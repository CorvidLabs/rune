---
change: CHG-0080-say-what-start-actually-does-split-the-roadmap-by-what-would-change-it-and-giv
artifact: requirements
---

# Requirements

1. `docs/sessions.md` describes the `start` contract that ships: a command that cannot be executed
   fails with `status: "error"` and exit 1; a command that starts and exits at once succeeds.
2. The guide says that `state` in a `start` reply is a snapshot which can already be wrong, and
   names `list` or the next `send` as the authority.
3. `ROADMAP.md` separates what must be done before 1.0 from what will ship as a documented
   limitation, and each moved item says why it moved rather than disappearing.
4. A session failure carries a stable `data.code` and, where a session is named, `data.name`.
5. The human rendering of a failure is unchanged.
6. Callers are told the code set will grow, so an unrecognised code is a generic failure.
