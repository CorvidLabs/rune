---
spec: session.spec.md
---

# Testing

Maps the session fault and recovery harness onto invariants already stated in
`session.spec.md`. This file adds no requirements and no requirement ids.
`requirements.md` has none to cite. A mapping does not prove a test ran.
Command results, exit codes, and receipts belong in the R1 fanout report.
Lifecycle acceptance is not claimed, and no human approval is recorded here.

## Already covered

`spec/rune/session_spec.rb` already pins these cases. The new examples do not
repeat them:

- A child that exits 0 immediately is a successful start
  (`still succeeds for a child that exits cleanly and at once`). That example
  does not check read, list, and meta together.
- A child that exits 7 has that code in meta
  (`records the exit and stops supervising when the child exits on its own`).
  The read and list surfaces are separate examples.
- Stop, idempotent stop, a supervisor killed without cleanup, and a start that
  fails fast.
- A missing or non-executable command versus a child that really exits 127.
- A catastrophic `--wait-for-regex` is abandoned with `regex_timed_out: true`
  (`a --wait-for-regex that backtracks catastrophically abandons the pattern
  and answers, rather than wedging the loop past its own deadline`). That
  example also asserts elapsed time and does not assert `settled`, `matched`,
  liveness, or an output bound.
- `--wait-for-regex` does not match the echo of a shell command whose text
  contains the marker (`does not let --wait-for-regex match the echo of the
  text being sent`). The sent text is `sleep 2; echo MARKER`, the assertion
  counts `MARKER` at least twice, and it requires the call to take more than
  1.5 seconds.
- `--max-output` and `--tail`.
- Teardown of the child's process group, including a grandchild.
- An orphan is reported, and a stranger with a recycled-looking pid is not.
  `list` and `archive` do not signal. Those examples do not show that `stop`
  leaves an unrelated process-group leader alone.
- A supervisor crash is recorded as exit 70.
- A send to a session whose supervisor is already gone is an error.

## Added

`spec/rune/session_fault_recovery_spec.rb` calls
`harnesses/session_fault_recovery.rb`. Each live example expects an empty
problem list from the predicate named below. The harness sets `RUNE_HOME` to a
private directory, and the supervisor is spawned with that home. No example
attaches a terminal, passes `--all-projects`, or signals a pid the fixture
does not own.

| Case | Invariants | What the predicate requires |
| --- | --- | --- |
| Clean exit 0 and nonzero exit 3 | 13, 14, 17 | `exit_problems`: read, list, and meta agree on the exact exit code and on `exited`; the child's marker occurs once; the sent text does not contain that marker; the output size is positive, at most 4096 bytes, and equal to the output's byte size. That ceiling is a sanity check on these short fixtures. It is not `--max-output` and it does not assert truncation. The child and the supervisor are dead; a second read returns the same cursor and the same output. |
| Sequential read, then exit | 13, 14 | `read_problems`: one read observes `running` and a nil exit code while the child is held after printing its marker. The release file is written only after that read returns. A later read, list, and meta agree on exit 5 and `exited`. These are sequential reads, not an overlapped in-flight read. |
| Exit during send | 6, 29 | `send_problems`: the in-flight send returns `status` ok, `child_exited: true`, and not `timed_out`; its output contains the child's marker once and the sent nonce does not contain that marker; the output is within the same short-fixture sanity bound; a following read, list, and meta agree on exit 9; the child and the supervisor are then dead. The send reply itself is not required to already say `exited`, because the supervisor can still be alive while it answers. |
| Late output | 7, 33 | `late_problems`: the transcript contains the sent nonce before the release file exists, and does not yet contain the marker; the marker is not a substring of the nonce; the reply then matches that marker once; a proof file is written only by the child after release. There is no duration assertion. |
| Supervisor disappearance, then the same name | 14, 32, 48, 48a | `reconnect_problems`: after SIGKILL of the recorded supervisor pid, list and read are `dead`. The child ignored HUP and TERM, and its pid and start time still match after the supervisor is gone and again after the name is started again. The new transcript contains the new marker once and does not contain the old marker. Exit code 0 agrees across read, list, and meta. The new supervisor pid differs. The new child and supervisor are dead. The old child is still alive. |
| Unrelated process-group leader | 15, 38, 48a | `bystander_problems`: `stop` on a different fixture session returns success and list shows `stopped`. That session's child and supervisor are dead. A bystander spawned with its own process group, ignoring HUP and TERM, is a different pid, leads its group, and is still alive with the same start time. The harness never signals a negative pid. |

## Broken controls

Each control stages a disposable checkout under the fixture home: a copy of
`lib/` and a copy of `bin/rune` beside it. `spawn_supervisor` re-invokes
`bin/rune` from the directory of the loaded `session_command.rb`, and that
script loads `../lib/rune`. The checkout layout is what makes the supervisor
run the fault. One literal edit is applied only to the copied lib. A
subprocess sets `RUNE_FAULT_LIB` to that copied lib and runs the same
observation and predicate as the live example. Before that observation,
`assert_fault_load!` requires the controller's loaded `launch`, `finish`, and
`answered` files to be the staged copies, and requires `../../../bin/rune`
from the loaded command file to be the staged bin whose `../lib` is that same
copy. The mutated file's bytes must differ from the candidate. A raise here,
or any other nonzero fault process, is `setup_ok: false` and is not a killed
regression. `RUNE_FAULT_LIB` must stay inside `RUNE_HOME` and must not be the
candidate `lib/`. The candidate `lib/` and `bin/rune` are read before and
after, and the control raises if those bytes differ.

