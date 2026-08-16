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
      # Text the log still holds, and how many earlier bytes rotation dropped.
      # A `truncated` event carries that count so cursors stay absolute: one
      # taken before a rotation still names the same position in the stream, it
      # just points at output no longer held.
      def self.load(path)
        return new(+'', 0) unless File.exist?(path)

        dropped = 0
        text = File.foreach(path).with_object(+'') do |line, buffer|
          event = JSON.parse(line, symbolize_names: true)
          case event[:event]
          when 'output' then buffer << event[:text].to_s
          when 'truncated' then dropped += event[:dropped_bytes].to_i
          end
        rescue JSON::ParserError
          next
        end
        new(text, dropped)
      end

      attr_reader :text, :dropped

      def initialize(text, dropped)
        @text = text
        @dropped = dropped
      end

      # Total bytes the child has produced, including what rotation discarded,
      # which is what a cursor counts.
      def cursor = @dropped + @text.bytesize

      # Everything from an absolute cursor onwards. Rotation shifts where that
      # lands in what is still held, so a cursor from before a rotation returns
      # everything retained rather than nothing — the caller learns what it
      # missed from `dropped`.
      def from(since)
        return @text if since.nil?

        offset = since - @dropped
        return @text.dup if offset.negative?

        (@text.byteslice(offset..) || +'').scrub
      end

      # What a terminal would be showing. A full-screen agent interleaves its
      # answer with its own repaints, so the byte stream holds every frame while
      # this holds only what is displayed.
      def screen = Parsers::ScreenRenderer.render(@text)

      # Lines matching `pattern`, with `context` lines either side.
      #
      # Matched against the *cleaned* text, not the raw stream: a repaint frame
      # splits words across escape sequences, so a pattern plainly visible on
      # screen does not match the bytes — which would make search appear broken
      # in exactly the situation it exists for.
      def grep(pattern, context: 0)
        lines = Parsers::TextSanitizer.strip_ansi(@text).lines
        matches = lines.each_index.select { |index| pattern.match?(lines[index]) }
        windows = matches.flat_map do |index|
          ([index - context, 0].max..[index + context, lines.size - 1].min).to_a
        end
        [windows.uniq.sort.map { |index| lines[index] }.join, matches.size]
      end
    end
  end
end
