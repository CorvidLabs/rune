# frozen_string_literal: true

require 'strscan'

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
    class ScreenRenderer
      DEFAULT_ROWS = 40
      DEFAULT_COLUMNS = 120
      # Bounds the work for a long-lived session, whose transcript grows without
      # limit. Only the tail can still be on screen: a full repaint cycle of a
      # 40x120 terminal is a few KB, so this is orders of magnitude of headroom.
      DEFAULT_TAIL_BYTES = 256 * 1024
      # How far past the cut to look for an escape to resync on. Comfortably
      # more than any CSI sequence, and small enough that a stream containing
      # no escapes at all keeps essentially all of its text.
      RESYNC_SCAN_BYTES = 256
      TAB_WIDTH = 8
      # Everything that is not a control this renderer acts on. Vertical tab and
      # form feed are line-feed class motion, not text, and were previously
      # written into the screen as characters.
      PRINTABLE = /[^\e\r\n\x08\x0b\x0c\t]+/
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
        /[=><cHNOZlmno|}~]/,               # keypad mode, RIS, HTS, SS2/SS3, ...
        / [FGLMN]/                         # ANSI conformance level
      ].freeze
      # A sequence the buffer ended in the middle of, with its terminator not
      # yet arrived.
      INCOMPLETE = %r{\A(?:\[[0-9:;<=>?]*[ -/]*|\][^\a\e]*|[PX^_][^\e]*|[()*+#% ])\z}
      # CSI final byte to the operation it performs. A table rather than a case
      # so that adding a sequence is a line, not a branch.
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
        '7' => :save_cursor, '8' => :restore_cursor
      }.freeze

      class << self
        # Renders `text` and returns the visible screen, with trailing blank
        # lines removed and each line right-trimmed.
        def render(text, rows: DEFAULT_ROWS, columns: DEFAULT_COLUMNS, tail_bytes: DEFAULT_TAIL_BYTES)
          return '' if text.nil? || text.empty?

          new(rows: rows, columns: columns).render(tail(text, tail_bytes))
        end

        private

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
          escape = window.byteslice(0, RESYNC_SCAN_BYTES).to_s.index("\e")
          return window if escape.nil? || escape.zero?

          window.byteslice(escape..).to_s
        end
      end

      def initialize(rows: DEFAULT_ROWS, columns: DEFAULT_COLUMNS)
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
        case scanner.getch
        when "\e" then escape(scanner)
        when "\r" then @screen.carriage_return
        when "\n", "\v", "\f" then @screen.newline
        when "\x08" then @screen.backspace
        when "\t" then @screen.tab(TAB_WIDTH)
        end
      end

      def escape(scanner)
        csi = scanner.scan(CSI)
        return csi_control(csi) if csi

        single = scanner.scan(/[DEM78]/)
        return @screen.public_send(ESCAPES.fetch(single), []) if single

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
        operation = CONTROLS[csi[-1]]
        parameters = csi[1..-2].to_s
        # Private-parameter forms are modes (`\e[?25l`, `\e[?1049h`), never
        # cursor motion, and must not be mistaken for their public namesakes.
        return if operation.nil? || csi.include?('?')
        # An intermediate byte selects a *different* function sharing the same
        # final byte, so honouring one as its plain namesake would act on a
        # sequence that means something else entirely.
        return if parameters.match?(%r{[ -/]})

        @screen.public_send(operation, parameters.delete('<>=!').split(';').map(&:to_i))
      end

      # The grid and cursor a terminal would maintain. Separated from the
      # stream parsing above so each half is legible on its own: this one knows
      # nothing about escape sequences, only about where text goes.
      #
      # rubocop:disable Metrics/ClassLength -- every method here mutates the same three pieces of
      # state (grid, cursor, pending wrap) and the deferred-wrap rule couples them: splitting the
      # operations across classes would put that rule out of sight of the methods that must honour
      # it, which is how the last-column bugs got in.
      class Screen
        def initialize(rows:, columns:)
          @rows = rows.positive? ? rows : DEFAULT_ROWS
          @columns = columns.positive? ? columns : DEFAULT_COLUMNS
          @grid = Array.new(@rows) { +'' }
          @row = 0
          @column = 0
          # xterm's "deferred wrap": after writing the last cell the cursor
          # stays on it and the wrap happens when the *next* graphic arrives.
          # Leaving the column one past the end instead put the cursor in a
          # state no terminal uses, which every relative move then read wrong.
          @wrap_pending = false
          @saved = nil
          # DECSTBM. Scrolling happens at the region's edges, not the screen's,
          # and every pager, editor and full-screen agent sets one: `less`,
          # `vim`, `htop`, Codex CLI and Claude Code all define a region and
          # then rely on a line feed at its bottom to scroll. Ignoring `\e[t;br`
          # meant a line feed at the region bottom walked down the page
          # instead. Replaying two real captured agent transcripts, 8 of 40
          # rows differed from a reference emulator; stripping only the region
          # sequences from the same bytes dropped that to 0.
          @top = 0
          @bottom = @rows - 1
        end

        # DECSTBM. Out-of-order or out-of-range bounds are ignored wholesale, as
        # a real terminal does, rather than half-applied.
        def scroll_region(numbers)
          top = (numbers[0].to_i.positive? ? numbers[0].to_i : 1) - 1
          bottom = (numbers[1].to_i.positive? ? numbers[1].to_i : @rows) - 1
          return unless top < bottom && top >= 0 && bottom <= @rows - 1

          @top = top
          @bottom = bottom
          # DECSTBM homes the cursor, which is why a pager can set a region and
          # start drawing without a separate CUP.
          move_to(0, 0)
        end

        def to_s = @grid.map(&:rstrip).join("\n").sub(/\n+\z/, '')

        def write(chunk)
          chunk.each_char do |char|
            wrap if @wrap_pending
            pad
            @grid[@row][@column] = char
            advance
          end
        end

        def carriage_return
          @column = 0
          @wrap_pending = false
        end

        # Not an endless method: `def backspace = ... if ...` binds the modifier
        # to the definition, so the guard runs once at class-definition time
        # against a nil ivar rather than per call.
        def backspace
          @column -= 1 if @column.positive?
          @wrap_pending = false
        end

        def tab(width)
          @column = [((@column / width) + 1) * width, @columns - 1].min
          @wrap_pending = false
        end

        def newline
          @wrap_pending = false
          return @row += 1 if @row < @bottom
          # Below the region entirely: a line feed still moves down, and only
          # the screen's own last row can stop it.
          return @row += 1 if @row > @bottom && @row < @rows - 1
          return if @row > @bottom

          scroll_region_up(1)
        end

        # ESC D / ESC E / ESC M. Previously unrecognised, so the escape was
        # eaten and the letter written as text: `hello\eDworld` rendered as
        # `helloDworld`.
        def index(_numbers = []) = newline

        def next_line(_numbers = [])
          newline
          @column = 0
        end

        def reverse_index(_numbers = [])
          @wrap_pending = false
          return @row -= 1 if @row > @top || (@row.positive? && @row < @top)
          return if @row != @top

          scroll_region_down(1)
        end

        # DECSC/DECRC and CSI s/u. Ignoring these was justified in a comment
        # claiming the ignored sequences could not move the cursor, which is
        # exactly what restore does.
        def save_cursor(_numbers = []) = @saved = [@row, @column, @wrap_pending]

        def restore_cursor(_numbers = [])
          return unless @saved

          @row, @column, @wrap_pending = @saved
        end

        def cursor_up(numbers) = move_to(@row - count(numbers), @column)

        def cursor_down(numbers) = move_to(@row + count(numbers), @column)

        def cursor_right(numbers) = move_to(@row, @column + count(numbers))

        def cursor_left(numbers) = move_to(@row, @column - count(numbers))

        def cursor_next_line(numbers) = move_to(@row + count(numbers), 0)

        def cursor_previous_line(numbers) = move_to(@row - count(numbers), 0)

        def cursor_column(numbers) = move_to(@row, count(numbers) - 1)

        # VPA: the row moves, the column does not.
        def cursor_row(numbers) = move_to(count(numbers) - 1, @column)

        def cursor_position(numbers) = move_to(count(numbers) - 1, count(numbers.drop(1)) - 1)

        def erase_display(numbers)
          @wrap_pending = false
          case numbers.first.to_i
          when 0
            erase_line([0])
            ((@row + 1)...@rows).each { |row| @grid[row] = +'' }
          when 1
            erase_line([1])
            (0...@row).each { |row| @grid[row] = +'' }
          when 2
            @grid = Array.new(@rows) { +'' }
          end
          # 3 is "erase saved lines" — the scrollback, which this renderer does
          # not keep — and anything else is undefined. Both were reaching an
          # `else` that cleared the display, so `\e[3J` (emitted by `clear` and
          # by several TUIs on startup) wiped output that is still on screen.
        end

        # Both directions include the cell under the cursor, per ECMA-48. Mode 1
        # excluded it, so `ABCD` with the cursor on column 3 erased back to
        # `  CD` where a real terminal leaves `   D`.
        def erase_line(numbers)
          @wrap_pending = false
          line = @grid[@row]
          # Only 0, 1 and 2 are defined; an unknown parameter is a no-op rather
          # than the full-line erase an `else` used to give it.
          @grid[@row] = case numbers.first.to_i
                        when 0 then line[0, @column].to_s
                        when 1 then (' ' * (@column + 1)) + line[(@column + 1)..].to_s
                        when 2 then +''
                        else line
                        end
        end

        # ICH: shift the rest of the line right, losing what falls off the edge.
        def insert_blanks(numbers)
          line = padded_line
          @grid[@row] =
            (line[0, @column].to_s + (' ' * span(numbers, @columns)) + line[@column..].to_s)[0, @columns].to_s
          @wrap_pending = false
        end

        # DCH: shift the rest of the line left over the deleted characters.
        def delete_characters(numbers)
          line = padded_line
          @grid[@row] = line[0, @column].to_s + line[(@column + span(numbers, @columns))..].to_s
          @wrap_pending = false
        end

        # ECH: blank characters in place, without shifting anything.
        def erase_characters(numbers)
          line = padded_line
          blanks = span(numbers, @columns)
          @grid[@row] = line[0, @column].to_s + (' ' * blanks) + line[(@column + blanks)..].to_s
          @wrap_pending = false
        end

        # IL/DL act from the cursor to the region bottom, and do nothing at all
        # outside the region.
        def insert_lines(numbers)
          @wrap_pending = false
          return unless @row.between?(@top, @bottom)

          span(numbers, @rows).times do
            @grid.insert(@row, +'')
            @grid.delete_at(@bottom + 1)
          end
        end

        def delete_lines(numbers)
          @wrap_pending = false
          return unless @row.between?(@top, @bottom)

          span(numbers, @rows).times do
            @grid.delete_at(@row)
            @grid.insert(@bottom, +'')
          end
        end

        def scroll_up(numbers)
          @wrap_pending = false
          scroll_region_up(span(numbers, @rows))
        end

        def scroll_down(numbers)
          @wrap_pending = false
          scroll_region_down(span(numbers, @rows))
        end

        # Scrolling is always confined to the region; with the default region
        # that is the whole screen, so the ordinary case is unchanged.
        def scroll_region_up(lines)
          lines.times do
            @grid.delete_at(@top)
            @grid.insert(@bottom, +'')
          end
        end

        def scroll_region_down(lines)
          lines.times do
            @grid.delete_at(@bottom)
            @grid.insert(@top, +'')
          end
        end

        private

        # A missing or zero parameter means 1 in every sequence handled here.
        def count(numbers)
          value = numbers.first.to_i
          value.positive? ? value : 1
        end

        # The same, bounded by the dimension the sequence operates on.
        #
        # A real terminal cannot insert more blanks than a line holds or scroll
        # by more rows than it has, so it clamps and returns immediately. rune
        # took the parameter literally and used it as an allocation or loop
        # bound, which made a single escape sequence in *child output* enough to
        # take the renderer down: `\e[99999999999999999999@` raised RangeError
        # out of `.render` and killed `read --screen`, `\e[999999999@` allocated
        # 2.9GB, and `\e[1000000L` never finished. This renders untrusted bytes,
        # so an unclamped count is a denial of service, not a cosmetic bug.
        def span(numbers, bound)
          [count(numbers), bound].min
        end

        # Every explicit move clears a pending wrap, which is what makes the
        # deferred-wrap state observable only to the next graphic character.
        def move_to(row, column)
          @row = row.clamp(0, @rows - 1)
          @column = column.clamp(0, @columns - 1)
          @wrap_pending = false
        end

        def advance
          if @column >= @columns - 1
            @wrap_pending = true
          else
            @column += 1
          end
        end

        def wrap
          @wrap_pending = false
          @column = 0
          newline
        end

        def padded_line
          pad
          @grid[@row]
        end

        def pad
          line = @grid[@row]
          line << (' ' * (@column - line.length)) if line.length < @column
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
