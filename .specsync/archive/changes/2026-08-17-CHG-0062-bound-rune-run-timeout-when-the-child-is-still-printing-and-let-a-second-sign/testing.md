---
change: CHG-0062-bound-rune-run-timeout-when-the-child-is-still-printing-and-let-a-second-sign
artifact: testing
---

# Testing

On the merged tree: 539 examples, 0 failures (526 + 13 new); rubocop clean across
72 files.

The wedge ladder was re-run on the merged tree and passes 4/4 — the table in
`context.md` is that measurement, not the original branch s. It was also run
against v0.8.0 and against the pre-merge 0.9.0 branch, both of which hang 2/4, so
the fix is attributable rather than assumed.

The first probe of this was itself wrong and is worth recording: it read rune s
stdout through a pipe, so "rune has not exited" and "my reader is blocked on a
pipe another process holds open" were indistinguishable. Redirecting to a file
and polling `Process.wait2(WNOHANG)` separated them, and `ps` confirmed state `S`.

The merge kept both sides of every conflicting hunk rather than taking either
wholesale — `pty_runner.rb` needed this branch s `interrupted_capture` *and* the
0.9.0 branch s `timeout_hint`, and `pty_watcher.rb` needed this branch s
`spawned_pid` capture *and* the 0.9.0 branch s `ExecArgv` shell-injection fix.
Taking one side would have silently dropped the other, which this repository has
done once before. Verified after merging: the wedge ladder passes, `send
--max-output=120` still bounds to 65 bytes, and `session --help --json` still
lists 7 subcommands.
