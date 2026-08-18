---
change: CHG-0071-make-a-failed-launch-loud-name-the-project-a-session-is-in-and-fix-two-multiby
artifact: testing
---

# Testing

604 examples, 0 failures; rubocop clean; specsync 0 hard errors.

    check                                        before            after
    start -- <missing binary>                    status ok         status error
    start -- true                                status ok         status ok
    read from another project                    "No such session" names the project
    हिन्दी                                        6 columns         5 (wcwidth)
    resync("日本語テキスト\\e[1mAFTER")              "\\xAA\\x9Eテキスト…"  "\\e[1mAFTER"

Controls: reverting `launch_failure` fails 1 of 3; reverting the resync byte
index fails 2; removing the Indic ranges fails 2; reverting the project lookup
fails 2.

One claim from the same report did **not** reproduce and is not fixed: that a
send over ~1024 bytes jams every later send while rune answers `settled: true,
state: running`. Measured at 600, 1100, 4096 and 20,000 bytes — the first three
show no jam at all, and 20,000 refuses the follow-up with `status: error` and
"previous input is still being delivered to the child", recovering by itself in
about ten seconds. That is what ROADMAP already records. The reported shape looks
like a probe reading `clean_output` without checking `status`, which is the exact
mistake this session made once already.
