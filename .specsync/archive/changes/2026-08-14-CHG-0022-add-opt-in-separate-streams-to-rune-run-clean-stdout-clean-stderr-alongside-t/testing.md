---
change: CHG-0022-add-opt-in-separate-streams-to-rune-run-clean-stdout-clean-stderr-alongside-t
artifact: testing
---

# Testing

- Real child writing to both stdout and stderr, `separate_streams: true`: `clean_stdout`/
  `clean_stderr` contain exactly their own stream's lines; `clean_output` still contains both
  (merged view unaffected).
- Exit code mirrors the wrapped command in separate_streams mode, same as default mode.
- Neither `clean_stdout` nor `clean_stderr` appears in the result data when `separate_streams` is
  not set — the regression guard for "no default behavior change."
- `--timeout` kills and reaps the child in separate_streams mode too (real `ps`-equivalent
  `Process.kill(0, pid)` orphan check after the fact, same style as the existing single-stream
  timeout test).
- Real SIGINT forwarding terminates the child promptly in separate_streams mode.
- `separate_streams: true` + `script:` fails clearly with `Result.failure` before spawning
  anything.
- Missing/non-executable wrapped commands still get the conventional 127/126 exit codes in
  separate_streams mode.
- `RunCommand#call`: `--separate-streams` parses and forwards correctly, alone and combined with
  `--timeout`; omitted entirely when not passed (not forwarded as `separate_streams: false`).
- Evidence to be filled in after implementation: `fledge run test`, `fledge run lint`,
  `fledge run spec-check` results.
