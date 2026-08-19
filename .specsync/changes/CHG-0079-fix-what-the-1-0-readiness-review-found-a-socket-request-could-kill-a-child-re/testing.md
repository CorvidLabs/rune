---
change: CHG-0079-fix-what-the-1-0-readiness-review-found-a-socket-request-could-kill-a-child-re
artifact: testing
---

# Testing

## Socket

A heartbeat child writes a file on a timer, so its death is read from the file and from `ps`, never
inferred from a rune reply.

```
                 before            after
null             KILLED            survived, {"error":"malformed request"}
123              KILLED            survived
true             KILLED            survived
"hello"          KILLED            survived
[1,2,3]          KILLED            survived
{"op":123}       survived          survived
not json at all  survived          survived
```

## Liveness

```
--- supervisor SIGKILLed ---
  list "dead"   read "dead"   (read was "running")   AGREE
  send: Session "lv" is not running (state dead and recorded no exit code).
--- child exited 7 on its own ---
  list "exited" read "exited" exit_code 7            AGREE
--- healthy session ---
  read "running"
```

## Idle ladder

```
    0s -> 0s   dim        899s -> 14m  dim         3600s -> 1.0h  yellow
   89s -> 89s  dim        900s -> 15m  YELLOW     86400s -> 1.0d  yellow
   90s -> 1m   dim       3599s -> 59m  yellow    129600s -> 1.5d  yellow
 -999s -> 0s   dim
```

Exhaustive over 0..3000s: no label renders in both colours. Before, `idle 15m` was dim for 870–899s
and yellow for 900–929s.

## Carry ceiling

```
payload   chunked == oneshot?
  12000   yes      (was NO: 11 bytes one-shot vs 1935 retained)
  60000   yes
  70000   NO       <- documented, not denied
 200000   NO       <- documented, not denied
memory: 60004B held after 20 x 60KB unterminated opens, ceiling 65536 — bounded, no accumulation
```

## Sanitizer

```
\e[38:2::255:0:0mERROR  -> "ERROR"      (was "\e[38:2::255:0:0mERROR")
\e[2 q$ ready            -> "$ ready"    (was "\e[2 q$ ready")
\e[4:3municurl           -> "unicurl"
\e[!pafter               -> "after"
ratio a:b in [1;2] is 3:4 -> unchanged   (widening must not eat ordinary text)
```

## The tests can fail

Each arm reverted independently, with the revert confirmed to have applied first:

```
socket type guard removed      -> 6 failures
liveness recompute reverted    -> 1 failure
idle floor -> round            -> 4 failures
sanitizer CSI arm narrowed     -> 1 failure
```

Two reverts earlier in this work silently matched nothing and "passed", which is why each is now
confirmed by grepping for the anchor before trusting the result.

## A harness error in my own test, caught and fixed

The straddle test first used `colours.uniq.one?`. `Array#one?` counts *truthy* elements, so
`[false].one?` is false and every all-dim label read as a straddle. A standalone check using
`size > 1` passed, which is how the disagreement surfaced. Corrected to `.size == 1`.

## Gates

`fledge run test` 636 examples / 0 failures. RuboCop clean.
