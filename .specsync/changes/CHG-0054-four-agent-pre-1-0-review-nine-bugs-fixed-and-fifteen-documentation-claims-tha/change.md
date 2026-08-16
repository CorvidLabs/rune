---
id: CHG-0054-four-agent-pre-1-0-review-nine-bugs-fixed-and-fifteen-documentation-claims-tha
state: accepted
type: feature
base_commit: 8856cdf9a4030ba3898c6dc88299e97721cbb187
---

# Four-agent pre-1.0 review: nine bugs fixed, and fifteen documentation claims that were wrong

## Intent

Four-agent pre-1.0 review: nine bugs fixed, and fifteen documentation claims that were wrong

## Affected Canonical Specs

- `session`
- `parsers`
- `cli`

## Acceptance Criteria

- send no longer settles on a partly-arrived echo (0/3 runs returned the answer before, 3/3 after). No escape sequence in child output can crash, hang or exhaust memory in the renderer. Scroll regions are honoured. Unrecognised sequences are consumed rather than printed. Undefined erase parameters are no-ops. Resolving a large turn is linear. --context accepts its separate form. Every factual claim in the docs was executed; the fifteen that were wrong are corrected. 411 examples pass, lint clean.

## No-spec Rationale

Not applicable
