---
change: CHG-0071-make-a-failed-launch-loud-name-the-project-a-session-is-in-and-fix-two-multiby
artifact: context
---

# Context

Four defects, from two sources, all verified here before being planned.

**A launch that never happened reported success.** `start` with a command not on
PATH returned `status: "ok"`, `state: "exited"`, `exit_code: 127`. A caller
checking `status` — the field whose entire job is to say whether the call worked
— saw success. It was documented as "check `state` instead", which is the wrong
shape of answer. Reported from a 22-minute real drive where it cost an hour, as
one of three instances of the same root cause: rune does not make failure loud.

**An error that was confidently wrong.** A session started in one directory and
read from another got `No such session`, and that error told the reader to run
`rune session list`, which is scoped to their project and returns nothing —
actively confirming the wrong conclusion. `--all-projects` finds it. This has now
caught three readers, two of whom had read the guide first, which is the point at
which a documented gotcha stops being a documentation problem.

**Two defects the native-language translation round found**, by conducting each
rune session entirely in the language being translated rather than sending
English prompts:

- `CharacterWidth::ZERO` covered Latin, Greek, Cyrillic, Hebrew, Arabic and Thai
  and omitted every Indic script, so `हिन्दी` was charged six columns for six
  codepoints. This is my own table, written hours earlier.
- `ScreenRenderer.resync` searched with `String#index` (characters) and sliced
  with `byteslice` (bytes). On `日本語テキスト\e[1mAFTER` the ESC is at character
  7 and byte 21; it cut at 7, returning `"\xAA\x9Eテキスト\e[1mAFTER"` — both
  splitting a character and failing to drop the remainder it exists to drop.
