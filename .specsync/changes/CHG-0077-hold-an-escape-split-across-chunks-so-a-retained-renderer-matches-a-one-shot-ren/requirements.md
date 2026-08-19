---
change: CHG-0077-hold-an-escape-split-across-chunks-so-a-retained-renderer-matches-a-one-shot-ren
artifact: requirements
---

# Requirements

1. A `ScreenRenderer` instance renders the same screen however the stream is chunked:
   `retained(any split of S) == ScreenRenderer.render(S)`.
2. A chunk ending on a bare `ESC` holds that byte, rather than dropping it and leaving the next
   chunk to arrive headless.
3. A chunk ending inside a CSI, OSC, DCS or charset designation holds the partial sequence.
4. An OSC or DCS whose two-byte ST terminator is split across chunks still reads as incomplete,
   rather than as complete-but-unrecognised with its body printed.
5. The carry is bounded, so a stream that opens an OSC and never closes it cannot buffer without
   limit. Past the ceiling the bytes are dropped, matching prior behaviour.
6. One-shot rendering is unchanged, including for a stream cut mid-escape.
7. The regression tests fail when either arm of the fix is reverted.
