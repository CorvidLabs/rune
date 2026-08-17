---
change: CHG-0057-forward-every-int-term-and-let-the-second-one-stop-rune-with-bounded-pty-draini
artifact: tasks
---

# Tasks

- [x] Queue-based forwarding, burst window, abort threshold, `Aborted`
- [x] Bounded `SignalHandler.reap` with an optional per-poll drain
- [x] `PTYRunner` abort path: reap inside the read loops, interrupted capture outside
- [x] `PTYWatcher` abort path: reap inside `pump_output`, interrupted result outside
- [x] Bound the pre-existing `--timeout`/`--idle-timeout`/EPIPE kill waits
- [x] Tests, each falsified against its own reverted fix
- [x] Real-CLI verification of all measured scenarios, including a real TTY for `rune watch`
- [x] Spec updates for `pty_runner` and `watch`
