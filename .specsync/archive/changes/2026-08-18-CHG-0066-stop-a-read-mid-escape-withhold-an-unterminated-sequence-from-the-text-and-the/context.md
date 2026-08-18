---
change: CHG-0066-stop-a-read-mid-escape-withhold-an-unterminated-sequence-from-the-text-and-the
artifact: context
---

# Context

Found by nine agents translating the README into nine languages, each driving
kimi, grok or claude through a rune session. The translations were the pretext;
this is what the dogfooding turned up, and it is the most dangerous shape this
project has — a reply that was well-formed and wrong.

`strip_ansi` only matches sequences that *terminated*. A sequence split across
two pty reads was therefore wrong at both ends. Reproduced exactly as reported,
against a child that printed `READY`, then `\e[3`, slept, then `1mRED\e[0m`:

    read (no flags)            clean_output "READY\n\e[3"   cursor 10
    read --since=10 --screen   clean_output "1mRED\n"       screen "READY\nRED"
    list                       last_line    "1mRED"

The second reply contradicts itself inside one payload: `clean_output` says the
child printed `1mRED`, `screen` says `RED`. The child printed `RED`.

My first attempt to reproduce this failed and I nearly wrote it off. I split the
escape across pty reads but then read the *whole* transcript, by which point both
halves were present and concatenated, so `strip_ansi` saw a complete sequence.
The reporter reads while the child is still mid-sequence, which is the ordinary
case for a live session and not an edge one.
