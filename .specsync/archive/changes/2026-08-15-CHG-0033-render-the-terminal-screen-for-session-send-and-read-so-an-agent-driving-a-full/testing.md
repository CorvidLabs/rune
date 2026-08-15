---
change: CHG-0033-render-the-terminal-screen-for-session-send-and-read-so-an-agent-driving-a-full
artifact: testing
---

# Testing

Unit specs cover repainted regions, erasing, wrapping, scrolling, backspace, tabs, ignored
sequences, tail bounding, invalid UTF-8, and nil/empty input.

Integration specs drive a child that repaints a status line ten times before answering, and assert
the repaint frames survive in `clean_output` while the screen holds only the answer — the difference
being the entire reason the renderer exists.

Two traps found while writing it are now pinned by tests rather than by memory: `/\b/` outside a
character class is a zero-width word boundary, which made the scanner match without consuming and
hang forever on any stream containing a backspace; and `def method = expr if cond` binds the
modifier to the definition, evaluating the guard once at class-definition time.

334 examples, 0 failures; lint clean.
