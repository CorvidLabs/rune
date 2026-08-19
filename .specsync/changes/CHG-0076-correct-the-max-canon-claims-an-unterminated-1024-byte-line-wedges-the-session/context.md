---
change: CHG-0076-correct-the-max-canon-claims-an-unterminated-1024-byte-line-wedges-the-session
artifact: context
---

# Context

Three documents published claims about the tty canonical-queue limit, and all three were wrong in
the same direction: they described losing **one line** when what actually happens is that the
session stops accepting input entirely.

| document | claim |
|---|---|
| `ROADMAP.md` | the earlier "every later send is silently discarded" entry was *wrong* and retracted |
| `docs/sessions.md` | "a single line of 1024+ bytes **vanishes**"; raw-mode children unaffected |
| `specs/session/session.spec.md` | "silently discarded ... with **no error anywhere**" |

## How the wrong text got published

The ROADMAP retraction is the instructive one. The 0.8.0 entry claimed every later send is silently
discarded while `settled: true`. That was retracted on the strength of a 20,000-character send to
`python3 -q`, which receives its input in full and refuses an overlapping send with a specific
error. **Every fact in the retraction reproduces** — `len()` and sha256 both verified.

It refuted nothing, because `python3 -q` is in **raw mode** at the instant the bytes land, and the
original claim was about **cooked mode**. A true finding was retracted on the basis of a
measurement taken in a different regime.

This is the same shape as the harness error the retraction itself was written to correct (a
liveness helper that ignored `status`, so a correct refusal read as a dead session) — a fixture more
specific than the mechanism — one level up.

## What was measured this time

Six independent probes and three adversarial verifiers, deliberately using **out-of-band detection**:
the child writes the byte count of each line it actually reads to a *file*, so the tty echo can
never be mistaken for delivery. That defeats the two harness traps this repo has recorded (a nonce
matching its own echo, and a child that never echoes anyway).

Established:

- The limit is **1024 bytes per canonical line including the terminator** rune appends, so a payload
  of 1023 arrives and 1024 does not — 20/20 deterministic. At exactly 1024 the payload is accepted
  whole and the *terminator* is rejected, so the line can never be submitted.
- **The session wedges**, indefinitely (measured to +120s), while every reply says `status: ok`,
  `settled: true`, `state: running`. After `\x15` recovery the discarded sends are permanently
  absent from the child's input, which rules out delayed buffering.
- **It is not rune**: a single 1025-byte `write()` to a bare `PTY.spawn` wedges identically, so the
  split payload/terminator write is not the cause.
- **The discriminator is `ICANON` when the bytes land** — established by holding the child binary
  constant and flipping one termios flag. Not the child's identity (`cat`, a `sh` read loop, a Ruby
  loop and a non-reading child all wedge alike), not whether the child drains.
- **Raw-mode children are not exempt.** `bash` and `python3` are raw at their prompt and cooked
  while a foreground command runs; a 1200-byte send in that window loses the line and silently
  corrupts the next command. This directly contradicts the shipped advice to "drive a raw-mode
  target".
- **"Over-long line" is wrong at the caller's level.** Four 256-byte writes with no terminator wedge
  the queue too, as does `--no-newline` with 1024 bytes and no terminator ever sent.
- **No reliable detector exists.** BEL fails in both directions and is suppressed entirely when
  `IMAXBEL` is cleared.
- Complete lines are never silently lost: they get backpressure and a loud refusal.

## Scope

Documentation only. No behaviour change — this records what the code already does. Whether rune
should *detect* and report the wedge is a separate question and is deliberately not answered here;
the measurement shows there is no reliable in-band signal to detect it with.
