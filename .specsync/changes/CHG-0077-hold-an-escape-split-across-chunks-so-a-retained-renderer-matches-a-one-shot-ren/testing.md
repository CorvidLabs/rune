---
change: CHG-0077-hold-an-escape-split-across-chunks-so-a-retained-renderer-matches-a-one-shot-ren
artifact: testing
---

# Testing

The property under test is always the same: `retained(any split of S) == oneshot(S)`. A fix that
works only on tidy splits is not a fix, so nearly all the effort here is adversarial splitting
rather than exotic input.

## Coverage

Ten streams — CSI-heavy repaint, OSC terminated by BEL, OSC terminated by ST, DCS, charset/box
drawing, mode set/reset, scroll region, wide CJK and Arabic glyphs, the erase family, and a
realistic mixed agent frame. For each: every single-point split, a byte-at-a-time split, and 200
random multi-point splits.

```
2571 split configurations tested, 0 divergent
unterminated OSC of 9000 bytes -> carry held 0 bytes (ceiling 4096) ok
OSC split across chunks -> "visible" ok
```

Before the fix the same harness reported 47 divergences across two streams, which is how the
pre-existing ST-terminator defect was found.

## The tests can fail

Each arm was reverted independently against the committed tests:

```
carry-on-incomplete reverted -> 2 failures (chunked-equivalence, split ST terminator)
bare-ESC carry reverted      -> 2 failures (chunked-equivalence, bare trailing ESC)
both present                 -> 5 examples, 0 failures
```

One expectation in the first draft was wrong and was corrected rather than accommodated: `\e[2K`
erases the line and leaves the cursor at column 3, so `"   def"` is right and the test now asserts
equality with the one-shot render rather than a hand-written string.

## Cost

```
20 frames of a 40x120 TUI repaint, 105KB total
growing-prefix one-shot : 1033.9 ms/tick
retained                :   99.9 ms/tick   (10.4x)
```

Deliberately not claimed: that this makes per-tick screen matching affordable. 100ms/tick remains
above `POLL_INTERVAL` and `Screen#heal` is still per-glyph.

## Gates

`bundle exec rspec` 611 examples / 0 failures before, 616 / 0 after. RuboCop clean.
