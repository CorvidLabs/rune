---
change: CHG-0073-record-that-wait-for-regex-can-match-a-prior-turn-redraw-and-bring-the-1-0-ro
artifact: docs
---

# Docs

English `docs/sessions.md` is updated: the flag is no longer called deterministic, the
prior-turn reprint is measured in the `--wait-for-regex` callout, and "What to know before
driving a real agent" has a matching bullet. `ROADMAP.md` is brought up to date.

The nine `docs/i18n/sessions.*.md` translations are **not** updated in this change. The
English file is authoritative where they disagree. Updating them is a follow-up that should
be conducted in-language through a real `rune session`, the same way the last translation
round found this defect.
