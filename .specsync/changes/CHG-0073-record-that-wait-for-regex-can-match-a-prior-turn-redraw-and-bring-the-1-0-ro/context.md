---
change: CHG-0073-record-that-wait-for-regex-can-match-a-prior-turn-redraw-and-bring-the-1-0-ro
artifact: context
---

# Context

Found by the native-language i18n dogfood (`RUNE_NATIVE_I18N.md` §5.2) and independently by
the doc-i18n pass. Re-measured on current main after CHG-0072, against
`ruby -Ilib bin/rune`, on a child that reprints every prior answer, sleeps 3s, then prints
`DONE N`:

    send1  --wait-for-regex 'DONE \d+'   3.56s  matched=true   output holds DONE 1
    send2  --wait-for-regex 'DONE \d+'   0.56s  matched=true   output holds DONE 1 only

`DONE 2` was not in the captured output. `Echo#repaint?` only covers a copy of *this* send's
input. The reprint is ordinary new bytes.

Two candidate rules were considered and not shipped, because each loses a case this project
has already been burned by:

1. Reject if the match text existed in the pre-send transcript — loses a second `echo DONE`
   to a simple child.
2. Reject if CSI-home / erase precedes the match — loses a TUI that paints a reused sentinel
   with cursor motion as the real new answer.

Unique-per-turn sentinels wait through the reprint. That is the documented answer.

The 1.0 roadmap was stale in the same pass: it still listed the renderer as open after #66
and still treated the unreproduced half-painted `--screen` frame as a 1.0 blocker.
