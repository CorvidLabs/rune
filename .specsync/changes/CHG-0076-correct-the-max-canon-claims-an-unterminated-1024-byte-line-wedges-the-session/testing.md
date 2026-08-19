---
change: CHG-0076-correct-the-max-canon-claims-an-unterminated-1024-byte-line-wedges-the-session
artifact: testing
---

# Testing

Documentation-only change; the RSpec suite and RuboCop are run as gates but the evidence for this
change is measurement, not new tests.

## Instruments

Three independent instruments, none of which read the tty echo:

1. a child appending `"#{line.bytesize}|..."` to a file for every line it reads
2. `tr a-z A-Z` with all-lowercase input, so uppercase in the transcript cannot be an echo
3. `stty -echo` wrappers, so any byte in the reply is necessarily the child's

## Key results

```
boundary        1022/1023 delivered, 1024/1025 not      20/20 deterministic
terminator      --no-newline 1024 accepted with 0 BEL, subsequent bare CR returns 1 byte = 1 BEL
wedge           probes at +0s, +30s, +120s all discarded; child alive (ps Ss+) throughout
                every reply: status ok, settled true, state running, exit_code null
not-delayed     after ^U recovery the child's log holds the pre-jam line and the post-recovery
                line only; all five intervening probes permanently absent
not-rune        bare PTY.spawn, one write() of 1025 bytes -> identical wedge
mode-isolation  same `cat`, same wrapper: icanon on -> wedge; `stty -icanon min 1 time 0` -> 1202
                bytes delivered, healthy
raw-not-exempt  busy bash: 1024 buffered bytes swallowed by readline and prepended to the next
                command (marker `expr 987654321 \* 3` never produced 2962962963)
                busy python3: follow-up statement never executed, target file still "UNWRITTEN"
recovery        ^U recovers (1024 bytes of \b \b erase echo, next send delivered)
                ^D does not recover and does not kill the child
                ^C ends the session at 130
roadmap claim   python3 -q at 4096 / 20000 / 60000 bytes: len() and sha256 both exact
```

## What was not tested

macOS 26.5.2 / Darwin 25.5.0 arm64 only — every number here is a macOS number. Real full-screen
agent TUIs were not measured; the raw-mode sample is `cat` under `stty raw`, `bash -i` and
`python3 -q`. `rune run` and `rune watch` were not measured, only `rune session`. Multibyte payloads
were checked for equivalence at equal byte counts but the wedge arms are ASCII.
