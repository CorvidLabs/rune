---
change: CHG-0072-snap-a-since-that-lands-inside-a-character-forward-instead-of-inventing-u-fff
artifact: requirements
---

# Requirements

- `Transcript#from` must not invent U+FFFD for a `--since` that lands inside a multi-byte
  character the child emitted intact.
- The snap is forward, to the next character start. Bytes before the requested offset are
  never returned.
- A `--since` already on a character start, including every cursor rune itself issues, is
  unchanged.
- Genuinely invalid bytes after the snap point may still be scrubbed; that is not this defect.
