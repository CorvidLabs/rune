---
change: CHG-0072-snap-a-since-that-lands-inside-a-character-forward-instead-of-inventing-u-fff
artifact: testing
---

# Testing

Measured on `こY` (E3 81 93 59) and on `X😀Y` (1 + 4 + 1 bytes) through `Transcript#from`
directly, and through `session read --since` against a child that prints `→ ünïcode ✓`.

    before   from(1) on こY   "��Y"     (2 × U+FFFD)
             from(2) on こY   "�Y"
             from(2) on 😀    "���Y"
    after    from(1) on こY   "Y"
             from(2) on こY   "Y"
             from(2) on 😀    "Y"

Each new example, plus the strengthened integration test, is red against the unfixed
`.scrub` path (4/4) and green with the snap.

Hole-mapping arithmetic is ASCII-only fixtures and is unchanged (7/7).
