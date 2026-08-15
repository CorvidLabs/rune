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
    # Deliberately not a full terminal emulator. It implements the sequences that
    # decide *where text lands*: cursor motion, erasing, and line discipline.
    # Everything else — colours, modes, title strings — is consumed and
    # discarded, because it cannot move the cursor and so cannot change the text
    # on the screen.
    class ScreenRenderer
      DEFAULT_ROWS = 40
      DEFAULT_COLUMNS = 120
      # Bounds the work for a long-lived session, whose transcript grows without
      # limit. Only the tail can still be on screen: a full repaint cycle of a
      # 40x120 terminal is a few KB, so this is orders of magnitude of headroom.
      DEFAULT_TAIL_BYTES = 256 * 1024
      TAB_WIDTH = 8
      # Everything that is not a control this renderer acts on. Scanned in bulk
      # so an ordinary line of output costs one match rather than one per byte.
      PRINTABLE = /[^\e\r\n\x08\t]+/
      # CSI final byte to the operation it performs. A table rather than a case
      # so that adding a sequence is a line, not a branch.
      CONTROLS = {
        'A' => :cursor_up, 'B' => :cursor_down, 'C' => :cursor_right, 'D' => :cursor_left,
        'E' => :cursor_next_line, 'F' => :cursor_previous_line, 'G' => :cursor_column,
        'H' => :cursor_position, 'f' => :cursor_position,
        'J' => :erase_display, 'K' => :erase_line
      }.freeze

      class << self
        # Renders `text` and returns the visible screen, with trailing blank
        # lines removed and each line right-trimmed.
        def render(text, rows: DEFAULT_ROWS, columns: DEFAULT_COLUMNS, tail_bytes: DEFAULT_TAIL_BYTES)
          return '' if text.nil? || text.empty?

          new(rows: rows, columns: columns).render(tail(text, tail_bytes))
        end

        private

        # Starting mid-stream can only mislead about the first line, and a
        # partial escape sequence at the cut is consumed harmlessly as text.
        def tail(text, tail_bytes)
          return text if tail_bytes.nil? || text.bytesize <= tail_bytes

          text.byteslice(-tail_bytes, tail_bytes).to_s.scrub
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
        when "\n" then @screen.newline
        when "\x08" then @screen.backspace
        when "\t" then @screen.tab(TAB_WIDTH)
        end
      end

      def escape(scanner)
        csi = scanner.scan(/\[[0-9;?<>=!]*[@-~]/)
        return csi_control(csi) if csi

        # Consumed and ignored: none of these can move the cursor, so none of
        # them can change the text on the screen.
        scanner.scan(/\][^\a\e]*(?:\a|\e\\)/) || scanner.scan(/[PX^_][^\e]*\e\\/) ||
          scanner.scan(/[()][AB0K]/) || scanner.scan(/[=><78]/)
      end

      def csi_control(csi)
        operation = CONTROLS[csi[-1]]
        return unless operation

        @screen.public_send(operation, csi[1..-2].to_s.delete('?<>=!').split(';').map(&:to_i))
      end

      # The grid and cursor a terminal would maintain. Separated from the
      # stream parsing above so each half is legible on its own: this one knows
      # nothing about escape sequences, only about where text goes.
      class Screen
        def initialize(rows:, columns:)
          @rows = rows.positive? ? rows : DEFAULT_ROWS
          @columns = columns.positive? ? columns : DEFAULT_COLUMNS
          @grid = Array.new(@rows) { +'' }
          @row = 0
          @column = 0
        end

        def to_s = @grid.map(&:rstrip).join("\n").sub(/\n+\z/, '')

        def write(chunk)
          chunk.each_char do |char|
            # Wrapping matters: an agent's status line is usually written to the
            # full width, and without it the tail would overwrite the same cell.
            wrap if @column >= @columns
            pad
            @grid[@row][@column] = char
            @column += 1
          end
        end

        def carriage_return = @column = 0

        # Not an endless method: `def backspace = ... if ...` binds the modifier
        # to the definition itself, so the guard runs once at class-definition
        # time against a nil ivar rather than per call.
        def backspace
          @column -= 1 if @column.positive?
        end

        def tab(width) = @column = [((@column / width) + 1) * width, @columns - 1].min

        def newline
          if @row >= @rows - 1
            @grid.shift
            @grid.push(+'')
          else
            @row += 1
          end
        end

        def cursor_up(numbers) = @row = (@row - count(numbers)).clamp(0, @rows - 1)

        def cursor_down(numbers) = @row = (@row + count(numbers)).clamp(0, @rows - 1)

        def cursor_right(numbers) = @column = (@column + count(numbers)).clamp(0, @columns - 1)

        def cursor_left(numbers) = @column = (@column - count(numbers)).clamp(0, @columns - 1)

        def cursor_next_line(numbers) = move_line(count(numbers))

        def cursor_previous_line(numbers) = move_line(-count(numbers))

        def cursor_column(numbers) = @column = (count(numbers) - 1).clamp(0, @columns - 1)

        def cursor_position(numbers)
          @row = (count(numbers) - 1).clamp(0, @rows - 1)
          @column = (count(numbers.drop(1)) - 1).clamp(0, @columns - 1)
        end

        def erase_display(numbers)
          case numbers.first.to_i
          when 0
            erase_line([0])
            ((@row + 1)...@rows).each { |row| @grid[row] = +'' }
          when 1
            erase_line([1])
            (0...@row).each { |row| @grid[row] = +'' }
          else
            @grid = Array.new(@rows) { +'' }
          end
        end

        # Both directions include the cell under the cursor, per ECMA-48. Mode 1
        # excluded it, so `ABCD` with the cursor on column 3 erased back to
        # `  CD` where a real terminal leaves `   D` — one character of a
        # repainted line surviving that should not have. Found by having grok
        # review this file through rune.
        def erase_line(numbers)
          line = @grid[@row]
          @grid[@row] = case numbers.first.to_i
                        when 0 then line[0, @column].to_s
                        when 1 then (' ' * (@column + 1)) + line[(@column + 1)..].to_s
                        else +''
                        end
        end

        private

        # A missing or zero parameter means 1 in every sequence handled here.
        def count(numbers)
          value = numbers.first.to_i
          value.positive? ? value : 1
        end

        def move_line(delta)
          @row = (@row + delta).clamp(0, @rows - 1)
          @column = 0
        end

        def wrap
          @column = 0
          newline
        end

        def pad
          line = @grid[@row]
          line << (' ' * (@column - line.length)) if line.length < @column
        end
      end
    end
  end
end
