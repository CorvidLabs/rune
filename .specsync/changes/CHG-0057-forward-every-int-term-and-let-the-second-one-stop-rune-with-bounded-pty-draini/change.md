---
id: CHG-0057-forward-every-int-term-and-let-the-second-one-stop-rune-with-bounded-pty-draini
state: accepted
type: feature
base_commit: 6277a4e99d31233ed54d2f8edd8f4245d7239a38
---

# Forward every INT/TERM and let the second one stop rune, with bounded pty-draining child reaping

## Intent

Forward every INT/TERM and let the second one stop rune, with bounded pty-draining child reaping

## Affected Canonical Specs

- `pty_runner`
- `watch`

## Acceptance Criteria

- Every trapped INT/TERM is forwarded to the child instead of only the first; the second signal within the burst window forwards and then ends the run at 128+signo with the child reaped and a well-formed result rendered; a lone signal still only reaches the child and rune keeps waiting; every wait on a signalled child is bounded and drains its pty so a wedged pty child cannot hang rune.

## No-spec Rationale

Not applicable
