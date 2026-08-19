---
change: CHG-0077-hold-an-escape-split-across-chunks-so-a-retained-renderer-matches-a-one-shot-ren
artifact: context
---

# Context

`ROADMAP.md` names a retained per-session `Screen` as the thing 1.0 hangs off: it removes the
render window instead of tuning it, and it is what would make screen-based `--wait-for-regex`
matching affordable. It also names the one thing standing in the way — **the parser is stateless
between calls**.

The grid was always retained across `render` calls. The parser was not: `render` builds a fresh
`StringScanner`, so an escape split across a chunk boundary failed to match CSI, fell through to
`PRINTABLE`, and was written onto the grid as literal text.

Measured before the fix, on a 425-byte stream of ordinary TUI output:

```
chunk_size  retained  oneshot  identical?
1              384       209      NO
2              363       209      NO
7              284       209      NO
64             218       209      NO
512            209       209      yes
```

At one byte per chunk the rendered screen was 84% longer than the truth, because every escape byte
in the stream had been printed. The first divergent line reads:

    oneshot : "row 0 some text here"
    retained: "[2J[H[1;1H[1;31mrow 0 some text here[0m[K[2;1H..."

## The fix

An unterminated sequence is held for the next chunk, which is what a real terminal does — it keeps
the partial sequence in its parser and shows nothing. The renderer already had the detection for
this (`INCOMPLETE`, used by `incomplete`); it *discarded* the bytes, which is right for a one-shot
render of a truncated transcript and exactly wrong for a retained one.

Bounded by `MAX_CARRY_BYTES`, because OSC and DCS run until their terminator, so a stream that
opens one and never closes it would otherwise buffer without limit. Past the ceiling the carry is
dropped — which is what a one-shot render already did with those bytes, so the ceiling degrades to
the old behaviour rather than to corruption.

## A second defect the adversarial split found

Testing every split point rather than a few tidy ones surfaced a **pre-existing** bug that the
carry did not cause and could not fix on its own.

`INCOMPLETE` matched an OSC body as `\][^\a\e]*`, which stops dead at `\e`. The ST terminator is
two bytes (`\e\\`), so a buffer ending between them leaves a body that pattern cannot cover: the
sequence read as complete-but-unrecognised and its body was printed. That means a one-shot render
of a transcript ending mid-ST has always rendered `]0;title` as visible text — `read --screen`
regularly renders a stream cut wherever the last pty read landed, so this was reachable without any
retained renderer at all.

## What this does and does not buy

Measured over 20 frames of a 40x120 TUI repaint (105KB total):

```
growing-prefix one-shot : 1033.9 ms/tick
retained                :   99.9 ms/tick     10.4x
```

That is the quadratic the ROADMAP describes, removed. It is **not** enough to put screen matching
on the supervisor's thread per pty read: 100ms/tick is still above `POLL_INTERVAL`, and `Screen#heal`
running per glyph is the remaining cost. An independent review measured the same ratio and the same
`heal` finding, and declined to propose a `heal` change it could not validate. This change makes the
retained path *correct*; it does not claim the cost question is closed.

## Scope

The renderer only. Wiring a retained `Screen` into the supervisor is the larger architectural change
and is deliberately not attempted here — this is its prerequisite, and it is independently correct
and independently tested.
