---
hi: 1
families: [RUN]
---

# Running one command

## Intent

The simplest thing rune does: take one command, run it in a real terminal so it behaves the way it would for a person, and hand the whole thing back as data once it finishes. Wrapping a colourful full-screen tool should be as safe as wrapping a plain script, and nothing should ever hang forever waiting for a reader that will never come. The result should be small enough to put in front of a model, honest about anything it had to leave out, and honest about anything it is only guessing at.

## Criteria

- **RUN-1**  I can run any command inside a real pseudo-terminal and get one structured result once it finishes.
- **RUN-2**  The output comes back with escape codes and cursor moves removed, so it reads as plain text.
- **RUN-3**  I can also see exactly what the command emitted, escapes and all.
- **RUN-4**  A command that would normally page its output answers straight away instead of waiting for a reader.
- **RUN-5**  I am told how long the command took.
- **RUN-6**  I get the wrapped command's own exit status back, so rune drops into a shell pipeline where the bare command used to be.
- **RUN-7**  A command that never finishes is killed after a limit I can set.
  - **RUN-7.a**  A killed command still returns everything it printed before the kill.
  - **RUN-7.b**  A timeout comes back as an ordinary result with its own recognisable exit status, rather than as an exception.
- **RUN-8**  I can cap how much output comes back.
  - **RUN-8.a**  I am told how much output was left out.
  - **RUN-8.b**  The place where output was cut is marked in the text itself, so what comes back never reads as something the command actually printed.
- **RUN-9**  I can have the command's error output kept apart from its ordinary output when I need to tell the two apart.
- **RUN-10**  Interrupting rune interrupts the command I wrapped, every time and not only the first time.
  - **RUN-10.a**  Interrupting twice in quick succession ends the run rather than waiting on a command that will not stop.
  - **RUN-10.b**  Nothing of an interrupted run is left running behind me.
- **RUN-11**  A command given as an explicit list of arguments runs exactly as written, with no shell slipped in between.
- **RUN-12**  I am told when the output looks like the command is waiting for input.
  - **RUN-12.a**  Rune is plain that this is a guess rather than a verdict, so I do not build a decision on it.
