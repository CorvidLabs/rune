---
id: CHG-0006-close-the-remaining-release-policy-review-gaps
state: accepted
type: bug_fix
base_commit: 772dddacd43b01c79c702f6dd3932ad5ccf72a4d
---

# Close the remaining release-policy review gaps

## Intent

Close the remaining release-policy review gaps

## Affected Canonical Specs

- None

## Acceptance Criteria

- SpecSync policy files remain meaningful when generated change artifacts are ignored; both publish jobs reject tags outside vMAJOR.MINOR.PATCH before resolving provenance; release documentation signs and pushes merge-commit attestation before trust verification; regression coverage and all release/trust gates pass

## No-spec Rationale

The CLI v3 contract already requires strict release provenance and SpecSync lifecycle enforcement; these fixes close enforcement and documentation gaps without changing the public Rune CLI
