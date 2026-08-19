---
change: CHG-0080-say-what-start-actually-does-split-the-roadmap-by-what-would-change-it-and-giv
artifact: context
---

# Context

Both agents in the 1.0 readiness review answered *do not ship*, and after the code findings were
fixed (CHG-0079) what remained was not code. It was three places where rune's own documents said
something other than what rune does, and one contract decision that is free now and impossible
after a freeze.

## 1. The guide taught a `start` contract that no longer exists

`docs/sessions.md` said a command that does not exist still returns `status: "ok"` with exit 0 and
`exit_code: 127` in the body, and told the reader to "check `state`, not the process exit status".
CHG-0078 changed all of that. Measured now, three trials each:

| case | status | exit | `state` in the reply |
|---|---|---|---|
| missing binary, not executable, a directory | `error` | 1 | — (no `data`) |
| exists, exits 3 at once | `ok` | 0 | **`running`** |
| `true` | `ok` | 0 | `exited`, code 0 |

The warning was right and its example and its remedy were both wrong. A command that cannot be
executed is now a hard failure; a command that starts and dies is still a success, because it is
one. And `state` in a *start* reply is a snapshot that can already be false — the script exiting 3
reported `running` 3 times out of 3. The authority is `list`, which recomputes, or the next `send`.

## 2. The roadmap listed solved and unsolved items as one undifferentiated blocker set

"What 1.0 needs" held four items, and a reader could not tell which were gates and which were
things that would ship documented. That ambiguity is what kept the list growing: every unsolved
item looked like a blocker whether or not anyone intended to solve it, so 1.0 receded whenever a
new one was found.

It is now split by what would actually change the answer. One gate remains. The three technical
items — the settle path, `--wait-for-regex`'s surface, the unwired retained `Screen` — moved to
"Known and documented", unchanged in substance, each saying why it moved. This is the same failure
the file already records about itself: it was three releases stale in 0.8.0 and "read as current".

## 3. Failures could only be distinguished by reading English

Every failure envelope was `{status, error}`. A caller telling "no such session" from "not running"
had the prose, and the prose is not stable — the same missing-session condition produces two
entirely different sentences depending on whether the session exists in another project, one of
which carries remediation advice that is wrong for the other case.

At 1.0 those sentences become a frozen API. `Result.failure` already accepted `data:` and
`Result#to_h` already emitted it, so this is additive: failures now carry `data.code` and
`data.name`. The human renderer reads only `error`, so nothing visible moves. It also closes the
gap that `data.name` was unavailable on exactly the path where a retry loop needs it.

The code set is deliberately not exhaustive. It covers the conditions a caller branches on today,
and a caller is told to treat an unrecognised code as a generic failure — so the set can grow
without another breaking change.

## What is still open

The reviewers named two more freeze-sensitive shapes that are **not** addressed here: `list
--archived` returns a `name` no other verb accepts, and `--home`/`--project` are parsed by every
session subcommand and inert in all of them. Both are real, both are breaking to change later, and
both want a decision rather than a patch. They are recorded rather than silently deferred.
