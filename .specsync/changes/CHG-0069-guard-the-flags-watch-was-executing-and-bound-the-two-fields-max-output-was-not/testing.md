---
change: CHG-0069-guard-the-flags-watch-was-executing-and-bound-the-two-fields-max-output-was-not
artifact: testing
---

# Testing

584 examples, 0 failures; rubocop clean; docs-check green; specsync 0 hard errors.

    fix                     control                          failures
    watch guard             leftover_flag_error removed      4 of 33
    grep honours --since    grep the whole transcript again  1 of 2
    stream bounds           bound_stream reverted            1 of 3

**An adversarial pass found two merge-blockers in my own work, and it was right
about both.**

The first: I shipped the watch guard with *no test*. Reverting all three guard
files left the suite fully green — CI could not tell the fix from its absence,
including its headline case. Six tests now cover it, including watch`s own drift
guard and the case it must not lose (a child`s own flags surviving).

The second: I moved `unknown_flag_error` and `INLINE_VALUE_ERROR` out of
`RunCommand` and left `specs/pty_runner/pty_runner.spec.md` documenting them, and
added six exports nothing documented. `specsync coverage` reported two hard
errors and six warnings; both errors are gone.

It also caught a real defect in my own writing-up: watch`s `VALUE_FLAGS` comment
claimed the list "cannot drift from the parser" while `--log` is appended by
hand. Corrected to what is true.

One reported loss was checked and left alone: the guard covers the leading
position only, so `rune watch echo hi --log=/tmp/x` still writes rune`s log to
the child`s path. Measured byte-identical before and after this change, so it is
pre-existing and out of scope — recorded in invariant 20 rather than fixed here.
