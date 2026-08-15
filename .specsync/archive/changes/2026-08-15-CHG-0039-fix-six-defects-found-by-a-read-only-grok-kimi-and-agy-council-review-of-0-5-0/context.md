---
change: CHG-0039-fix-six-defects-found-by-a-read-only-grok-kimi-and-agy-council-review-of-0-5-0
artifact: context
---

# Context

A read-only council review of the released 0.5.0, one lens each so three agents did not produce
three copies of the same pass: grok on the terminal renderer, kimi on the send path and event loop
ordering, agy on failure and teardown. All three were driven through `rune session` itself, with
1.3KB briefs — twenty times the length that silently failed to submit before 0.5.0.

All six findings are in code added during the 0.4.0 and 0.5.0 hardening, not in older code. Two of
them are in fixes made earlier in that same hardening: the ordering guard added to protect the
terminator reintroduced the coalescing the terminator delay exists to prevent.
