---
id: CHG-0070-give-the-screen-a-cell-model-so-a-wide-glyph-occupies-the-two-columns-it-is-draw
state: archived
type: feature
base_commit: ac38dba529ff6cb4838f825b5c3c9594af36b7d1
---

# Give the screen a cell model so a wide glyph occupies the two columns it is drawn in

## Intent

Give the screen a cell model so a wide glyph occupies the two columns it is drawn in

## Affected Canonical Specs

- `parsers`

## Acceptance Criteria

- A screen row is an array of cells, so a column index is an array index. A wide glyph occupies two columns and wraps rather than splitting at the margin; destroying either half blanks both, as a terminal does. A zero-width character attaches to the cell before it and occupies no column. The wide-glyph invariant is restored by one heal pass after each mutating operation rather than by teaching twelve operations about pairs. All five renderer gaps are closed, and the spec invariant that wrongly recorded this fix as measured-worse is corrected with the three-revision measurement that reverses it.

## No-spec Rationale

Not applicable
