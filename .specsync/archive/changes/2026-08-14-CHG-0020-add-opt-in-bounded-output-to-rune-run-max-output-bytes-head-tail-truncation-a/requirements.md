---
change: CHG-0020-add-opt-in-bounded-output-to-rune-run-max-output-bytes-head-tail-truncation-a
artifact: requirements
---

# Requirements

- `rune run --max-output=BYTES <cmd>` truncates `clean_output` and `raw_output` independently to
  at most `BYTES` bytes each, keeping the head and tail (omitting the middle), and adds
  `truncated: true|false` and `omitted_bytes: N` to the result data.
- `rune run --tail=N <cmd>` keeps only the last `N` lines of `clean_output` and `raw_output`, and
  adds `truncated: true|false` and `omitted_lines: N` to the result data.
- Neither flag changes the result data shape when it is not passed — no new keys appear, existing
  keys are byte-for-byte unchanged. This preserves the existing JSON envelope for consumers that
  don't opt in.
- `--max-output` and `--tail` are mutually exclusive; passing both fails with a clear
  `Result.failure` before spawning anything.
- Both flags follow the existing `--timeout` convention: recognized only before a `--` separator,
  and a malformed value (non-positive, non-numeric, empty) fails clearly instead of leaking into
  the wrapped command's argv.
- Truncation must not corrupt UTF-8 at the cut boundary (reuse the scrub approach already used by
  `UTF8StreamDecoder`).
