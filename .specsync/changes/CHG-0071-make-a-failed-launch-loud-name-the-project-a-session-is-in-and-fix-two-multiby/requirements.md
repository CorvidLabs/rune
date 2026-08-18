---
change: CHG-0071-make-a-failed-launch-loud-name-the-project-a-session-is-in-and-fix-two-multiby
artifact: requirements
---

# Requirements

1. A command not on PATH fails; a child that exits zero at once does not.
2. A refused launch keeps its record, because that record is the diagnosis.
3. An error about a missing session names the project holding it, when one does.
4. Indic nonspacing marks take no column; spacing marks still take one.
5. `resync` drops the pre-escape remainder whole, whatever encoding it is in.
