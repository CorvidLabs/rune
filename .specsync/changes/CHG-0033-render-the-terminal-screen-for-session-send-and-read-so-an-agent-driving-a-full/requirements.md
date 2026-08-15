---
change: CHG-0033-render-the-terminal-screen-for-session-send-and-read-so-an-agent-driving-a-full
artifact: requirements
---

# Requirements

1. A caller can obtain what the callee's terminal is actually displaying, not only the bytes that
   arrived.
2. The default result shape is unchanged: the screen appears only when asked for.
3. Rendering must not run on the supervisor's event-loop thread.
4. Rendering must terminate on any input, including malformed escape sequences and invalid UTF-8,
   and must be bounded for a transcript that grows without limit.
