---
hi: 1
families: [CLI]
---

# One tool, two audiences

## Intent

rune is meant to be used by a person at a keyboard and by a program driving it, with neither getting a second-class version. The same verbs do the same work either way; only the presentation changes, and it changes by itself when nobody is watching. A caller should never have to read English to find out what happened, and should always be able to tell rune's own failure from the failure of the thing rune was wrapping. Flags belong to rune only up to the point where the wrapped command begins, and anything ambiguous is refused rather than guessed at.

## Criteria

- **CLI-1**  I get the same behaviour from a command whether I type it myself or a program calls it.
  - **CLI-1.a**  Only the presentation differs between those two, so neither a person nor a program gets a reduced version of the tool.
- **CLI-2**  I get coloured, readable output when I am looking at a terminal.
- **CLI-3**  I get JSON when something other than a person is reading the output.
  - **CLI-3.a**  Piping or redirecting rune's output is enough to get JSON, with no flag to remember.
- **CLI-4**  I can ask for a one-line JSON envelope instead, when the harness around rune expects every command to answer in that shape.
- **CLI-5**  Every reply tells me which version of the wire contract it was written against, so I know what I am reading before I parse it.
- **CLI-6**  Everything a program is meant to parse arrives on one channel, with nothing else mixed into it.
- **CLI-7**  The command I am wrapping receives its own flags untouched, however much they look like rune's.
  - **CLI-7.a**  There is one unmistakable place where rune's flags stop and the wrapped command's begin.
  - **CLI-7.b**  A flag rune does not recognise, in the place rune's own flags go, is refused rather than run or passed along.
- **CLI-8**  A flag that would have no effect on the subcommand I called is refused rather than accepted and quietly ignored.
- **CLI-9**  Two flags that contradict each other are refused rather than one of them silently winning.
- **CLI-10**  A failure explains in plain words what went wrong.
- **CLI-11**  A failure carries a stable code a program can branch on instead of prose it has to grep.
  - **CLI-11.a**  A code a client has never seen still routes somewhere sensible, because every code names the coarse kind of problem it is.
  - **CLI-11.b**  A failure tells me whether repeating the identical call could plausibly work.
- **CLI-12**  A bug in rune reads differently from a mistake in my call.
- **CLI-13**  Rune's own failure is never confusable with the failure of the command it was wrapping.
