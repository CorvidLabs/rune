---
change: CHG-0078-report-what-a-session-is-actually-doing-a-real-127-is-not-a-failed-exec-and-36
artifact: testing
---

# Testing

## The 127 fix

Measured with a script that appends to a file and then exits 127, so delivery is proven by the
child's own file rather than by the reply:

```
before: misreported as "not on PATH" 7/12,  children that executed 12
after : misreported 0/12,                   children that executed 12
missing binary        -> error (exit 127) still
non-executable target -> error (exit 126), was silently status: "ok"
```

The new spec starts six such sessions and asserts all six succeed. It waits for the children to
record that they ran rather than reading the file at once: `start` returns before the child has
necessarily executed, and reading immediately raced them — that first version passed in isolation
and failed under a loaded full-suite run, which is exactly the flake it would have become.

## The idle rendering

```
45s          -> "idle 45s"    dim
5m           -> "idle 5m"     dim
1.5h         -> "idle 1.5h"   yellow
36.2h        -> "idle 36.2h"  yellow
4.6d         -> "idle 4.6d"   yellow
36.2h stopped-> "idle 36.2h"  dim
```

## The tests can fail

Each arm reverted independently against the committed tests:

```
launch_failed -> exit_code == 127 : 2 failures (real-127 succeeds, non-executable fails)
new idle formatter -> old one     : 2 failures (units, and the dimming threshold)
```

Both reverts were verified to have actually applied before trusting the result — an earlier attempt
to revert by regex silently matched nothing and "passed", which would have proven the opposite of
what it appeared to.

## Gates

`fledge run test` 621 examples / 0 failures. RuboCop clean. Eight consecutive full-suite runs clean
after the race in the new test was fixed.

## Not covered

A child that repaints a spinner while blocked still reports `idle_ms` near zero and `child_busy`
true. Nothing here detects that, and nothing here claims to.
