---
id: CHG-0048-add-read-grep-for-searching-a-long-transcript-and-correct-what-the-docs-claim
state: accepted
type: feature
base_commit: feb88ab148b50c5e1fbd6b7c700111d5fd7e5769
---

# Add read --grep for searching a long transcript, and correct what the docs claim about prompt_detected and settled

## Intent

Add read --grep for searching a long transcript, and correct what the docs claim about prompt_detected and settled

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- rune session read --grep=RE keeps only matching lines, --context=N includes surrounding lines, matching runs against the cleaned text rather than the repaint stream, grep_matches is reported, and an unparseable pattern comes back as grep_error rather than raising. The docs correct two claims that field use disproved: prompt_detected does discriminate but is false for a permission dialog and true for grok's composer, and settled cannot distinguish a finished turn from a child that backgrounded a long command and went quiet. Full suite and lint pass.

## No-spec Rationale

Not applicable
