---
change: CHG-0068-correct-the-flag-message-run-gets-wrong-and-the-five-contracts-the-dogfood-foun
artifact: testing
---

# Testing

573 examples, 0 failures; rubocop clean; docs-check green.

The four cases, before and after:

    run --timeout 5    "Unknown option: --timeout ... put the command first"
                    -> "--timeout takes its value inline: --timeout=VALUE ..."
    run --tiemout=5    unchanged, still "Unknown option: --tiemout"
    run --timeout=5    unchanged, applies the timeout
    run -- echo hi --timeout 5   unchanged, passes through to the child

Controls:

    mutation                              failures
    the inline-value branch removed       3 of 4
    --separate-streams left in the list   the drift guard, immediately

That second one was not a planned control. The work order said to derive the set
from `FLAG_PATTERNS.keys + --separate-streams`; the drift test rejected it on the
first run, because `--separate-streams` is boolean — "give the value inline" is
nonsense for it, and the parser consumes it before this path anyway. The set is
the value-taking flags only, and a test now pins that a boolean flag still works
normally.
