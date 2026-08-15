---
change: CHG-0034-bound-a-wait-for-regex-match-so-a-catastrophically-backtracking-pattern-cannot
artifact: design
---

# Design

`compile_regex` attaches `REGEX_MATCH_TIMEOUT` (0.25s) when the Ruby running the supervisor
supports it — generous for any sane pattern against a screenful of output, and a fraction of a tick
for a pathological one.

Capability is detected with `Regexp.method_defined?(:timeout)` rather than by rescuing a bad
keyword: on Ruby 3.0 an unknown keyword is taken as the *options* argument rather than rejected, so
a rescue-based probe would silently compile a case-insensitive regex instead of falling back.

`regex_matched?` returns true, false, or nil for "exceeded its budget", and `pending_outcome`
maps nil to `{ settled: false, regex_timed_out: true }`. A tri-state rather than an exception at
the call site keeps the precedence order in `pending_outcome` readable.

`REGEX_TIMEOUT_ERROR` resolves to `Regexp::TimeoutError` where it exists and to a never-raised
class otherwise, so the rescue clause stays valid on Ruby 3.0 without widening to `StandardError`.
