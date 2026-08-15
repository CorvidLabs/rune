---
change: CHG-0034-bound-a-wait-for-regex-match-so-a-catastrophically-backtracking-pattern-cannot
artifact: tasks
---

# Tasks

- [x] reproduce the wedge against a live session
- [x] `REGEX_MATCH_TIMEOUT` applied at compile time where supported
- [x] capability detection that does not misfire on Ruby 3.0
- [x] `regex_matched?` tri-state and the `regex_timed_out` outcome
- [x] regression tests, verified failing against the unfixed code
- [x] invariant and Known Limitation recorded
