---
id: CHG-0037-fix-two-defects-found-by-having-grok-and-claude-review-this-branch-through-rune
state: accepted
type: feature
base_commit: ec7cb59c877ecc4bb64d5dbb8b2c95ea015becd5
---

# Fix two defects found by having grok and claude review this branch through rune itself: erase-line excluded the cursor cell, and backpressure defeated the terminator delay

## Intent

Fix two defects found by having grok and claude review this branch through rune itself: erase-line excluded the cursor cell, and backpressure defeated the terminator delay

## Affected Canonical Specs

- `parsers`
- `session`

## Acceptance Criteria

- ScreenRenderer erases inclusive of the cell under the cursor in both directions per ECMA-48: ABCD with the cursor on column 3 and EL 1 renders as three spaces then D, and erasing with the cursor on the last column clears the line. deliver_submit restarts the terminator delay while text is still queued, so the delay is measured from the last text byte going out rather than from when the send arrived. Three regression tests, all verified failing against the unfixed code and passing against the fix. Full suite and lint pass.

## No-spec Rationale

Not applicable
