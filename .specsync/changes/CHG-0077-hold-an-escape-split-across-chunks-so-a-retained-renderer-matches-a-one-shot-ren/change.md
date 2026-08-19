---
id: CHG-0077-hold-an-escape-split-across-chunks-so-a-retained-renderer-matches-a-one-shot-ren
state: accepted
type: bug_fix
base_commit: f2c687b6d9181e5c29f2ce8b0707186d75b7f4c0
---

# Hold an escape split across chunks so a retained renderer matches a one-shot render

## Intent

Hold an escape split across chunks so a retained renderer matches a one-shot render

## Affected Canonical Specs

- `parsers`

## Acceptance Criteria

- A ScreenRenderer instance renders the same screen however the input stream is chunked: retained(any split of S) == ScreenRenderer.render(S), verified across 2571 split configurations spanning ten escape families including every single-point split, byte-at-a-time, and 200 random multi-point splits per stream, with zero divergence. An unterminated escape is held for the next chunk bounded by MAX_CARRY_BYTES, so an unclosed OSC drops rather than buffering without bound. An OSC or DCS whose two-byte ST terminator is split still reads as incomplete rather than printing its body. One-shot rendering of a stream cut mid-escape is unchanged. Regression tests fail when either arm of the fix is reverted.

## No-spec Rationale

Not applicable
