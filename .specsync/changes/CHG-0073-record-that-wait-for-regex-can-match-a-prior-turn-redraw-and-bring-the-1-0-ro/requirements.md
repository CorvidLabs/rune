---
change: CHG-0073-record-that-wait-for-regex-can-match-a-prior-turn-redraw-and-bring-the-1-0-ro
artifact: requirements
---

# Requirements

- The session contract and the English sessions guide must not call `--wait-for-regex`
  deterministic without stating that a reused pattern can match a prior-turn reprint.
- The two candidate fixes that were not shipped must be recorded so they are not tried
  again as a hurry-up patch.
- Unique-per-turn sentinels must still match after a reprint of an earlier answer.
- `ROADMAP.md` must not list the renderer as open, and must not list the unreproduced
  half-painted `--screen` frame as a 1.0 blocker.
