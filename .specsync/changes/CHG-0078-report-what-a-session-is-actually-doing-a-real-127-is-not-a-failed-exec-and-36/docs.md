---
change: CHG-0078-report-what-a-session-is-actually-doing-a-real-127-is-not-a-failed-exec-and-36
artifact: docs
---

# Docs

`specs/session/session.spec.md` records both: that a failed launch is established by the supervisor
rather than inferred from exit 127, and that `list` renders idle time readably and stops dimming a
running session that has gone quiet — with the explicit note that this is legibility, not detection.

`docs/sessions.md` needs no change for the idle rendering (it is human output, not contract). The
`start` failure text there is stale for a different reason and is being corrected separately, so it
is deliberately untouched here to avoid two changes editing the same passage.
