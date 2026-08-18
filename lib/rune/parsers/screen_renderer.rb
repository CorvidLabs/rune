# frozen_string_literal: true

require 'strscan'
require_relative 'screen'

module Rune
  module Parsers
    # Replays a terminal byte stream onto a virtual screen and returns what a
    # terminal would actually be showing.
    #
    # `TextSanitizer` deletes escape sequences; it does not *obey* them. For a
    # command that merely colours its output the difference does not matter. For
    # a full-screen agent CLI it is the whole problem: the child repaints the
    # same region continuously, so stripping escapes yields every frame of every
    # repaint concatenated. Measured while dogfooding `rune session` against
    # grok, a 13-character answer arrived inside 13777 bytes of repaints; the
    # answer was absent from all 10333 bytes of `clean_output` because repaints
    # had split it, and present in the 1233-byte rendered screen.
    #
    # Not a full terminal emulator, but the boundary is specific: it implements
    # everything that decides *where text lands* — cursor motion, erasing,
    # insert and delete, scrolling, and line discipline — and consumes only what
    # genuinely cannot move the cursor, such as colours and title strings. An
    # earlier version claimed that boundary while ignoring `ESC D`/`E`/`M`,
    # cursor save/restore, `VPA`, and the insert/delete family; the first of
    # those printed a literal `D` into the output.
    # rubocop:disable Metrics/ClassLength -- 101 code lines across 267 physical: the length is one
    # documented rationale per escape, and each of those comments exists because the sequence above
    # it was got wrong once. The tables and the dispatch that reads them have to stay together —
    # `ESC D` printed a literal `D` precisely because a sequence was absent from the table the
    # dispatch consults, and the state half was already extracted into `Screen` for exactly this
    # ceiling. Splitting the grammar from its own vocabulary would hide that class of bug again.
    class ScreenRenderer
      DEFAULT_ROWS = 40
      DEFAULT_COLUMNS = 120
      # Ceilings on a *caller-supplied* size. The grid is allocated eagerly, so
      # a dimension arriving from outside this process — a session's recorded
      # winsize, read back out of a JSON file — must not be able to ask for an
      # arbitrary allocation.
      #
      # A last-resort backstop, not the operating limit. A caller that owns the
      # size is expected to clamp it where it records it, tighter and against
      # what a terminal can actually be: `Session::Supervisor` clamps a resize to
      # 300x1000 before it ever reaches meta.json. These bounds exist for a size
      # that reached the renderer without passing through anything that did —
      # a hand-edited meta, a directory written by another version — where the
      # answer that matters is "a bounded grid" rather than any particular one.
      MAX_ROWS = 1000
      MAX_COLUMNS = 2000
      # Bounds the work for a long-lived session, whose transcript grows without
      # limit. Only the tail can still be on screen: a full repaint cycle of a
      # 40x120 terminal is a few KB, so this is orders of magnitude of headroom.
      # Measured, not derived — and deliberately not called "sufficient".
      #
      # The old 256KB came from "a full repaint of a 40x120 terminal is a few
      # KB", which holds for a plain program and is wrong by roughly 50x for a
      # TUI spending most of its bytes on colour and cursor positioning. On one
      # 5.5MB grok transcript 256KB renders 1782 bytes of screen where 512KB
      # renders 1990 and holds there through 2MB.
      #
      # But two transcripts from the *same child* disagree about whether any
      # constant converges. A second 5.08MB grok session, measured independently,
      # converges at no window up to 1MB and is non-monotonic well inside that
      # range — 393,216 and 786,432 both render 3074 bytes while 524,288 between
      # them renders 3123. A long session simply accumulates more content that
      # was painted once and never repainted, and no window can recover it.
      #
      # So 512KB is justified as *better*, never as *enough*: it renders strictly
      # more of the screen than 256KB on both corpora, at ~52ms against ~26ms,
      # paid per `--screen` read rather than per pty read. A kimi corpus converges
      # at 32KB and pays 13x here for grok's benefit.
      #
      # The real answer is not a bigger constant, and not "grow until two sizes
      # agree" either — that rule would terminate on the coincidental 3074/3074
      # match above. It is to retain one `Screen` per session and feed it each
      # chunk as it arrives, which removes the window entirely.
      DEFAULT_TAIL_BYTES = 512 * 1024
      # How far past the cut to look for an escape to resync on. Comfortably
      # more than any CSI sequence, and small enough that a stream containing
      # no escapes at all keeps essentially all of its text.
      RESYNC_SCAN_BYTES = 256
      TAB_WIDTH = 8
      # Everything that is not a control this renderer acts on. Vertical tab and
      # form feed are line-feed class motion, not text, and were previously
      # written into the screen as characters.
      # Bytes excluded here fall through `control_byte`'s case, which has no
      # branch for BEL/NUL/SO/SI/DEL, so they are consumed and dropped. A
      # non-graphic character occupies no cell in any terminal, and writing one
      # shifted the rest of the line: `TERM=screen tput sgr0` is `\e[m\x0f\x0f`,
      # so ncurses under tmux injected two literal cells on every attribute
      # reset. Verified against GNU screen and pyte, which agree on all five.
      PRINTABLE = /[^\e\r\n\x08\x0b\x0c\t\a\x00\x0e\x0f\x7f]+/
      # The ECMA-48 CSI grammar: parameter bytes 0x30-0x3F, then intermediate
      # bytes 0x20-0x2F, then one final byte 0x40-0x7E.
      #
      # The previous pattern allowed neither `:` nor the intermediates, so
      # `\e[2 q` (DECSCUSR — set cursor shape, emitted by fish, starship, zsh
      # vi-mode and Codex CLI) and `\e[38:2::255:0:0m` (the ITU-T T.416 colon
      # form of truecolour SGR) did not match, fell through, and were *printed*:
      # a real capture of one agent contained 80 such sequences.
      CSI = %r{\[[0-9:;<=>?]*[ -/]*[@-~]}
      # Escape forms that cannot move the cursor, so can be consumed and
      # dropped — but must be *consumed*, since anything left behind is printed.
      IGNORED = [
        /\][^\a\e]*(?:\a|\e\\)/,          # OSC, terminated by BEL or ST
        /[PX^_][^\e]*\e\\/,               # DCS, SOS, PM, APC
        %r{[()*+][A-Za-z0-9<>%"&./:?-]},   # charset designation into G0-G3
        /[%#][@A-Za-z0-9]/,                # UTF-8 select, DEC screen alignment
        /[=><HNOZlmno|}~]/,                # keypad mode, HTS, SS2/SS3, ...
        / [FGLMN]/                         # ANSI conformance level
      ].freeze
      # A sequence the buffer ended in the middle of, with its terminator not
      # yet arrived.
      INCOMPLETE = %r{\A(?:\[[0-9:;<=>?]*[ -/]*|\][^\a\e]*|[PX^_][^\e]*|[()*+#% ])\z}
      # CSI final byte to the operation it performs. A table rather than a case
      # so that adding a sequence is a line, not a branch.
      # Control byte to the operation it performs, a table for the same reason
      # CONTROLS is one. SO/SI select G1/G0 and were previously consumed and
      # dropped, which is correct only while no slot can hold anything but ASCII.
      BYTE_CONTROLS = {
        "\r" => :carriage_return, "\n" => :newline, "\v" => :newline, "\f" => :newline,
        "\x08" => :backspace, "\x0e" => :shift_out, "\x0f" => :shift_in
      }.freeze

      # `CSI Pm h/l`, with an optional private prefix. Nothing else may reach the
      # mode path: an intermediate byte selects a different function entirely.
      MODE_FORM = /\A\[(\??)[\d;]*[hl]\z/
      CONTROLS = {
        'A' => :cursor_up, 'B' => :cursor_down, 'C' => :cursor_right, 'D' => :cursor_left,
        'E' => :cursor_next_line, 'F' => :cursor_previous_line, 'G' => :cursor_column,
        'd' => :cursor_row, 'H' => :cursor_position, 'f' => :cursor_position,
        'J' => :erase_display, 'K' => :erase_line,
        '@' => :insert_blanks, 'P' => :delete_characters, 'X' => :erase_characters,
        'L' => :insert_lines, 'M' => :delete_lines, 'S' => :scroll_up, 'T' => :scroll_down,
        'r' => :scroll_region,
        's' => :save_cursor, 'u' => :restore_cursor
      }.freeze
      # Single-byte escapes that move the cursor, so cannot be discarded.
      ESCAPES = {
        'D' => :index, 'E' => :next_line, 'M' => :reverse_index,
        '7' => :save_cursor, '8' => :restore_cursor, 'c' => :full_reset
      }.freeze

      class << self
        # Renders `text` and returns the visible screen, with trailing blank
        # lines removed and each line right-trimmed.
        def render(text, rows: nil, columns: nil, tail_bytes: DEFAULT_TAIL_BYTES)
          return '' if text.nil? || text.empty?

          height, width = dimensions(rows, columns)
          # The window has to hold one full repaint of the grid being rendered
          # or the render is silently short. DEFAULT_TAIL_BYTES was justified by
          # "a full repaint of a 40x120 terminal is a few KB", true while 40x120
          # was the only size this could render; once a session records its
          # child's real winsize, break-even is 260 rows at 1000 columns, and a
          # 300x1000 repaint left 40 of 300 rows blank while the reply asserted
          # the geometry was trustworthy. Eight bytes a row for the escapes a
          # repaint wraps around its text.
          window = tail_bytes && [tail_bytes, height * (width + 8)].max
          new(rows: height, columns: width).render(tail(text, window))
        end

        # The size a render will actually use, given what the caller asked for.
        # Exposed rather than kept private because a caller that reports which
        # geometry a screen was rendered at must report the effective one: a
        # session records its child's winsize on disk, and "unknown" (an old
        # session directory), "0x0" (a pty whose size was never set) and
        # "garbage" all have to resolve to something before they are shown.
        def dimensions(rows, columns)
          [dimension(rows, DEFAULT_ROWS, MAX_ROWS), dimension(columns, DEFAULT_COLUMNS, MAX_COLUMNS)]
        end

        private

        # `exception: false` rather than a rescue because every way this can
        # fail is the same answer: nil, a string that is not a number, a hash
        # out of a mangled JSON file.
        def dimension(value, fallback, ceiling)
          value = Integer(value, exception: false)
          value&.positive? ? [value, ceiling].min : fallback
        end

        # Starting mid-stream can only mislead about the first line.
        #
        # A partial escape sequence at the cut is *not* harmless, which this
        # comment claimed until a census of a real agent's output showed why it
        # matters. The remainder of a sliced sequence has no `ESC` left to
        # identify it, so it is printed: cutting inside `\e[?2026h` puts a
        # literal `?2026h` on the screen, at whatever position the cursor
        # happens to hold. Resyncing to the first `ESC` drops that remainder.
        def tail(text, tail_bytes)
          return text if tail_bytes.nil? || text.bytesize <= tail_bytes

          resync(text.byteslice(-tail_bytes, tail_bytes).to_s.scrub)
        end

        # The scan is bounded because a cut can also land in plain text, where
        # there is no way to tell the two apart and the next `ESC` may be far
        # away or absent. Dropping a couple of lines from the start of a 256KB
        # window costs nothing — that first line is already unreliable — while
        # dropping to the next escape in a stream that has none would discard
        # the whole screen.
        def resync(window)
          # `.b` first, because `String#index` counts characters and `byteslice` counts bytes. On a
          # multi-byte head the two differ by however many extra bytes it holds, so the slice landed
          # early — measured on `日本語テキスト\e[1mAFTER`, the ESC is at character 7 and byte 21, and
          # resync cut at 7: it returned `"\xAA\x9Eテキスト\e[1mAFTER"`, both cutting a character in
          # half and failing to drop the pre-ESC remainder it exists to drop. `byteindex` would say
          # this directly but arrived in Ruby 3.2, and this gem supports 3.0.
          escape = window.byteslice(0, RESYNC_SCAN_BYTES).to_s.b.index("\e")
          return window if escape.nil? || escape.zero?

          window.byteslice(escape..).to_s
        end
      end

      def initialize(rows: nil, columns: nil)
        rows, columns = self.class.dimensions(rows, columns)
        @screen = Screen.new(rows: rows, columns: columns)
      end

      def render(text)
        scan(text.scrub)
        @screen.to_s
      end

      private

      def scan(text)
        scanner = StringScanner.new(text)
        until scanner.eos?
          chunk = scanner.scan(PRINTABLE)
          chunk ? @screen.write(chunk) : control_byte(scanner)
        end
      end

      # `getch` always consumes, so this loop cannot fail to advance. An earlier
      # version dispatched on `scanner.scan(/\b/)`, which outside a character
      # class is a zero-width *word boundary*: it matched without consuming, and
      # rendering any stream containing a backspace hung forever.
      def control_byte(scanner)
        byte = scanner.getch
        return escape(scanner) if byte == "\e"
        return @screen.tab(TAB_WIDTH) if byte == "\t"

        operation = BYTE_CONTROLS[byte]
        @screen.public_send(operation) if operation
      end

      def escape(scanner)
        csi = scanner.scan(CSI)
        return csi_control(csi) if csi

        single = scanner.scan(/[DEM78c]/)
        return @screen.public_send(ESCAPES.fetch(single), []) if single

        # Charset designation, `ESC ( <final>` / `ESC ) <final>`. Consumed by
        # IGNORED until now, which was right while nothing could act on it and
        # wrong once the graphics set existed: ncurses draws every box from it,
        # so a dropped designation printed `qqq` where a border belonged.
        designation = scanner.scan(%r{[()][A-Za-z0-9<>%"&./:?-]})
        return @screen.designate_charset(designation[0] == '(' ? 'G0' : 'G1', designation[1]) if designation

        # Consumed and ignored: none of these can move the cursor, so none of
        # them can change the text on the screen.
        #
        # The list is long because anything *not* consumed here is printed. ESC
        # is already gone by the time we arrive, so an unrecognised escape
        # leaves its body to be matched by PRINTABLE and written onto the
        # screen — the same failure as the `ESC D` that printed a literal `D`,
        # which was fixed for three escapes and left in place for the rest.
        # `\ec` put a literal `c` on screen, `\e(1` a `(1`, `\eN` an `N`.
        IGNORED.any? { |pattern| scanner.scan(pattern) } || incomplete(scanner)
      end

      # `\e[?1049h` and `\e[4h` differ only in where the parameters start.
      def apply_modes(csi, private_form)
        enable = csi[-1] == 'h'
        parameters = csi[(private_form ? 2 : 1)..-2].to_s
        private_form ? @screen.private_modes(parameters, enable) : @screen.ansi_modes(parameters, enable)
      end

      # A sequence the buffer ended in the middle of. Consumed rather than
      # printed, because a real terminal holds an incomplete sequence in its
      # parser and shows nothing. This is the normal case rather than an edge
      # one: a live session's transcript ends wherever the last read landed, so
      # `read --screen` regularly renders a stream cut mid-escape. Truncating
      # the *start* of the window was fixed first; this is the same bug at the
      # other end.
      def incomplete(scanner)
        scanner.terminate if scanner.rest.match?(INCOMPLETE)
      end

      def csi_control(csi)
        # DECSTR, a soft reset. It carries an intermediate byte, so both guards
        # below reject it, and its final byte is not in CONTROLS — it was
        # dropped twice over. terminfo's `rs2`/`is2` for xterm begin with it.
        return @screen.soft_reset([]) if csi == '[!p'

        # Mode changes, before the guard below drops every `?` form: the private
        # ones decide what the grid *contains*, not how hardware behaves.
        mode = csi.match(MODE_FORM)
        return apply_modes(csi, mode[1] == '?') if mode

        operation = CONTROLS[csi[-1]]
        parameters = csi[1..-2].to_s
        # Private-parameter forms are modes (`\e[?25l`, `\e[?1049h`) or vendor
        # extensions, never the public operation sharing the final byte. `?` was
        # guarded and `<`, `>`, `=` were not, though all four are ECMA-48
        # private-prefix bytes: kitty's `\e[<u`, `\e[>1u` and `\e[=5;1u` all ran
        # DECRC and teleported the cursor, and `\e[>2T` ran SD and scrolled.
        # Across 451 real captures on one machine there were 242 `CSI <u`, 244
        # `CSI >u`, 40 `CSI =u` and *zero* public `CSI u`, so the restore-cursor
        # row never once fired correctly on real agent output.
        return if operation.nil? || csi.match?(/[?<>=]/)
        # An intermediate byte selects a *different* function sharing the same
        # final byte, so honouring one as its plain namesake would act on a
        # sequence that means something else entirely.
        return if parameters.match?(%r{[ -/]})

        @screen.public_send(operation, parameters.delete('<>=!').split(';').map(&:to_i))
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
