---
change: CHG-0032-prep-0-4-0-release-bump-version-roll-up-changelog
artifact: context
---

# Context

0.4.0 is the `rune session` release: persistent, named PTY sessions that outlive a single `rune`
invocation, plus the send-and-settle primitive that makes them usable as a synchronous call. It also
carries three rounds of independent review and one round of dogfooding against real agent CLIs, the
last of which found a crash that killed live sessions within a handful of turns.

Version constant and changelog only. No library code, public API, or canonical contract changes in
this change.
