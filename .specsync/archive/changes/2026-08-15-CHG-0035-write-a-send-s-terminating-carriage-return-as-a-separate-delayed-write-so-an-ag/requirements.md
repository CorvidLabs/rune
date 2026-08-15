---
change: CHG-0035-write-a-send-s-terminating-carriage-return-as-a-separate-delayed-write-so-an-ag
artifact: requirements
---

# Requirements

1. A raw-mode child must receive a send's text and its terminating carriage return in two separate
   reads, whatever the length of the text.
2. Behaviour must not regress for children that already worked, cooked-mode or raw.
3. `--no-newline` must continue to send no terminator at all.
4. If a second send arrives while a terminator is still outstanding, ordering must hold: the
   outstanding terminator goes first.
