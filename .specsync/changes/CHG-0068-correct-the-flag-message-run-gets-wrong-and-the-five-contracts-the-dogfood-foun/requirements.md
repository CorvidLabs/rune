---
change: CHG-0068-correct-the-flag-message-run-gets-wrong-and-the-five-contracts-the-dogfood-foun
artifact: requirements
---

# Requirements

1. A correctly spelled `run` flag with a space-separated value gets a message that
   names the real problem and a remedy that works.
2. The known-flag set is derived from the parser, not hand-written.
3. Each of the four documentation defects is corrected where it is stated —
   help text, spec invariant, and guide — not in one place only.
4. No behaviour changes except that one message.
