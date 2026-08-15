---
change: CHG-0039-fix-six-defects-found-by-a-read-only-grok-kimi-and-agy-council-review-of-0-5-0
artifact: requirements
---

# Requirements

1. The renderer must obey every sequence that moves the cursor, and must not print the byte after an
   escape it does not recognise.
2. The last-column cursor must match a real terminal, so relative moves from it are correct.
3. A send must not be accepted while previous input is still being delivered.
4. A send must not be settled before its own input has been submitted.
5. `stop` must let the cooperative shutdown run before force-killing.
6. A recorded exit code must reflect how the child actually died.
7. Killing a process group must not depend on its leader still being alive.
