---
change: CHG-0035-write-a-send-s-terminating-carriage-return-as-a-separate-delayed-write-so-an-ag
artifact: plan
---

# Plan

1. Determine whether the answer was missing because settle fired early or because the renderer was
   wrong — capture both the raw stream and the screen, at settle and again later.
2. Neither: read the rendered screen and see the prompt sitting in the composer.
3. Bisect by input length.
4. Distinguish chunk size from content by writing the same text three ways.
5. Split the write, and re-run the bisect on all three agents.
