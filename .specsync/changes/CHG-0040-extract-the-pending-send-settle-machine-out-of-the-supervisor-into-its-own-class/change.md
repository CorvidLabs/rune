---
id: CHG-0040-extract-the-pending-send-settle-machine-out-of-the-supervisor-into-its-own-class
state: accepted
type: feature
base_commit: 839d392bb81565dc9cc8fa0e50bafbda9974b7ab
---

# Extract the pending-send settle machine out of the supervisor into its own class, so the logic four review rounds kept finding bugs in is testable without an event loop

## Intent

Extract the pending-send settle machine out of the supervisor into its own class, so the logic four review rounds kept finding bugs in is testable without an event loop

## Affected Canonical Specs

- `session`
- `cli`

## Acceptance Criteria

- The settle decision — echo stripping, the regex bound, the quiet window, the deadline, and the unsubmitted-input rule — lives in Session::PendingSend and is exercised without constructing a Supervisor. supervisor.rb drops from 980 to about 815 lines. Behaviour is unchanged: the full suite passes, including every regression test from the five rounds of review that produced this logic.

## No-spec Rationale

Not applicable
