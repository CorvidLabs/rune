---
change: CHG-0059-expose-subcommands-as-structured-data-in-per-command-help
artifact: testing
---

# Testing

Three tests in `spec/rune/cli_spec.rb`, each verified against deliberately broken
code rather than assumed to work — this repo has deleted a regression test that
passed with its own fix reverted.

    control                                  result
    revert the Help wiring only              1 of 3 fail
    declare a `ghost` subcommand not in
      SUBCOMMANDS (the drift case)           2 of 3 fail

Both controls were restored and the file re-run clean: 30 examples, 0 failures.

Also exercised end to end against a live `grok` session, where the payload was
read by a driver rather than an assertion.
