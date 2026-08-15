---
change: CHG-0033-render-the-terminal-screen-for-session-send-and-read-so-an-agent-driving-a-full
artifact: docs
---

# Docs

`--screen` is documented on the `session` command. The session spec records why it is opt-in, why it
renders client-side, and why `read --screen` ignores `--since`. The parsers spec records what
`ScreenRenderer` deliberately does not model, and that a screen shows the end state rather than the
history.
