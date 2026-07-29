## MODIFIED

### SPEC SECTION Error Cases
| Condition | Behavior |
|-----------|----------|
| Unknown command | Returns `Result.failure` with descriptive error, exit code 1 |
| Command raises exception | Caught and wrapped in `Result.failure`, exit code 1 |
| No command given | Shows help output |
| Help requested for an unknown command | Returns `Result.failure` with descriptive error, exit code 1 |
| Mixed or repeated help aliases | Consumes every alias, returns help, and exits 0 |
| Reused CLI after help | Resets help and output modes, then dispatches and renders normally |
