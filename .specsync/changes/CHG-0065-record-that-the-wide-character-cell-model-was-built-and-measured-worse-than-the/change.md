---
id: CHG-0065-record-that-the-wide-character-cell-model-was-built-and-measured-worse-than-the
state: accepted
type: feature
base_commit: 1749093b9563a42e245ceeb6d6f7eb59fb23fb63
---

# Record that the wide-character cell model was built and measured worse than the gap

## Intent

Record that the wide-character cell model was built and measured worse than the gap

## Affected Canonical Specs

- `parsers`

## Acceptance Criteria

- parsers.spec.md invariant 17 records that a wide-character cell model was implemented and reverted, with the live-output comparison that killed it and the two synthetic probes that reproduce it. The claim is limited to the cases that actually differ; a probe identical in both is labelled baseline rather than evidence. harnesses/renderer_gaps.rb carries the reproduction and says which cases the cell model changed. No production behaviour changes.

## No-spec Rationale

Not applicable
