---
change: CHG-0064-honour-the-modes-and-charsets-that-decide-what-the-screen-contains-and-strip-th
artifact: testing
---

# Testing

Every new test was falsified against deliberately broken code:

    mutation                              failures
    private-mode dispatch removed         7
    DECAWM ignored, alternate kept        1
    two-byte escape branch removed        7
    charset broadening reverted           1

563 examples, 0 failures; rubocop clean across 72 files.

The alternate-screen fix was checked against live output before being believed.
Against grok it changes nothing — grok enters the alternate buffer before
printing anything, so there is nothing to hide, and both renderers produce the
same 897 bytes. The case where it matters is a program that prints *first*,
which is any TUI launched from a shell that already produced output. Captured
from a real `sh -c "echo BEFORE_TUI; tput smcup; echo INSIDE_TUI; tput rmcup;
echo AFTER_TUI"`:

    old  ["BEFORE_TUI", "INSIDE_TUI", "AFTER_TUI"]
    new  ["BEFORE_TUI", "AFTER_TUI"]

The sanitizer fix was verified against a live Claude Code session: 2 escapes in
`clean_output` before, 0 after, capped and uncapped.

Dogfooded across four agent CLIs — claude, grok, kimi and agy — 16 field-report
checks each. Two apparent failures were controlled and only one was real: a
null-text socket send reported HUNG at a 5s bound and replied in 1.1s when given
a real one, which was the probe rather than rune.
