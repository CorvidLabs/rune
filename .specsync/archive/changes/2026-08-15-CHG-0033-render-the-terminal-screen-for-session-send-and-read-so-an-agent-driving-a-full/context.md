---
change: CHG-0033-render-the-terminal-screen-for-session-send-and-read-so-an-agent-driving-a-full
artifact: context
---

# Context

Dogfooding 0.4.0 measured which of the recorded session limitations actually costs the most, and it
was not the settle heuristic. It was this: a settled reply is a raw byte stream, and a full-screen
agent interleaves its answer with its own repaints.

Driving grok, a 13-character answer arrived inside roughly 12KB of repaint traffic with the answer
itself split across frames. Searching the reply for a token the agent had plainly displayed failed
3 turns out of 3 — including in the probe harness written to measure it, which is how the problem
was noticed at all.

`TextSanitizer` cannot fix this. It deletes escape sequences; it does not obey them, so stripping
leaves every frame of every repaint concatenated.
