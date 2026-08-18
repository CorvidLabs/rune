---
change: CHG-0071-make-a-failed-launch-loud-name-the-project-a-session-is-in-and-fix-two-multiby
artifact: docs
---

# Docs

session.spec.md gains invariants 52 (a failed launch is an error, and why only
127) and 53 (an error names the project). Export rows for `launch_failure`,
`EXEC_FAILURE_STATUS` and `projects_holding`.

The wider point from the same report — that rune has three different envelope
shapes and a caller must independently know to check each — is deliberately not
addressed here. That is an API-shape decision for 1.0 and wants designing, not a
third patch; this change fixes the one instance where `status` itself was wrong.
