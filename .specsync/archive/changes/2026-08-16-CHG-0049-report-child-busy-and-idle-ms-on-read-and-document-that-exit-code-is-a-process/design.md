---
change: CHG-0049-report-child-busy-and-idle-ms-on-read-and-document-that-exit-code-is-a-process
artifact: design
---

# Design

`read` gains `child_busy` and `idle_ms`, derived from the transcript's own event timestamps
rather than asked of the supervisor — the same source `list` already uses, which means they work
identically once a session has stopped. Busy is defined as having printed within the settle window,
because that is the same threshold a send uses to decide a turn is over.

The flag is deliberately named for what it observes. A child that backgrounds a command and goes
quiet reports `child_busy: false` while still working; that is stated in the docs next to the
field rather than left for someone to discover, because it is the same trap that produced a false
"finished" 260 seconds early in the report that prompted this.

`exit_code` is documented rather than renamed. Renaming conveys the same information at the cost of
breaking every existing caller.
