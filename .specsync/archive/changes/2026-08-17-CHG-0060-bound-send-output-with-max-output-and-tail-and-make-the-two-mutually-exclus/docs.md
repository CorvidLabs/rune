---
change: CHG-0060-bound-send-output-with-max-output-and-tail-and-make-the-two-mutually-exclus
artifact: docs
---

# Docs

`session.spec.md` invariants 50, 50a and 50b carry the contract. The flag
descriptions in `session_command.rb` still read `read: …`; they are now accurate
for `send` too and are left for a pass that rewords all of them together rather
than leaving one flag described differently from its neighbours.

`ROADMAP.md` is rewritten from "known, unfixed, and queued for 0.9.0" to a
re-measured table, because seven of its eight entries were no longer true and one
was wrong about its own mechanism.
