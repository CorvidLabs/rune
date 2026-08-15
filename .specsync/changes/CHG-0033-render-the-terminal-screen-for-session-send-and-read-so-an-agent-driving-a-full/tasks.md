---
change: CHG-0033-render-the-terminal-screen-for-session-send-and-read-so-an-agent-driving-a-full
artifact: tasks
---

# Tasks

- [x] `ScreenRenderer` with cursor motion, erasing, wrapping, scrolling and tabs
- [x] nested `Screen` owning the grid and cursor
- [x] `--screen` on `read`, rendering the whole transcript
- [x] `--screen` on `send`, rendering after settle
- [x] unit specs for every sequence class, including the hang and the endless-method traps
- [x] integration specs against a repainting child
- [x] verified against a live agent and against every captured transcript
