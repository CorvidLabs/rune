---
change: CHG-0040-extract-the-pending-send-settle-machine-out-of-the-supervisor-into-its-own-class
artifact: plan
---

# Plan

1. Write `PendingSend` with the loop's facts as parameters rather than ivars.
2. Delegate from the supervisor, one method at a time, checking syntax after each.
3. Retarget the white-box echo tests at the class that now owns the logic.
4. Confirm the full suite, which contains the regression tests for every bug this logic has had.
