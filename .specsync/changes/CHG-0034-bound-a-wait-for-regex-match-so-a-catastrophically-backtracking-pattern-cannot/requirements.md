---
change: CHG-0034-bound-a-wait-for-regex-match-so-a-catastrophically-backtracking-pattern-cannot
artifact: requirements
---

# Requirements

1. A single `--wait-for-regex` match must be bounded, so no pattern can hold the event loop.
2. Exceeding the bound must abandon the pattern rather than retry it: the slice only grows, so
   retrying spends the budget again every tick and the send never ends.
3. The caller must be told which happened, distinguishably from a settle or a timeout.
4. The session must remain usable afterwards.
5. Ruby 3.0 and 3.1 have no per-`Regexp` timeout; behaviour there must be unchanged and documented
   rather than silently different.
