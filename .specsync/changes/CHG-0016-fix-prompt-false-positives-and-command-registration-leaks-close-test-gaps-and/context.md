---
change: CHG-0016-fix-prompt-false-positives-and-command-registration-leaks-close-test-gaps-and
artifact: context
---

# Context

Rune's audit found four related trust gaps in otherwise-small surfaces:

- broad prompt patterns mark ordinary completed output as interactive;
- command registration installs one global `TracePoint` per subclass and leaks it for unnamed classes;
- explicit watch-log permissions, NDJSON error events, and dynamic registration lack direct tests;
- error-stream behavior and development dependency resolution are not reproducibly contracted.

PR #21 already removed the dead `optparse` require and corrected the README result example from #18. This change owns the remaining #18 work plus #11, #16, and #17.
