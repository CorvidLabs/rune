---
change: CHG-0052-the-screen-tail-can-cut-an-escape-sequence-in-half-and-print-its-remainder-onto
artifact: context
---

# Context

Field feedback reported a duplicated line in a rendered screen and, unusually, did the work to
narrow it: a census of 4.5MB of grok's output showing **109,364 absolute cursor moves, 31,798
synchronised-update brackets, and zero erases of any kind** — no `\e[K`, no `\e[2K`, no
`\e[2J`, no scroll regions.

That profile is the finding. An agent that repaints purely by positioning and overwriting depends on
the terminal remembering every cell it ever wrote. It also means the stream is almost entirely
escape sequences, which is what makes the window's cut dangerous: a cut is far likelier to land
inside a sequence than in text.

The reported duplicate is probably not a rune bug — a painter that never erases and shifts its
layout leaves the old copy on a real terminal too. Looking for it found a different one.
