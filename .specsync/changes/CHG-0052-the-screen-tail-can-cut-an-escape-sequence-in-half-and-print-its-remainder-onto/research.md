---
change: CHG-0052-the-screen-tail-can-cut-an-escape-sequence-in-half-and-print-its-remainder-onto
artifact: research
---

# Research

Rendered output for a stream cut at three offsets inside a leading `\e[?2026h`:

| bytes lost | before | after |
|---|---|---|
| 0 | `\nHELLO` | `\nHELLO` |
| 2 | `?2026h\nHELLO` | `\nHELLO` |
| 4 | `026h\nHELLO` | `\nHELLO` |

Separately, rune's renderer was checked against **pyte**, an independent emulator, across six
profiles built from the census — incremental streaming diff, scrolling tail with a repainting panel,
overwrite-without-erase, the wrap boundary, scroll from the bottom row, and cursor positions beyond
bounds. All six agree, which is why the reported duplicate is attributed to the painter rather than
the renderer.

Worth recording that the differential test could not have found *this* bug: feeding pyte the same
truncated bytes makes it print the same garbage. Truncation is rune's choice, not the emulator's.
