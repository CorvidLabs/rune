# frozen_string_literal: true

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

      # RIS. Consumed but not acted on until now, under a comment asserting
      # ignored escapes cannot move the cursor — false for a full reset. The
      # trigger is someone typing `reset` or `tput init` to recover a garbled
      # agent TUI, which is exactly the moment a scroll region is live: a
      # stale region then confines every later line feed, IL, DL and scroll
      # for the rest of the render.
      def full_reset(_numbers = [])
        @grid = Array.new(@rows) { +'' }
        @saved = nil
        soft_reset
      end

      # DECSTR. Resets the region, origin and saved cursor, and homes the
      # cursor, but deliberately does not clear the display.
      def soft_reset(_numbers = [])
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
