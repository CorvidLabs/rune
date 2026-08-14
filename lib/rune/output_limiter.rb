# frozen_string_literal: true

module Rune
  # Bounds already-captured text for `rune run --max-output`/`--tail` without corrupting UTF-8 at
  # the cut boundary. Stateless — both entry points are class methods, no instance needed, mirrors
  # `Rune::Parsers::TextSanitizer`'s shape.
  class OutputLimiter
    class << self
      # Keeps the head and tail of `text`, omitting the middle, so the result is at most
      # `max_bytes` bytes. Returns `[bounded_text, omitted_bytes]`; `omitted_bytes` is exactly
      # `original_bytesize - max_bytes` (never affected by `scrub`'s own byte-count changes at a
      # split multi-byte character, which are a rune-added annotation of the cut, not omitted
      # content).
      def truncate_middle(text, max_bytes)
        bytes = text.bytesize
        return [text, 0] if bytes <= max_bytes

        omitted = bytes - max_bytes
        head_bytes = max_bytes / 2
        tail_bytes = max_bytes - head_bytes
        head = text.byteslice(0, head_bytes).scrub
        tail = text.byteslice(bytes - tail_bytes, tail_bytes).scrub
        [head + tail, omitted]
      end

      # Keeps only the last `line_count` lines of `text`. Returns
      # `[bounded_text, omitted_lines]`. A trailing newline does not count as an extra empty line.
      def tail_lines(text, line_count)
        lines = text.split("\n", -1)
        lines.pop if lines.last == '' && text.end_with?("\n")
        return [text, 0] if lines.size <= line_count

        omitted = lines.size - line_count
        kept = lines.last(line_count).join("\n")
        kept += "\n" if text.end_with?("\n")
        [kept, omitted]
      end
    end
  end
end
