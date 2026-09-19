---
hi: 1
families: [LIBRARY]
---

# Using rune from your own code

## Intent

rune is a library as well as a command, and a program that already speaks Ruby should be able to wrap a terminal, script an interactive prompt, and turn a CLI's printed output into data without pulling anything else in. The parsers exist because terminal output is the only interface many tools have; they should do the obvious thing and let me overrule them where the obvious thing is wrong. Above all, a driven program behaving badly is data, not an exception — the caller decides what happens next.

## Criteria

- **LIBRARY-1**  I can use everything rune does from Ruby, not only from the command line.
- **LIBRARY-2**  Adding rune to my own project brings nothing else along with it.
- **LIBRARY-3**  I can turn a printed table into a list of records without writing a parser.
  - **LIBRARY-3.a**  Rune works out for itself whether a table is pipe-drawn or space-aligned.
  - **LIBRARY-3.b**  I can override that guess where it would be wrong.
- **LIBRARY-4**  I can turn key-and-value output into a hash with numbers and booleans already typed.
- **LIBRARY-5**  I can clean escape codes out of any captured text.
- **LIBRARY-6**  I can script an interactive program as a sequence of waits, keystrokes and pauses.
- **LIBRARY-7**  A driven program misbehaving arrives as data on an ordinary result, so my code decides what happens next instead of catching an exception.
