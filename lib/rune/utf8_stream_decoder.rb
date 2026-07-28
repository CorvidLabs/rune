# frozen_string_literal: true

module Rune
  # Incrementally decodes arbitrary byte chunks as UTF-8 without corrupting a
  # valid multi-byte character merely because it straddled a read boundary.
  class UTF8StreamDecoder
    def initialize
      @pending = ''.b
    end

    def decode(chunk)
      bytes = @pending + chunk.to_s.b
      split_at = incomplete_suffix_start(bytes)
      complete = split_at ? bytes.byteslice(0, split_at) : bytes
      @pending = split_at ? bytes.byteslice(split_at..) : ''.b
      scrub(complete)
    end

    def finish
      trailing = @pending
      @pending = ''.b
      scrub(trailing)
    end

    private

    def incomplete_suffix_start(bytes)
      lower_bound = [bytes.bytesize - 4, 0].max
      (bytes.bytesize - 1).downto(lower_bound) do |index|
        expected_length = sequence_length(bytes.getbyte(index))
        next unless expected_length

        suffix = bytes.byteslice(index..)
        return index if suffix.bytesize < expected_length && continuation_bytes?(suffix.bytes.drop(1))

        break
      end
      nil
    end

    def sequence_length(byte)
      return 2 if byte&.between?(0xC2, 0xDF)
      return 3 if byte&.between?(0xE0, 0xEF)
      return 4 if byte&.between?(0xF0, 0xF4)

      nil
    end

    def continuation_bytes?(bytes)
      bytes.all? { |byte| byte.between?(0x80, 0xBF) }
    end

    def scrub(bytes)
      bytes.force_encoding(Encoding::UTF_8).scrub
    end
  end
end
