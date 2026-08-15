---
change: CHG-0033-render-the-terminal-screen-for-session-send-and-read-so-an-agent-driving-a-full
artifact: plan
---

# Plan

1. Write `ScreenRenderer` against captured real transcripts, not synthetic samples.
2. Split grid state into a nested `Screen` once the parsing and the model both got long enough to
   obscure each other.
3. Add `--screen` to `read`, then to `send`, both client-side.
4. Verify against a live agent, and re-render every transcript already collected as a soak.
