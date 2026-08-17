---
change: CHG-0062-bound-rune-run-timeout-when-the-child-is-still-printing-and-let-a-second-sign
artifact: requirements
---

# Requirements

1. `--timeout` returns at its deadline whether or not the child is printing.
2. Every trapped INT/TERM reaches the child.
3. A second signal within a burst window forwards to the child *first*, then ends
   rune at `128 + signo` with a well-formed result rather than a mid-render death.
4. A third signal is still the last escape hatch.
5. `rune watch`s interrupt behaviour is unchanged.
