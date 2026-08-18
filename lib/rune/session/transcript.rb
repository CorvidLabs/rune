# frozen_string_literal: true

require 'json'
require_relative '../parsers/screen_renderer'
require_relative '../parsers/text_sanitizer'

module Rune
  module Session
    # One session's durable transcript, and the questions asked of it.
    #
    # Read from the NDJSON log rather than over the control socket, so every one
    # of these works identically for a live session and for one whose supervisor
    # has already exited — and costs the supervisor's single thread nothing,
    # which matters because that thread also has to keep pumping a pty.
    #
    # Extracted from `SessionCommand` once this had grown to a third of that
    # file: reconstruction, cursor arithmetic across rotation, search and
    # rendering are one subject, and none of them need anything from the command
    # surface but a path.
    class Transcript
      # Text the log still holds, and where in it the stream is not contiguous.
      # A `truncated` event carries a dropped byte count so cursors stay
      # absolute: one taken before the drop still names the same position in the
      # stream, it just points at output no longer held.
      #
      # *Where* each drop sits is recorded, not just the total. Rotation drops a
      # prefix, so one running total was enough for it; a write that fails drops
      # a region in the *middle* of a stream that continues afterwards, and a
      # single total then shifts output the drop is not in front of — every
      # cursor issued before the hole resolving |hole| bytes early, which is
      # already-delivered output replayed as new.
      def self.load(path)
        return new(+'', 0) unless File.exist?(path)

        gaps = []
        text = File.foreach(path).with_object(+'') do |line, buffer|
          event = JSON.parse(line, symbolize_names: true)
          case event[:event]
          when 'output' then buffer << event[:text].to_s
          when 'truncated' then record_gap(gaps, buffer.bytesize, event[:dropped_bytes].to_i)
          end
        rescue JSON::ParserError
          next
        end
        new(text, gaps.last&.last.to_i, gaps)
      end

      # One hole, as the offset into the retained text where it sits and the
      # total dropped up to and including it. Two recorded at the same offset —
      # a rotation's own head event over a tail that already began with one — are
      # one hole in the stream and are merged, which keeps the prefix-only case a
      # single entry and its arithmetic exactly what it always was. A zero-byte
      # `truncated` (a lost event that carried no output) moves nothing and is
      # not a hole.
      def self.record_gap(gaps, offset, bytes)
        return unless bytes.positive?

        if gaps.last&.first == offset
          gaps[-1] = [offset, gaps.last.last + bytes]
        else
          gaps << [offset, gaps.last&.last.to_i + bytes]
        end
      end

      attr_reader :text, :dropped, :gaps

      def initialize(text, dropped, gaps = nil)
        @text = text
        @dropped = dropped
        # A caller that knows only a total is describing the prefix case, which
        # is the one shape a total on its own can describe.
        @gaps = gaps || (dropped.positive? ? [[0, dropped]] : [])
      end

      # Total bytes the child has produced, including everything dropped, which
      # is what a cursor counts.
      def cursor = @dropped + @text.bytesize

      # Everything from an absolute cursor onwards. A drop shifts where that
      # lands in what is still held, so a cursor from before one returns
      # everything retained after it rather than nothing — the caller learns what
      # it missed from `dropped`.
      def from(since)
        return @text if since.nil?

        offset = retained_offset(since)
        return @text.dup if offset.negative?

        # `--since` is a byte offset a caller can compute, so unlike a cursor
        # rune itself issued it can land inside a character. `.scrub` then
        # replaced each orphaned continuation with U+FFFD under `status: ok` —
        # `--since=1` on `こY` returned two replacement characters then `Y`,
        # and `--since=1` was *longer* than `--since=0`. Snap forward to the
        # next character start instead: the split character is not available
        # from this offset, and nothing is invented.
        offset += 1 while offset < @text.bytesize &&
                          (byte = @text.getbyte(offset)) && byte.between?(0x80, 0xBF)
        (@text.byteslice(offset..) || +'').scrub
      end

      # Where an absolute cursor lands in the text still held.
      #
      # A hole shifts what comes after it and only what comes after it, so the
      # cursor is walked past each one in turn rather than having a single total
      # subtracted from it. A cursor landing *inside* a hole clamps forward to
      # the hole's end: those bytes are gone either way, and returning later
      # output is honest where returning earlier output — already delivered, now
      # presented as new — is not.
      #
      # With one hole at the head, which is every rotation, this is `since -
      # dropped` byte for byte.
      def retained_offset(since)
        dropped = 0
        @gaps.each do |offset, cumulative|
          return since - dropped if since < offset + dropped
          return offset if since < offset + cumulative

          dropped = cumulative
        end
        since - dropped
      end

      # What a terminal would be showing. A full-screen agent interleaves its
      # answer with its own repaints, so the byte stream holds every frame while
      # this holds only what is displayed.
      #
      # The size is the caller's to supply, because it is not in the transcript:
      # the child's pty is resized by whatever terminal attaches, and rendering
      # at a fixed default while the child laid its output out for a different
      # geometry produces a screen nobody ever saw. `ScreenRenderer` decides what
      # an absent or nonsensical size falls back to.
      def screen(rows: nil, columns: nil)
        Parsers::ScreenRenderer.render(@text, rows: rows, columns: columns)
      end

      # Lines matching `pattern`, with `context` lines either side.
      #
      # Matched against the *cleaned* text, not the raw stream: a repaint frame
      # splits words across escape sequences, so a pattern plainly visible on
      # screen does not match the bytes — which would make search appear broken
      # in exactly the situation it exists for.
      def grep(pattern, context: 0) = self.class.grep_text(@text, pattern, context: context)

      # Greps a given stretch of transcript rather than always the whole of it.
      #
      # `read --since=N --grep=RE` sliced the transcript to the cursor and then handed the slice to
      # a grep that ignored it and searched `@text`, so `--since` had no effect on a grepped read at
      # all. Measured: a read from a cursor recorded *after* the first line still returned that
      # line, and `grep_matches` counted it. A caller paging a long transcript with
      # `--since=<last cursor>` got the whole history back on every page, under a match count that
      # looked like it had filtered.
      def self.grep_text(text, pattern, context: 0)
        lines = Parsers::TextSanitizer.strip_ansi(text).lines
        matches = lines.each_index.select { |index| pattern.match?(lines[index]) }
        windows = matches.flat_map do |index|
          ([index - context, 0].max..[index + context, lines.size - 1].min).to_a
        end
        [windows.uniq.sort.map { |index| lines[index] }.join, matches.size]
      end
    end
  end
end
