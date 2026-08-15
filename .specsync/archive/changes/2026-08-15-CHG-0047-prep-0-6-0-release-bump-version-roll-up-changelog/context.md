---
change: CHG-0047-prep-0-6-0-release-bump-version-roll-up-changelog
artifact: context
---

# Context

0.6.0 is a fix release, and every fix in it was found by *running* rune rather than reading it:
driving real agent CLIs, and watching processes over time. Two of the bugs were introduced earlier
in the same week by changes meant to make things better, and one was reported from real use.

Nothing here is a new feature. Users on 0.5.0 have a session whose memory and disk grow without
bound, an attachment that reports two contradictory endings at once, and a terminal renderer that
prints stray letters.
