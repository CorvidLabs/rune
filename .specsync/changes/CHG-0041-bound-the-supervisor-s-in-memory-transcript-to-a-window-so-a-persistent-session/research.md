---
change: CHG-0041-bound-the-supervisor-s-in-memory-transcript-to-a-window-so-a-persistent-session
artifact: research
---

# Research

Same child, 500KB/s, sampling resident memory and file descriptors:

| | before | after |
|---|--------|-------|
| shape | linear with output | plateaus |
| 80s at 500KB/s | 27MB to 69MB | — |
| last 60s of a 150s run | — | +30MB output, +0.16MB memory |
| final samples | still climbing | identical |
| file descriptors | flat at 27 | flat at 27 |

The initial ramp after the fix is Ruby heap warm-up rather than the transcript: it stops within the
first twenty seconds and then holds flat while output grows another 60MB.
