---
change: CHG-0066-stop-a-read-mid-escape-withhold-an-unterminated-sequence-from-the-text-and-the
artifact: docs
---

# Docs

`session.spec.md` invariants 51 and 51a carry the contract and the measurement.
`pty_runner.spec.md` documents `dangling_suffix` where `OutputLimiter` lives.

The full dogfooding report from the nine translation agents is in
`RUNE_I18N_DOGFOOD.md`, which is untracked and deliberately left out of this
change: it covers several findings beyond this one and should be triaged on its
own rather than smuggled in beside a fix.
