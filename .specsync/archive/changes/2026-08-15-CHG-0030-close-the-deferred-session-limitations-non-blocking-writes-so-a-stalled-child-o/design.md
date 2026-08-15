---
artifact: design
---

# Design

## Non-blocking writes

Every write from the event-loop thread — to the pty master and to attached terminals — goes through
a per-IO outbox drained on writability. The invariant being restored is simple: *the only thread
must never block*, because blocking there stops pty pumping, settle evaluation and `stop` handling
simultaneously.

**What is and is not demonstrated.** The queue provably removes blocking writes (there are none
left). It does *not* come with a reproduction of the wedge two reviewers predicted: a 4MB write to a
raw-mode child that never reads stdin behaved identically before and after on macOS. Recorded as
hardening by construction rather than a fixed defect, because claiming otherwise would be false.

What *is* verified is that the queue is correct: 300KB arrives byte-perfect, checked against a
byte-sum the child computes itself, and a deaf child no longer holds anything up.

## Terminal size

Dimensions travel in the attach request, and SIGWINCH is forwarded over a *separate* short-lived
control connection. That separation is forced: after the ack the attachment socket is a raw byte
pipe to the pty, so any control frame written into it would be typed at the child.

The child returns to the headless default when the last terminal detaches. Without that, a session's
geometry would depend on whether a human happened to attach earlier, which would make programmatic
sends non-deterministic.

## Idle connections

Silent peers are never readable, so they were never examined. They are now reaped after the same
bound that applies to a partially-delivered request. A client that has sent anything is already out
of the set by the time it is handled, so only genuinely silent connections are affected.

## Start lock

An exclusive per-name lock spans the conflict check *and* the recording of a supervisor pid, because
those two were a check-then-act pair. The lock file is never deleted — deleting it is what
reintroduces the race.

## Discovered while testing

A single line of >=1024 bytes is silently dropped by a cooked-mode child's terminal (`MAX_CANON`).
Measured exactly: 1023 arrives, 1024 does not, no error anywhere. Not fixable in rune — it is the
line discipline — but it is the kind of silent data loss that will bite anyone sending a long prompt
to a shell-like child, so it is documented in the spec and the guide.
