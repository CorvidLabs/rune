---
change: CHG-0078-report-what-a-session-is-actually-doing-a-real-127-is-not-a-failed-exec-and-36
artifact: context
---

# Context

Two defects, found the same afternoon, that are the same mistake wearing different faces: rune
reported a state it had not established.

## 1. A real 127 was reported as "not on PATH"

`launch_failure` tested `exit_code == 127`, on the reasoning that 127 is the shell's "command not
found" and therefore the one case where the child never ran. That is true of a *shell*. It is not
true of a *child*: 127 is an ordinary status any program may choose.

Measured with the child appending to a file **before** exiting 127, so the file — not the reply —
proves execution:

```
misreported as "not on PATH": 7/12    reported ok: 5/12
children that actually executed:  12
```

Racy, because it depended on whether the child died before the supervisor recorded it as running.
The same script succeeded or failed by timing alone, and the failure told the user to check whether
a program they had just run was installed.

The supervisor already knew the truth and discarded it. Only `PTY.spawn` raising means exec failed,
and that happens before the child exists — so `finish` now records `launch_failed`, and the CLI
reads the fact instead of inferring it from a status that cannot carry it.

That closed a hole in the other direction too: a file that exists but is **not executable** returned
`status: "ok"` and failed only on the next `send`. `EACCES` means exec genuinely failed, so it is now
a loud failure — which is what the original code's own comment said it intended.

| case | before | after |
|---|---|---|
| runs, exits 127 | 7/12 falsely "not installed" | 0/12 |
| missing binary | error | error |
| non-executable target | silent `status: "ok"` | error |

## 2. Thirty-six hours of silence rendered as routine

A session driving an agent CLI stopped at an approval prompt — *"Run this command? 1. Approve once
2. Approve for this session 3. Reject"* — and waited there for **36.2 hours**. `state` said
`running` the whole time, which is the same word a healthy child gets.

rune was not blind to it. `idle_ms` was 130,293,976 and `child_busy` was false: the facts were all
present and correct. The rendering is what failed. `idle_suffix` printed minutes at every scale, so
the line read `idle 2172m`, in the same dim grey as every healthy session. Minutes stop being a unit
anyone converts somewhere around an hour, and grey is the colour of "ignore me".

So: hours and days once it is that long, and no dimming for a *running* session past
`STALE_IDLE_SECONDS`. A stopped session stays dim — its idle time is only how long ago it stopped.

Rendered against the real sessions afterwards:

```
● kimi-rev    running  idle 36.3h   kimi     <- yellow
● grok-rev    running  idle 21s     grok     <- grey, genuinely working
● kimi-rc     running  idle 7m      kimi     <- grey
```

**This is deliberately not a stuck-detector.** rune cannot tell a child waiting on a human from one
thinking hard, and this repo has measured and rejected four heuristics that tried. The threshold
decides a colour, nothing more. The honest claim is that the fact was always there and was not
legible; it is now.

## What this does not fix

A child that repaints a spinner while blocked keeps `idle_ms` near zero and `child_busy` true
forever, so it is indistinguishable from working. That is the harder half and is untouched here.
`last_line` is also of little use for a full-screen agent — for the blocked session above it read
`context: 3% (29.3k/1M)`, the status bar, because that is simply what the child painted last.
