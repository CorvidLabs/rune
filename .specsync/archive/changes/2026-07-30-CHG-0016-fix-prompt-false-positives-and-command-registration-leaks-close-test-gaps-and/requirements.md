---
change: CHG-0016-fix-prompt-false-positives-and-command-registration-leaks-close-test-gaps-and
artifact: requirements
---

# Requirements

1. Ordinary output such as `##`, `TODO: fix #`, `Is it ok? Yes`, and lines ending in bare `>`, `$`, or `%` must not be classified as prompts.
2. Explicit confirmations, labeled prompts, wizard markers, arrow prompts, and recognizable shell prompts must remain detectable.
3. Declaring a command name must register the class immediately without creating a `TracePoint`.
4. Calling `.name` with no argument must preserve Ruby class-name reflection.
5. An unnamed subclass must remain unregistered and must not leave global instrumentation enabled.
6. NDJSON failures must emit `event: "error"`.
7. A newly created explicit watch log must have mode `0600`.
8. Rune-level failures must remain structured on stdout and that behavior must be documented.
9. Development and test dependencies must be locked in a repository-tracked `Gemfile.lock` compatible with the supported CI matrix.
