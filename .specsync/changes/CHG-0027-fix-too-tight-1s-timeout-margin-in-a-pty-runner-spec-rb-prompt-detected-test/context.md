---
change: CHG-0027-fix-too-tight-1s-timeout-margin-in-a-pty-runner-spec-rb-prompt-detected-test
artifact: context
---

# Context

CHG-0024's `--timeout` + `prompt_detected` regression test used `timeout_seconds: 1` for a
`ruby -e` child that must boot its interpreter and print `"Password: "` before the kill fires.
Under real system load this margin is too tight — reproduced locally as a *consistent* (not
random) failure, unlike the sporadic load-related flakes seen elsewhere in the same session. This
codebase already documents the exact same risk on a neighboring test (the orphan-process timeout
test a few lines above): `timeout_seconds: 3, not 1 — ... a ruby -e child's own interpreter boot
time can stretch enough to approach a 1s timeout`. This change applies the same fix.
