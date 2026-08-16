---
change: CHG-0056-second-review-round-the-regex-echo-bug-fixed-four-renderer-defects-fixed-and
artifact: requirements
---

# Requirements

1. A pattern must be matched against the reply, not against the pty's echo of the input.
2. RIS and DECSTR must reset the scroll region, since 0.8.0 gave the renderer region state and both
   previously left it stale.
3. A private-marker CSI must not run as the public operation sharing its final byte.
4. Non-graphic control bytes must not occupy cells.
5. What is still broken must be documented with its measurements, not narrowed to sound finished.
