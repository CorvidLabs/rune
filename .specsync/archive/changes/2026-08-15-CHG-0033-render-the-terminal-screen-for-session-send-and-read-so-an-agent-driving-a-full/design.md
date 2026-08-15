---
change: CHG-0033-render-the-terminal-screen-for-session-send-and-read-so-an-agent-driving-a-full
artifact: design
---

# Design

`Parsers::ScreenRenderer` replays a byte stream onto a virtual screen. It implements the sequences
that decide *where text lands* — cursor motion, erasing, line discipline — and consumes everything
else (colours, modes, title strings), which by definition cannot change which text is on screen.
That scope is what keeps it a parser rather than a terminal emulator.

Split in two: `ScreenRenderer` parses the stream and knows nothing about the grid; the nested
`Screen` owns the grid and cursor and knows nothing about escape sequences.

`--screen` is handled entirely client-side, reading the transcript file that the supervisor already
maintains. The supervisor is untouched by this change — deliberately, since three review rounds
have shown its event loop is where mistakes turn into wedged sessions.

`read --screen` renders the whole transcript rather than the `--since` slice: a screen is the
product of every sequence before it, so replaying from a mid-stream cursor would show a screen the
child never displayed.
