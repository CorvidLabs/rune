---
change: CHG-0054-four-agent-pre-1-0-review-nine-bugs-fixed-and-fifteen-documentation-claims-tha
artifact: docs
---

# Docs

Fifteen corrections across README, getting-started, sessions and architecture guides, each claim
re-executed rather than re-read. The worst repeated 0.7.0's failure exactly: fields documented on
the wrong command, telling callers to use something that returns nil.

`ROADMAP.md` was three releases out of date and is rewritten around what 1.0 needs.
`docs/sessions.md` gains the `--wait-for-regex` echo limitation with a workaround.
