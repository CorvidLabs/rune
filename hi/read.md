---
hi: 1
families: [READ]
---

# Reading back what happened

## Intent

A session keeps a durable record of everything its program printed, and that record should be reachable long after the turn that produced it — while the session runs, and after it has stopped. Because a driven agent produces enormous amounts of output, reading should be something you do in slices: only what is new, only the last few lines, only the lines that match. The record has to stay bounded so an all-day session does not eat the disk, and any output that had to be dropped must be admitted rather than presented as a continuous stream.

## Criteria

- **READ-1**  I can read a session's output back at any time, whether it is still running or long finished.
- **READ-2**  Each read hands me a position I can pass back next time to get only what is new.
  - **READ-2.a**  A position stays meaningful even when older output has been dropped.
  - **READ-2.b**  A position never replays what I already have.
- **READ-3**  I can take a slice of a long transcript instead of all of it.
  - **READ-3.a**  I can ask for just the last few lines.
  - **READ-3.b**  I can cap how many bytes come back.
- **READ-4**  I can search a long transcript for a line and get the lines around it.
  - **READ-4.a**  A pattern that will not compile returns nothing and says so, so a filter that never ran is distinguishable from a filter that found nothing.
- **READ-5**  A read tells me whether the program is still printing, so I never have to grep its own busy marker.
  - **READ-5.a**  A read tells me how long it has been since the program last printed.
- **READ-6**  A transcript stays bounded, so a session left running all day does not grow without limit.
- **READ-7**  When output has been dropped, the read says how much, rather than presenting a gap as continuous output.
