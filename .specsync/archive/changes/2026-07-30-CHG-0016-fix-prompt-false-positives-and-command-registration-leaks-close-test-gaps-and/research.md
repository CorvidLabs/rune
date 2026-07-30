---
change: CHG-0016-fix-prompt-false-positives-and-command-registration-leaks-close-test-gaps-and
artifact: research
---

# Research

Issue #11 reproduced false positives from two catch-all regexes: an unanchored question/capital match and any trailing shell punctuation. Issue #16 showed `Class.new(Command)` never emits the `:end` event required by the current TracePoint design and unnamed subclasses leak enabled TracePoints forever.

The repository already has Bundler 2.4.22 installed, which can produce the lockfile without introducing a new tool dependency. PR #21 completed two of issue #18's four items; `.gitignore` and the stdout contract confirm the other two remain.
