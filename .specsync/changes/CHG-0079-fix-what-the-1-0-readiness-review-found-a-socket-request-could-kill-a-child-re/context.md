---
change: CHG-0079-fix-what-the-1-0-readiness-review-found-a-socket-request-could-kill-a-child-re
artifact: context
---

# Context

Five independent reviewers were asked whether rune should cut 1.0 — two agents driven through
`rune session` and three subagents attacking specific surfaces. Both agents answered **do not
ship**, for different reasons. This change fixes the code half of what they found. Two of the five
findings are corrections to work accepted earlier the same day.

## 1. A control-socket request could kill a child

`JSON.parse` accepts any JSON *value*, not only an object. `null`, `123`, `true`, `"x"` and
`[1,2,3]` all parsed, then `request[:op]` raised — `TypeError` for the Integer, `NoMethodError` for
the rest — past every rescue in `handle_request`. It unwound the event loop into `run`'s
`StandardError` rescue, which crashed the supervisor and SIGKILLed a healthy child.

Measured with a heartbeat child, so death was observed from its file and from `ps` rather than
inferred: **5/5 such payloads killed both**, while `{"op":123}` and unparseable text were answered
correctly. Reachable only from the non-Ruby socket client the protocol exists to serve — rune's own
client always builds a Hash.

`specs/session/session.spec.md` invariant 28 says a control client "can never take the session down
with it". This was the hole in it.

## 2. `read` reported a dead session as running, indefinitely

`liveness` returned `meta[:state]` as recorded. `describe` recomputes from process liveness and
carries a comment saying a recorded "running" "is routinely stale and must never be reported
as-is". With the supervisor SIGKILLed:

```
list -> "dead"      read -> "running"      send -> is not running (state running, exit code nil)
```

`docs/sessions.md` recommends polling `read` for a readiness marker, so that loop waited forever on
a session that was already gone. The `send` refusal contradicted itself in one sentence and put
Ruby's `nil` in front of a user.

## 3. The idle rendering shipped that morning had a boundary bug

`idle_suffix` compared raw seconds against `STALE_IDLE_SECONDS` while `humanize_idle` rounded, so
`idle 15m` rendered **dim at 870s and yellow at 900s** — identical label, different colour, nothing
on screen to explain it. That is precisely the legibility the change existed to deliver.

Flooring instead of rounding makes the label change at the same instant as the colour, and fixes
two more: an hour printed `60m` where the code's own comment promised hours, and `90s` printed `2m`
(a 33% overstatement that made `1m` unreachable). Days now begin at one day rather than two, so the
36-hour incident that motivated the work reads `1.5d`.

## 4. The carry ceiling accepted that morning was set to exactly the producer's read size

`MAX_CARRY_BYTES` was 4096 — exactly `Supervisor::READ_CHUNK` — so a sequence that did not complete
inside a single pty read could never be carried. Measured: an 8205-byte sequence survived 0 of 14
start offsets.

Worse, the invariant published with it claimed that past the ceiling "the bytes are dropped, which
is what a one-shot render already did with them". That is false in both directions: a terminated
`\e]52;c;<12KB base64>\a` split at 4096 renders **11 bytes one-shot and 1935 bytes of base64
retained**. One-shot never has to hold anything across a boundary, so it gets this right.

Raised to 64KB — sixteen reads of headroom, memory still bounded. It does not close the hole; OSC 52
and iTerm2 inline images are unbounded, so no finite ceiling can, and the invariant now says so.

## 5. Two parsers in one module disagreed about what an escape is

`ScreenRenderer::CSI` was widened to the full ECMA-48 grammar — parameters, then intermediates, then
a final byte — after a real capture of one agent contained 80 sequences it printed instead of
obeying. `TextSanitizer::ANSI_REGEX` kept the narrow pattern. So the same sequences still survived
into `clean_output`, `--grep` and `list`'s `last_line` while `--screen` rendered them correctly:

```
strip_ansi("\e[38:2::255:0:0mERROR")  =>  "\e[38:2::255:0:0mERROR"    ScreenRenderer => "ERROR"
strip_ansi("\e[2 q$ ready")            =>  "\e[2 q$ ready"             ScreenRenderer => "$ ready"
```

`\e[2 q` is DECSCUSR, emitted by fish, starship, zsh vi-mode and Codex CLI; the colon form is
ITU-T T.416 truecolour. This file's history already records the same shape twice — one parser fixed,
the other not.

## Not in this change

The reviewers' remaining findings are documentation and surface-freeze decisions rather than code:
the guide still teaches the pre-CHG-0078 `start` contract, the roadmap still lists solved and
unsolved items together, and the additive envelope choices (structured error codes,
`list --archived`'s `name`) are cheap now and impossible after a freeze. Those are deliberately
separate so this change stays reviewable.
