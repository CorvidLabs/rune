---
change: CHG-0008-keep-rune-watch-stdout-parseable-in-agent-mode-and-stop-the-trust-gate-passing-o
artifact: testing
---

# Testing

## Regression tests added

| Test | Guards |
|---|---|
| `watch_command_spec`: routes the live stream to stderr under `--json` | R1, R3 |
| `watch_command_spec`: routes the live stream to stderr under `--ndjson` | R1, R3 |
| `watch_command_spec`: routes the live stream to stderr when stdout is not a TTY | R1, R3 |
| `watch_command_spec`: keeps the live stream on stdout for a human on a TTY | R2 |
| `e2e_spec`: complete stdout of every command in every agent mode parses as JSON | R4 |
| `e2e_spec`: `rune watch --json` under a real pty emits exactly one parseable JSON document | R1, R4 |

## Manual reproduction

Before the fix:

```
$ ruby -rpty -rio/wait -e 'PTY.spawn("sh","-c","rune watch --json --log=/tmp/a.ndjson -- echo X > /tmp/a.out 2>/dev/null"){|r,w,p| (loop{break unless r.wait_readable(10); r.readpartial(4096)} rescue nil); Process.wait(p) rescue nil}'
$ python3 -m json.tool < /tmp/a.out
Expecting value: line 1 column 1 (char 0)
```

After the fix the same command prints the parsed envelope, and the child's `X` appears on stderr.

## Trust range

The empty-range rejection cannot be exercised by RSpec. It is verified by running the resolution
script directly on `main` (where `origin/main..HEAD` is empty, so it must fall back to
`HEAD~1..HEAD`) and on a feature branch (where it must keep `origin/main..HEAD`), and by confirming
`fledge trust verify` reports a non-zero commit count in both cases.

## Deliberately not covered

The child's stdout/stderr remain merged inside the pty, so no test asserts they are distinguishable
— that is a separate tracked limitation, not something this change claims to fix.

## Full gate

`fledge lanes run verify` and `fledge run smoke-test` must both pass, with spec-sync file and LOC
coverage still at 100%.
