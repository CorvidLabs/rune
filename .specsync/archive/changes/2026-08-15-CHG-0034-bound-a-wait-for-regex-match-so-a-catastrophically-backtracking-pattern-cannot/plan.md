---
change: CHG-0034-bound-a-wait-for-regex-match-so-a-catastrophically-backtracking-pattern-cannot
artifact: plan
---

# Plan

1. Establish which patterns actually blow up on the Ruby in use, rather than assuming the textbook
   ones do.
2. Prove the wedge end to end against a live session before changing anything.
3. Bound the match, and abandon rather than retry on exceeding it.
4. Guard the regression tests by capability, since Ruby 3.0 and 3.1 cannot be fixed this way.
