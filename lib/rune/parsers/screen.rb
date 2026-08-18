# frozen_string_literal: true

require_relative 'character_width'

module Rune
  module Parsers
    # The grid and cursor a terminal would maintain, extracted from
    # `ScreenRenderer` once that class had grown to hold two separable things:
    # parsing a byte stream, and the state that stream mutates. The split is the
    # same one already made for `Session::Transcript` and `Session::PendingSend`,
    # and for the same reason — this half knows nothing about escape sequences,
    # only about where text goes.
    # rubocop:disable Metrics/ClassLength -- every method here mutates the same three pieces of
    # state (grid, cursor, pending wrap) and the deferred-wrap rule couples them: splitting the
    # operations across classes would put that rule out of sight of the methods that must honour
    # it, which is how the last-column bugs got in.
    class Screen
      def initialize(rows:, columns:)
        @rows = rows.positive? ? rows : DEFAULT_ROWS
        @columns = columns.positive? ? columns : DEFAULT_COLUMNS
        @grid = Array.new(@rows) { [] }
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
        # The primary buffer's grid while the alternate one is in use, and nil
        # otherwise — so "am I in the alternate buffer" and "what do I restore"
        # are one piece of state rather than two that can disagree.
        @alternate = nil
        # DECAWM, on by default as every terminal ships it. A TUI turns it off
        # to write the last cell of a row without scrolling the screen, which is
        # why status bars and box borders depend on it.
        @autowrap = true
        # IRM. Off by default; with it on, a graphic shifts the rest of the line
        # right instead of overwriting. `zsh`'s line editor sets it to insert a
        # character mid-line without repainting the tail.
        @insert = false
        # G0/G1 charset designations and which of them GL currently selects.
        # `ESC ( 0` designates DEC Special Graphics into G0, which is how
        # ncurses draws a box from `acsc` — the letters q, x, l, k are the line
        # glyphs, so leaving the designation unhandled printed `qqq` where a
        # border belonged.
        @charsets = { 'G0' => :ascii, 'G1' => :ascii }
        @gl = 'G0'
      end

      # RIS. Consumed but not acted on until now, under a comment asserting
      # ignored escapes cannot move the cursor — false for a full reset. The
      # trigger is someone typing `reset` or `tput init` to recover a garbled
      # agent TUI, which is exactly the moment a scroll region is live: a
      # stale region then confines every later line feed, IL, DL and scroll
      # for the rest of the render.
      def full_reset(_numbers = [])
        # RIS returns to the primary buffer and to autowrap on, like a terminal
        # power-cycling. Clearing the grid while still holding the alternate
        # buffer's would have left the primary's contents to reappear at the
        # next `\e[?1049l` — a reset that resurrects pre-reset output.
        @alternate = nil
        @autowrap = true
        @charsets = { 'G0' => :ascii, 'G1' => :ascii }
        @gl = 'G0'
        @grid = Array.new(@rows) { [] }
        @saved = nil
        soft_reset
      end

      # DECSTR. Resets the region, origin and saved cursor, and homes the
      # cursor, but deliberately does not clear the display.
      def soft_reset(_numbers = [])
        @insert = false
        @top = 0
        @bottom = @rows - 1
        @saved = nil
        @wrap_pending = false
        @row = 0
        @column = 0
      end

      # DECSTBM. A bottom past the last row is clamped rather than discarded:
      # discarding leaves the *previous* region in force, which is worse than
      # doing nothing now that regions exist. xterm, xterm.js, VTE, st, tmux
      # and pyte all clamp; GNU screen does discard, so this is a real
      # divergence and clamping is the majority side of it.
      def scroll_region(numbers)
        top = (numbers[0].to_i.positive? ? numbers[0].to_i : 1) - 1
        bottom = (numbers[1].to_i.positive? ? numbers[1].to_i : @rows) - 1
        bottom = @rows - 1 if bottom > @rows - 1
        return unless top < bottom && top >= 0

        @top = top
        @bottom = bottom
        # DECSTBM homes the cursor, which is why a pager can set a region and
        # start drawing without a separate CUP.
        move_to(0, 0)
      end

      # A DEC private mode, `CSI ? Pm h` / `CSI ? Pm l`. Every private form used
      # to be dropped whole, which was right for the ones that only affect a
      # real terminal's hardware (cursor visibility, bracketed paste, mouse
      # reporting) and wrong for the two that decide what the grid contains.
      #
      # Modes not listed here are still ignored, deliberately: `\e[?25l` and
      # `\e[?2004h` change nothing a rendered frame can show, and guessing at an
      # unknown mode is how a renderer starts inventing output.
      # DEC Special Graphics, the `acsc` set every ncurses program draws boxes
      # with. Only 0x5F-0x7E are remapped; everything else passes through, which
      # is why text between `ESC ( 0` and `ESC ( B` is not mangled.
      GRAPHICS = {
        '_' => ' ', '`' => '◆', 'a' => '▒', 'b' => '␉', 'c' => '␌', 'd' => '␍', 'e' => '␊',
        'f' => '°', 'g' => '±', 'h' => '␤', 'i' => '␋', 'j' => '┘', 'k' => '┐', 'l' => '┌',
        'm' => '└', 'n' => '┼', 'o' => '⎺', 'p' => '⎻', 'q' => '─', 'r' => '⎼', 's' => '⎽',
        't' => '├', 'u' => '┤', 'v' => '┴', 'w' => '┬', 'x' => '│', 'y' => '≤', 'z' => '≥',
        '{' => 'π', '|' => '≠', '}' => '£', '~' => '·'
      }.freeze

      # `ESC ( <final>` and `ESC ) <final>`. `0` selects the graphics set; `B`
      # and every other designation returns that slot to ASCII, because guessing
      # at an unknown national set would corrupt text a terminal shows plainly.
      def designate_charset(slot, final)
        @charsets[slot] = final == '0' ? :graphics : :ascii
      end

      # SO and SI. A program that designates graphics into G1 shifts in and out
      # around each run rather than re-designating G0 every time.
      def shift_out = @gl = 'G1'
      def shift_in = @gl = 'G0'

      # ANSI (public) modes, `CSI Pm h/l`. Only IRM decides what the grid holds;
      # the rest govern a real terminal's input handling and are ignored.
      def ansi_modes(parameters, enable)
        parameters.split(';').each { |mode| @insert = enable if mode.to_i == 4 }
        nil
      end

      # `CSI ? 1049 ; 25 h` sets both, so each parameter applies in turn. An
      # empty list is `CSI ? h`, which selects nothing and must not read as 0.
      def private_modes(parameters, enable)
        parameters.split(';').reject(&:empty?).each { |mode| private_mode(mode.to_i, enable) }
        nil
      end

      def private_mode(mode, enable)
        return alternate_buffer(mode, enable) if ALTERNATE_MODES.key?(mode)
        return enable ? save_cursor : restore_cursor if mode == 1048

        @autowrap = enable if mode == 7
      end

      # xterm 1049 saves the cursor, switches to a cleared alternate buffer, and
      # restores both on exit. Agent CLIs enter it at startup, so without it
      # every byte printed before the switch stayed on the grid and
      # `read --screen` showed a shell banner underneath a TUI. 47 and 1047 are
      # the older forms and carry no cursor save — that is precisely why 1049
      # was added, so they are not given one here.
      ALTERNATE_MODES = { 1049 => true, 1047 => false, 47 => false }.freeze

      def alternate_buffer(mode, enable)
        saves_cursor = ALTERNATE_MODES.fetch(mode)
        enable ? enter_alternate(save: saves_cursor) : leave_alternate(restore: saves_cursor)
      end

      # The scroll region is deliberately not part of the snapshot. DECSTBM
      # margins belong to the terminal rather than to a buffer in xterm, so a
      # region set inside the alternate buffer survives the switch back — which
      # is what an application that sets one before switching depends on.
      def enter_alternate(save:)
        return if @alternate # 1049h while already alternate is idempotent, not a second save.

        save_cursor if save
        @alternate = @grid
        @grid = Array.new(@rows) { [] }
      end

      def leave_alternate(restore:)
        return unless @alternate

        @grid = @alternate
        @alternate = nil
        restore_cursor if restore
      end

      # A cell is nil (never written), a String holding one graphic plus any combining marks, or
      # CONTINUATION for the right half of a wide glyph. The continuation occupies a column for
      # every purpose except display, where it contributes nothing — so cursor arithmetic counts in
      # columns while the rendered line counts in characters, and a wide glyph is two of the former
      # and one of the latter.
      CONTINUATION = :wide_tail

      def to_s = @grid.map { |row| render_row(row).rstrip }.join("\n").sub(/\n+\z/, '')

      def render_row(row)
        row.each_with_index.map { |cell, index| render_cell(cell, row, index) }.join
      end

      def render_cell(cell, row, index)
        return ' ' if cell.nil?
        # An orphan continuation renders as a blank, not as nothing: `heal` normally removes them,
        # and one that survives must still hold its column open rather than silently shortening the
        # line.
        return wide?(row[index - 1]) && index.positive? ? '' : ' ' if cell == CONTINUATION

        cell
      end

      def wide?(cell) = cell.is_a?(String) && CharacterWidth.of(cell[0]) == 2

      # Restores the wide-glyph invariant after any operation that moved cells.
      #
      # Insert, delete, erase and scroll all slice the row, and any of them can separate a wide
      # glyph from its continuation. Teaching each one about pairs is what the first attempt at
      # this did, and it lost: measured on live grok output, `東 京` and `東h京` appeared where the
      # one-column renderer produced `東京`. Repairing once, after the fact, is the same invariant
      # expressed in one place instead of twelve.
      def heal(row)
        row.each_index do |index|
          if row[index] == CONTINUATION
            row[index] = nil unless index.positive? && wide?(row[index - 1])
          elsif wide?(row[index]) && row[index + 1] != CONTINUATION
            # Its other half is gone, so neither half can be shown: a terminal blanks both.
            row[index] = ' '
          end
        end
        row
      end

      def write(chunk)
        chunk.each_char { |char| write_char(translate(char)) }
      end

      # One graphic, placed according to how many columns it occupies.
      #
      # A combining mark takes none: it belongs to the glyph already written, so it is appended to
      # that cell rather than given one of its own. That is safe here and was not before — a cell
      # is one array slot however many characters it holds, where a String row put every later
      # index off by one and the next graphic overwrote the mark.
      def write_char(char)
        width = CharacterWidth.of(char)
        return combine(char) if width.zero?

        settle_wrap(width)
        # IRM: make room first, so the tail of the line shifts right rather than being overwritten.
        # ICH is the same operation, which is why this reuses it.
        insert_blanks([width]) if @insert
        place(char, width)
      end

      # Takes any pending wrap, and takes one early rather than split a wide glyph at the margin.
      #
      # With DECAWM off the pending wrap is never taken at all: the cursor stays on the last cell
      # and each further graphic overwrites it, which is what lets a TUI paint the bottom-right
      # corner of a border without scrolling the screen out from under itself. A terminal also
      # never splits a wide glyph across the margin — it wraps first and leaves the last cell blank
      # rather than painting half a character there.
      def settle_wrap(width)
        return @wrap_pending = false unless @autowrap

        wrap if @wrap_pending || (width == 2 && @column + 1 >= @columns)
      end

      def place(char, width)
        line = @grid[@row]
        line[@column] = char
        line[@column + 1] = CONTINUATION if width == 2
        heal(line)
        width.times { advance }
      end

      # A combining mark modifies the graphic before the cursor, and attaches to the wide glyph
      # itself rather than to its continuation.
      def combine(char)
        line = @grid[@row]
        target = @column.positive? ? @column - 1 : 0
        target -= 1 if line[target] == CONTINUATION && target.positive?
        return if line[target].nil? || line[target] == CONTINUATION

        line[target] = line[target] + char
      end

      def translate(char)
        return char unless @charsets[@gl] == :graphics

        GRAPHICS.fetch(char, char)
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
          ((@row + 1)...@rows).each { |row| @grid[row] = [] }
        when 1
          erase_line([1])
          (0...@row).each { |row| @grid[row] = [] }
        when 2
          @grid = Array.new(@rows) { [] }
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
        @grid[@row] = heal(case numbers.first.to_i
                           when 0 then line[0, @column].to_a
                           when 1 then Array.new(@column + 1) + line[(@column + 1)..].to_a
                           when 2 then []
                           else line
                           end)
      end

      # ICH: shift the rest of the line right, losing what falls off the edge.
      def insert_blanks(numbers)
        line = @grid[@row]
        @grid[@row] =
          heal((line[0, @column].to_a + Array.new(span(numbers, @columns)) + line[@column..].to_a)[0, @columns].to_a)
        @wrap_pending = false
      end

      # DCH: shift the rest of the line left over the deleted characters.
      def delete_characters(numbers)
        line = @grid[@row]
        @grid[@row] = heal(line[0, @column].to_a + line[(@column + span(numbers, @columns))..].to_a)
        @wrap_pending = false
      end

      # ECH: blank characters in place, without shifting anything.
      def erase_characters(numbers)
        line = @grid[@row]
        blanks = span(numbers, @columns)
        @grid[@row] = heal(line[0, @column].to_a + Array.new(blanks) + line[(@column + blanks)..].to_a)
        @wrap_pending = false
      end

      # IL/DL act from the cursor to the region bottom, and do nothing at all
      # outside the region.
      def insert_lines(numbers)
        @wrap_pending = false
        return unless @row.between?(@top, @bottom)

        span(numbers, @rows).times do
          @grid.insert(@row, [])
          @grid.delete_at(@bottom + 1)
        end
      end

      def delete_lines(numbers)
        @wrap_pending = false
        return unless @row.between?(@top, @bottom)

        span(numbers, @rows).times do
          @grid.delete_at(@row)
          @grid.insert(@bottom, [])
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
          @grid.insert(@bottom, [])
        end
      end

      def scroll_region_down(lines)
        lines.times do
          @grid.delete_at(@bottom)
          @grid.insert(@top, [])
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

      # No padding helper any more: assigning past the end of an Array fills the gap with nil,
      # and a nil cell renders as a blank. A String row had to be padded by hand first, and that
      # padding is what made every column index a byte index into text.
    end
    # rubocop:enable Metrics/ClassLength
  end
end
