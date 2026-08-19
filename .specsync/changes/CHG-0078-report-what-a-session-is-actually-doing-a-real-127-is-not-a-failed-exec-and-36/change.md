---
id: CHG-0078-report-what-a-session-is-actually-doing-a-real-127-is-not-a-failed-exec-and-36
state: accepted
type: bug_fix
base_commit: aa63d6e4100f888c62fcd622b059cbd3c83724e4
---

# Report what a session is actually doing: a real 127 is not a failed exec, and 36 hours of silence should not read as routine

## Intent

Report what a session is actually doing: a real 127 is not a failed exec, and 36 hours of silence should not read as routine

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- A child that runs and then exits 127 is reported as a successful start (measured 12/12, with the child's own file proving it executed), where before 7 of 12 were told the command was not on PATH. A genuinely missing binary and a target that exists but is not executable are both reported as failures, the latter having previously returned status ok and failed only on the next send. The supervisor records launch_failed only when exec itself failed, and the field is absent rather than false when a child ran, so meta written by older versions reads as a child that ran. In session list, a running session's idle time is rendered in hours or days past 90 minutes rather than thousands of minutes, and is no longer dimmed once it exceeds STALE_IDLE_SECONDS; a stopped session stays dim however long it has been quiet. Every new test fails when its arm of the fix is reverted.

## No-spec Rationale

Not applicable
