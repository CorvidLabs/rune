---
change: CHG-0020-add-opt-in-bounded-output-to-rune-run-max-output-bytes-head-tail-truncation-a
artifact: testing
---

# Testing

- `OutputLimiter.truncate_middle`: below-budget text is untouched (0 omitted); over-budget text
  keeps head+tail and reports the exact omitted byte count; a multi-byte UTF-8 character at the
  cut boundary is scrubbed instead of raising/corrupting.
- `OutputLimiter.tail_lines`: fewer lines than N is untouched; more than N keeps only the last N
  and reports the omitted line count.
- `PTYRunner` with `max_output_bytes:` against a real chatty command (`yes` under a short timeout)
  bounds both `clean_output` and `raw_output` and sets `truncated: true`.
- `PTYRunner` with `tail_lines:` keeps only the last N lines and sets `truncated: true`.
- `PTYRunner` with neither option set produces byte-for-byte the same result data shape as before
  (no `truncated`/`omitted_*` keys at all) — the regression guard for "no default behavior change."
- `RunCommand#call`: `--max-output=N` and `--tail=N` parse and forward correctly; malformed values
  (`0`, negative, non-numeric, empty) are rejected before spawning anything; combining both flags
  in one invocation fails with a clear error.
- Evidence to be filled in after implementation: `fledge run test`, `fledge run lint`,
  `fledge run spec-check` results.