| Tag | Fault in the copy | Same assertion |
| --- | --- | --- |
| `exit_code` | `finish` records exit code 0 | `exit_problems` on a child that exits 3 |
| `marker` | `read` returns the fixed string `withheld` | `exit_problems` on that same exit |
| `child_exited` | both `child_exited: true` replies become `{ settled: true }` | `send_problems` |
| `running` | `liveness` supplies exit code 5 when meta has no exit code | `read_problems` |
| `reset` | `launch` does not call `reset_transcript` | `reconnect_problems` |
| `old_child` | `launch` passes a positive previous `child_pid` to `signal_owned_fixture`, which signals only a tracked pid whose recorded and current start times are present and equal | `reconnect_problems` |

These are not product-sensitive broken controls, and they are not claimed as
such:

- The 4096-byte sanity check. It does not request `--max-output`.
- `stable` and `cleanup`. A copied fault that keeps the same wrong value on
  both reads, or that points meta at a pid the scenario does not own, would
  not be the assertion under test.
- `echo` and `proof` on the late path. `echo` checks that the sent nonce does
  not contain the marker. `proof` checks a file the child writes. Neither is a
  rune reply field a one-line copy can falsify without changing the child.
- `bystander`. Killing that fixture after a successful `stop` does not show
  that `stop` signalled it. A copy that aimed `stop` at the bystander would
  need a pid rune does not have, or a process-group signal. The live
  bystander example remains. The signal probes below cover a missing identity.

## Signal identity

`signal_fixture` calls `Process.kill` only from `deliver_kill`, and only for a
positive tracked pid whose recorded start time and current start time are
both present and equal. A missing recorded identity, a missing current
identity, or a mismatch raises and does not signal. `Process.wait` success is
the only confirmation of death, and a later signal of that pid is a no-op. A
nil result from `ps` is not that confirmation. The `old_child` copy uses
`signal_owned_fixture`, which is that same guard, so a positive metadata pid
is not enough to signal. The probes pass a recorder in place of `Process.kill`
and use an owned sleeper whose stdin, stdout, and stderr are `/dev/null`.
They do not start a session and they do not signal a process group.

## Default home

`default_home_for` uses `realpath` only when that directory already exists.
Otherwise it returns the expanded path and does not create it. `refuses_default?`
compares a fixture path with that result. The missing-default example passes
an owned synthetic directory and does not read or create the operator's
`~/.rune`.

## Isolation

When `RUNE_HOME` is set to something other than the default home, the private
directory is created inside it. Otherwise the harness uses its own temporary
directory. Subprocesses inherit the private home. The harness does not signal
a negative pid.

## Cleanup

`reap_tracked` reports `reaped` only after `Process.wait`. A pid that
disappears without that wait is `absent`, not reaped. After a guarded signal,
presence is polled a bounded number of times. Injected checks do not pause.
`Process.getpgid` is used only for a positive pid when no existence double is
installed, and it is not a signal. A pid that is still present after the poll
is `still_present`. `refused_alive` is an identity refusal for a pid that is
still present. A refusal is not signalled again. `still_present` and
`refused_alive` both keep the fixture under `RUNE_FAULT_EVIDENCE` and fail
the scenario. Ignoring `still_present` would delete the directory and return
success, which the unresolved-pid example rejects. That example, the refusal
example, and the cleanup-error example inject existence and wait and use a
recorder in place of `Process.kill`. They do not spawn a process or signal an
unowned pid. `RUNE_HOME` and the module's home, tracking, and kill callback
are cleared in an ensure that still runs when reaping raises.

## Initial local verification before duplicate removal

The corrected harness ran on macOS on 2026-10-15 (America/Denver). The new
initial spec passed all 17 examples; the initial complete RSpec suite passed 659 examples
with zero failures. Separate identity probes passed all three missing or
mismatched identity cases. All seven disposable-product controls completed
their setup and were rejected by their corresponding assertions, including
the now-removed duplicate regex budget control on this Ruby version.

A separate synthetic cleanup control restored the old conditions that
ignored `still_present`. The corrected assertions rejected that copy: it
returned success, removed the fixture and omitted `cleanup-refusal.json`.
The control used injected process callbacks and did not signal a live pid.
The candidate harness was unchanged by every control.

The version check, strict spec check (100% of 32 source files), canonical
spec lifecycle check and native Trust verification passed locally. RuboCop
inspected the new spec; the harness directory remains excluded by the
repository's existing lint configuration. The first Trust run exercised the
candidate tests but had an empty committed diff, so it is not evidence of
committed-range risk review.

## Limits

This adds verification and documents observed behavior; it changes no Rune
implementation. The results cover this local macOS/Ruby environment, not the
hosted Ruby matrix or other platforms. No human lifecycle review or acceptance
is recorded. Detailed command receipts, control output and hash-bound source
review are retained with the coordinator's R1 report.

## Timeout coverage retained in the existing suite

The duplicate regex scenario and its mutation control were removed from the
new harness after hosted CodeQL flagged its deliberately exponential pattern.
The pattern was eliminated from this harness rather than encoded, moved or
excluded from scanning. Production code, CodeQL configuration and all
pre-existing tests are unchanged.

`spec/rune/session_spec.rb` still contains both real timeout regressions under
`a --wait-for-regex that backtracks catastrophically`: abandonment with
`regex_timed_out: true` within the send deadline, and subsequent session
usability. Those tests already own this scenario and remain explicitly in the
verification plan. The removed new case's additional `settled`, `matched`,
liveness and output-bound assertions are no longer claimed as added coverage.
The revised harness has 16 examples and six mutation controls; its new
verification receipts are recorded separately from the historical runs above.
