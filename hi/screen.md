---
hi: 1
families: [SCREEN]
---

# What the terminal actually shows

## Intent

A full-screen program repaints constantly, so its byte stream is every frame of every repaint with the answer scattered across them — and the thing it plainly displayed may not be findable in the bytes at all. When the question is what does it say right now, rune should answer with the screen a person would be looking at. That screen is small, which is exactly what you want in front of a model, but it is a snapshot, so rune must be straight about what a snapshot cannot tell you.

## Criteria

- **SCREEN-1**  I can ask for the screen the program is showing rather than the bytes it sent.
- **SCREEN-2**  The screen is available both when I send and when I read.
- **SCREEN-3**  The screen is rendered at the size the program is actually running at, not at some fixed default.
  - **SCREEN-3.a**  The reply tells me the size it rendered at.
  - **SCREEN-3.b**  The reply tells me whether that size was the program's real one or a fallback.
- **SCREEN-4**  A screen is small enough to put in front of a model without my having to bound it.
- **SCREEN-5**  Looking at the screen never costs me the transcript, which stays the record of what happened.
- **SCREEN-6**  Rune says plainly that a screen caught mid-repaint can be half-painted.
  - **SCREEN-6.a**  Rune says what to do instead of trusting a single frame.
