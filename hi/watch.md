---
hi: 1
families: [WATCH]
---

# Watching while a person drives

## Intent

Sometimes the right thing is for a human to sit at the keyboard and do it themselves, while something else follows along. Watching should feel like using the program directly — keystrokes go through as typed, output appears as it happens — while every byte of the session is quietly recorded somewhere an agent can tail in real time. The recording must never get in the way of the session it is recording, and the session must never be left without a way to end it.

## Criteria

- **WATCH-1**  I can drive an interactive program myself while something else records the whole session.
- **WATCH-2**  My keystrokes reach the program as I type them, including arrow keys and other raw escape sequences rather than only whole lines.
- **WATCH-3**  The program's output reaches my screen as it happens rather than all at the end.
- **WATCH-4**  Every chunk of the session is logged as it happens, so an agent can follow along live from somewhere else.
  - **WATCH-4.a**  The log goes to its own file rather than into my terminal, so the events never make the session unreadable.
  - **WATCH-4.b**  Rune tells me once, up front, where that file is.
  - **WATCH-4.c**  I can put the log somewhere of my own choosing when something is already waiting to read it there.
- **WATCH-5**  When a program is parsing rune's output, my live view moves aside so the parseable answer stays clean.
- **WATCH-6**  Rune refuses to watch when there is no real terminal to take over, rather than half-working.
- **WATCH-7**  The program sees my terminal's real size.
  - **WATCH-7.a**  Resizing my window resizes the program with it.
- **WATCH-8**  I can bound a watch by wall-clock time.
- **WATCH-9**  I can bound a watch by how long it has gone with no output and no typing, which is the bound that means the thing has stopped doing anything.
  - **WATCH-9.a**  The result says which of the two bounds ended the session.
- **WATCH-10**  Ending a watch ends the program I was driving, rather than leaving it orphaned.
