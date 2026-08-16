---
id: CHG-0052-the-screen-tail-can-cut-an-escape-sequence-in-half-and-print-its-remainder-onto
state: accepted
type: feature
base_commit: 29888fa7284bb23c4a9f8fbfc4983f69d4592ed6
---

# The screen tail can cut an escape sequence in half and print its remainder onto the screen

## Intent

The screen tail can cut an escape sequence in half and print its remainder onto the screen

## Affected Canonical Specs

- `parsers`

## Acceptance Criteria

- Cutting the render window inside an escape sequence no longer prints its remainder onto the screen, at any cut offset within the sequence. The resync is bounded, so a stream whose next escape is further away than the scan keeps its text rather than losing the screen. Regression tests fail without the fix. The docs state what the window costs an agent that never erases.

## No-spec Rationale

Not applicable
