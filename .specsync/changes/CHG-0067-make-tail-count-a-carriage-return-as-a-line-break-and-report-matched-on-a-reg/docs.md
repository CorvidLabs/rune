---
change: CHG-0067-make-tail-count-a-carriage-return-as-a-line-break-and-report-matched-on-a-reg
artifact: docs
---

# Docs

`session.spec.md` invariant 6 now states which conditions race with and without
a pattern, and records that the four-condition version was wrong so nobody
restores it. `docs/sessions.md` defines `settled` as "the wait was answered"
with the companion field naming which of quiet, match or exit did it — the old
text said "the child went quiet", which a regex match sets with no quiet period
at all. `--help` says the flag replaces the settle window rather than racing it.
