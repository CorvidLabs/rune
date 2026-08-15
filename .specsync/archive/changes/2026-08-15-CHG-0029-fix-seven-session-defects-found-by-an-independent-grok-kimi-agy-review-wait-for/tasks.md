---
artifact: tasks
---

# Tasks

- [x] `--wait-for-regex` matches beyond the echo, not the raw slice
- [x] `beyond_echo` locates the echo rather than requiring it at the cursor
- [x] Watch the in-flight send's socket; release on caller EOF
- [x] Bound the client's own wait so a wedged supervisor cannot hang it
- [x] Require supervisor liveness for readiness; fail fast when it dies
- [x] Signal the child's process group on teardown
- [x] Force owner-only modes on every directory created under RUNE_HOME
- [x] Bound request reads; isolate teardown steps; rescue EACCES and disk errors
- [x] Regression tests for each verified finding
- [x] Record the deferred limitations in the spec
