---
change: CHG-0057-forward-every-int-term-and-let-the-second-one-stop-rune-with-bounded-pty-draini
artifact: context
---

# Context

`rune run` and `rune watch` stopped responding to signals after the first one.
`SignalHandler.with_traps` latched with `forwarded ||= forward(pid, pending)`, so every signal after
the first was a no-op — while the INT/TERM traps stayed installed for the whole run. rune therefore
neither passed the signal on nor died itself.

Measured before the change: 4x SIGINT + 2x SIGTERM over three seconds to a `rune run` all reported
`exited=false`; rune kept going and left only when its own `--timeout` fired 15s later. The child
printed its trap message exactly once — signals two through six were swallowed. `rune watch` was
identical, and with no `--timeout` (its default) it survived 5x SIGINT + 5x SIGTERM and needed
SIGKILL. That last case is the serious one: a CLI that cannot be stopped by Ctrl-C or by an init
system, with no bound.
