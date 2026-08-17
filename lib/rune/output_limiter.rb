# frozen_string_literal: true

module Rune
  # Bounds already-captured text for `rune run --max-output`/`--tail` without corrupting UTF-8 at
  # the cut boundary. Stateless — both entry points are class methods, no instance needed, mirrors
  # `Rune::Parsers::TextSanitizer`'s shape.
  class OutputLimiter
    # Announces the elided middle in the text itself.
    #
    # `--max-output` keeps a head and a tail, and joining them silently produces text that was
    # never printed. Measured: a 201-byte transcript at `--max-output=200` dropped exactly the byte
    # that turned `chsh -s /bin/zsh` into `chsh -s bin/zsh` — a different, still-plausible path,
    # reported as `status: ok`. The `truncated`/`omitted_bytes` metadata was honest throughout; the
    # *text* was a fabrication, and a caller reading only `clean_output` had no in-band signal at
    # all. `--tail` never had this problem because what it keeps is contiguous.
    #
    # The shape reuses rune's existing in-band annotation prefix (`[rune] Execution timed out after
    # N seconds`), names the flag responsible, and carries the exact byte count, alone on its own
    # line. It is not a security boundary — a child can print any string, this one included — so
    # `truncated`/`omitted_bytes` stay authoritative; the marker is what makes the cut visible to
    # whoever reads the text.
    ELISION_PATTERN = /^\[rune\] ==== (\d+) bytes? omitted by --max-output ====$/

    # An escape sequence a cut left without its terminator, anchored to the whole string so it can
    # be applied to the slice starting at the last ESC before the cut.
    #
    # Both cut boundaries need this, in mirror image. A head ending mid-`\e]0;title` makes
    # `strip_ansi` — which treats OSC as everything up to the terminator — swallow the marker *and*
    # the head of the tail up to the first BEL. A tail *beginning* mid-sequence has no ESC left to
    # identify it, so the remainder prints literally: cut inside `\e[1;31m` and `31mred` appears as
    # text. That is the same defect `ScreenRenderer#resync` already fixes for the rendered screen
    # (`\e[?2026h` cut in half printing `?2026h`), in a second place.
    #
    # Written with byte ranges rather than literals because it runs against binary slices: params
    # are 0x30-0x3F, intermediates 0x20-0x2F, CSI final bytes 0x40-0x7E (ECMA-48 5.4). Note that a
    # comment containing a slash would close an -x mode literal, so none of them do.
    # A control string is single-line by construction, which is what keeps a stray introducer from
    # eating real output. `\e]` with no terminator anywhere would otherwise make every byte after
    # it look like string content: measured on a synthetic stream carrying one unterminated `\e]`,
    # the head trim dropped as much as 3,197 bytes of ordinary text. Excluding CR and LF caps that
    # at one line, and costs nothing real — no OSC title, OSC 8 hyperlink, OSC 52 payload, DCS
    # reply or Sixel body contains either. `TextSanitizer::ANSI_REGEX` is looser here because it
    # only ever matches strings that did terminate.
    STRING_BODY = /[^\a\e\r\n]*/
    DANGLING_ESCAPE = /
      \A \e (?:
        \[ [\x30-\x3F]* [\x20-\x2F]*   # CSI, still waiting for its final byte
        | \] #{STRING_BODY}            # OSC, still waiting for BEL or ST
        | [PX^_] #{STRING_BODY}        # DCS, SOS, PM, APC, still waiting for ST
        | [\x20-\x2F]+                 # two-byte escape, still waiting for its final byte
      )? \z
    /x

    # The same shapes, complete. Used to find where the remainder of a straddling sequence ends
    # inside the tail, so exactly that remainder is dropped and not one byte more.
    #
    # The lookahead in the last branch keeps a bare `\e[` from matching as a complete two-byte
    # escape once the CSI branch has failed for want of a final byte; without it an unterminated
    # CSI would be reported as two bytes long and the rest of it would still be printed.
    COMPLETE_ESCAPE = /
      \A \e (?:
        \[ [\x30-\x3F]* [\x20-\x2F]* [\x40-\x7E]
        | \] #{STRING_BODY} (?: \a | \e\\ )
        | [PX^_] #{STRING_BODY} \e\\
        | (?! [\[\]PX^_] ) [\x20-\x2F]* [\x30-\x7E]
      )
    /x

    # How far either side of a cut is examined for the sequence that straddles it, and therefore
    # the most either trim can remove.
    #
    # Bounded for the same reason `ScreenRenderer::RESYNC_SCAN_BYTES` is: the scan has to terminate
    # on input that is all plain text, and it must not walk a multi-megabyte transcript. Past the
    # window the old behaviour stands — the orphan is kept rather than a guess being made — so a
    # miss costs what today already costs, and a false positive can cost at most this much text,
    # which `omitted_bytes` and the marker both report. 512 clears every sequence a terminal
    # actually emits: the longest CSI is around 20 bytes and the longest realistic OSC is a
    # hyperlink URL.
    RESYNC_WINDOW_BYTES = 512

    class << self
      # Keeps the head and tail of `text`, omitting the middle and marking where it was, so the
      # result holds at most `max_bytes` bytes of the child's own output. Returns
      # `[bounded_text, omitted_bytes]`.
      #
      # `omitted_bytes` is exactly the number of the child's bytes that are not in the result:
      # `original_bytesize - max_bytes`, plus whatever the two escape-sequence trims removed. It is
      # never affected by `scrub`'s own byte-count changes at a split multi-byte character, because
      # every count here is taken in offsets into the original text and the scrub happens after.
      #
      # The marker is not charged against `max_bytes`, so a result can exceed it by the marker's
      # length. That is deliberate, and it is not a new kind of overshoot: `scrub` already returns
      # 62 bytes for `truncate_middle(text, 60)` when both cuts split a multi-byte character, and
      # has since the flag shipped. The budget bounds the child's output; rune's own annotation of
      # the cut is not the child's output. Charging it would mean `--max-output=200` quietly
      # returning 155 bytes of transcript, and would make the marker's length depend on the count
      # printed inside it.
      def truncate_middle(text, max_bytes)
        bytes = text.bytesize
        return [text, 0] if bytes <= max_bytes

        head_bytes = max_bytes / 2
        head_end = trimmed_head_end(text, head_bytes)
        tail_start = resynced_tail_start(text, bytes - (max_bytes - head_bytes))
        omitted = tail_start - head_end
        bounded = head(text, head_end) + elision_marker(omitted) + tail(text, tail_start)
        # Bounding must never return more than it was given. `--max-output=200`
        # on a 210-byte reply returned 251 bytes — more than passing no flag at
        # all — because the marker cost more than the elision saved; 42% of a
        # 20,000-case fuzz returned more than the input. Stated as the property
        # itself rather than as a proxy for it, so it fires exactly when it must
        # and leaves every case where eliding genuinely pays.
        return [text, 0] if bounded.bytesize >= bytes

        [bounded, omitted]
      end

      # The marker text for `omitted` bytes, newline-delimited so it always stands alone.
      #
      # The leading newline is load-bearing: it separates the head's last partial line from the
      # tail's first, and it can terminate no escape sequence, so a half-cut sequence the trim
      # somehow missed cannot absorb the marker's opening bracket. Plain `\n` rather than `\r\n`
      # because `rune run` bounds its already-stripped `clean_output` with this same call, where a
      # stray CR would survive into the text.
      def elision_marker(omitted)
        "\n[rune] ==== #{omitted} #{omitted == 1 ? 'byte' : 'bytes'} omitted by --max-output ====\n"
      end

      # Keeps only the last `line_count` lines of `text`. Returns
      # `[bounded_text, omitted_lines]`. A trailing newline does not count as an extra empty line.
      #
      # Needs no marker: what it keeps is a contiguous run of real output, so nothing in the result
      # is text the child never produced. It starts late, which `omitted_lines` reports.
      def tail_lines(text, line_count)
        lines = text.split("\n", -1)
        lines.pop if lines.last == '' && text.end_with?("\n")
        return [text, 0] if lines.size <= line_count

        omitted = lines.size - line_count
        kept = lines.last(line_count).join("\n")
        kept += "\n" if text.end_with?("\n")
        [kept, omitted]
      end

      private

      def head(text, head_end) = text.byteslice(0, head_end).to_s.scrub

      def tail(text, tail_start) = text.byteslice(tail_start, text.bytesize - tail_start).to_s.scrub

      # Where the kept head has to stop so it does not end inside an escape sequence: back at the
      # ESC that opened the one the cut split, or at the cut itself when it split nothing.
      #
      # The walk repeats because escape debris nests one level. Measured on a real vim transcript,
      # two cut points of 14,029 landed between the ESC and the backslash of the ST that closes
      # `\ePzz\e\\`: removing the trailing bare ESC leaves `\ePzz`, an opener with no terminator,
      # which `strip_ansi` cannot match and so prints as literal `Pzz`. One more step back clears
      # it. Each step strictly decreases the offset, so the loop always terminates.
      def trimmed_head_end(text, head_end)
        window = window_before(text, head_end)
        finish = window.bytesize
        while (found = dangling_at(window, finish))
          finish = found.first
        end
        head_end - (window.bytesize - finish)
      end

      # Where the kept tail has to start so it does not begin inside an escape sequence: past the
      # final byte of the one the cut split.
      #
      # Only that remainder is skipped, never a fixed window: the sequence is reassembled from its
      # dangling prefix on the far side of the cut plus the bytes that follow, and the match says
      # exactly where it ends. A sequence that does not terminate within the window leaves the tail
      # where it was, which is what happens today.
      #
      # The innermost dangling sequence is the right one here, and it is not the one the head walks
      # back to: what the tail needs is where the split sequence *ends*, and a cut inside an ST is
      # a cut inside a complete two-byte escape of its own.
      def resynced_tail_start(text, tail_start)
        window = window_before(text, tail_start)
        found = dangling_at(window, window.bytesize)
        return tail_start unless found

        prefix = found.last
        ahead = text.byteslice(tail_start, RESYNC_WINDOW_BYTES).to_s.b
        # The same window forward as back, so the skip is bounded by the same constant the trim is:
        # a sequence whose terminator is further away than this is not one, and the orphan stays.
        whole = (prefix + ahead)[COMPLETE_ESCAPE]
        whole ? tail_start + (whole.bytesize - prefix.bytesize) : tail_start
      end

      # `[window_offset, unterminated_sequence]` for the last ESC before `finish`, or nil when what
      # precedes `finish` is plain text or a sequence that already completed.
      #
      # Anchored at the last ESC rather than scanned forward for, which is both cheaper and more
      # faithful: xterm abandons an OSC or DCS string when a fresh ESC arrives inside it, so the
      # sequence a cut can be inside is always the most recent one. `window` is binary, so its
      # character indices are byte offsets and `rindex` needs no conversion.
      def dangling_at(window, finish)
        start = finish.positive? ? window.rindex("\e", finish - 1) : nil
        return nil unless start

        candidate = window.byteslice(start, finish - start)
        candidate.match?(DANGLING_ESCAPE) ? [start, candidate] : nil
      end

      # At most RESYNC_WINDOW_BYTES of `text` ending at `offset`, as bytes rather than characters
      # so every offset in this file is a byte offset and `scrub` never has to be reasoned about.
      def window_before(text, offset)
        back = [offset, RESYNC_WINDOW_BYTES].min
        text.byteslice(offset - back, back).to_s.b
      end
    end
  end
end
