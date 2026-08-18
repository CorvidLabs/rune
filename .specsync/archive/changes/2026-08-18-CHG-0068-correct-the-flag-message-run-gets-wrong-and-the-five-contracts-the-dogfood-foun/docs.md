---
change: CHG-0068-correct-the-flag-message-run-gets-wrong-and-the-five-contracts-the-dogfood-foun
artifact: docs
---

# Docs

`pty_runner.spec.md` gains rows for the new constants and two invariants: the
independent per-field budget with its consequence, and the ASCII-only
reconciliation of `omitted_bytes`. `session.spec.md` extends 41o with the three
measured `--grep` limits and 41h with `--screen` being bounded by geometry rather
than by the read filters.

Guides: `docs/sessions.md` (both), `docs/getting_started.md` (the `--max-output`
bullet), `docs/pty_architecture.md` (the unqualified
`clean_output = strip_ansi(raw_output)` claim). `ROADMAP.md` records the two
limitations so they are tracked rather than buried in help text.

`README.md` is deliberately untouched: its `--max-output` line is correct, and
editing it would stale every accepted change and drag in nine translated READMEs
for no gain.
