---
change: CHG-0054-four-agent-pre-1-0-review-nine-bugs-fixed-and-fifteen-documentation-claims-tha
artifact: requirements
---

# Requirements

1. `send` must not treat a partly-arrived echo as the child having answered.
2. No escape sequence in child output may crash, hang or exhaust memory.
3. Sequences the parser does not recognise must be consumed, never printed.
4. Scroll regions must be honoured, since every full-screen agent sets one.
5. Every factual claim remaining in the docs must have been executed.
