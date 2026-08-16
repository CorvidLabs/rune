---
change: CHG-0050-extract-the-transcript-out-of-sessioncommand-reconstruction-cursors-search-an
artifact: context
---

# Context

`session_command.rb` had reached 930 lines, the largest file in the project, and had grown by about
seventy in the last two changes alone as transcript search and the busy signal landed.

A third of it was one subject: reading the durable NDJSON log, doing cursor arithmetic across
rotation, searching it, and rendering it to a screen. None of that needs anything from the command
surface except a path, and all of it is pure data transformation — the same shape as the settle
machine, whose extraction made a class of recurring bugs testable.
