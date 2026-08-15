---
change: CHG-0038-prep-0-5-0-release-bump-version-roll-up-changelog
artifact: context
---

# Context

0.5.0 is a fix release with one addition. 0.4.0, released hours earlier, silently fails to deliver
any prompt longer than about 64 characters to Claude Code while reporting success — for the single
use case `rune session` exists to serve. Upgrading is strongly recommended and the changelog says
so.

The changelog also carries a correction rather than only new entries: 0.4.0's settle measurement was
confounded twice over, and the default it produced has been reverted. A release note that quietly
dropped the old numbers would leave anyone who read them still believing them.
