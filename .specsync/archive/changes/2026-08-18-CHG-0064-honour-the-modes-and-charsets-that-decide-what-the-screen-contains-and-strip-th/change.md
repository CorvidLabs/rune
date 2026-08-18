---
id: CHG-0064-honour-the-modes-and-charsets-that-decide-what-the-screen-contains-and-strip-th
state: archived
type: feature
base_commit: cc8bb3c25e807fe07de3cf66687302d97f1ddddb
---

# Honour the modes and charsets that decide what the screen contains, and strip the escapes the sanitizer missed

## Intent

Honour the modes and charsets that decide what the screen contains, and strip the escapes the sanitizer missed

## Affected Canonical Specs

- `parsers`

## Acceptance Criteria

- The renderer honours the alternate screen buffer (1049, 1047, 47), DECAWM, IRM and DEC Special Graphics charset designation with SO/SI, and TextSanitizer strips the two-byte escapes and the full charset-designation set. Four of the five renderer gaps ROADMAP listed as open are closed; double-width characters remain, recorded as a limitation with its measurement. Every fix is verified by a harness that measures against ECMA-48/xterm behaviour rather than a reference emulator, and every new test was falsified against deliberately unfixed code.

## No-spec Rationale

Not applicable
