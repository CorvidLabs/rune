---
id: CHG-0014-clarify-mixed-help-aliases-and-invocation-local-cli-modes-in-the-exact-cli-contr
state: accepted
type: documentation
base_commit: e3b9064ab7f89fbd43a9c3e42a92886b5c9ac3b9
---

# Clarify mixed help aliases and invocation-local CLI modes in the exact CLI contract

## Intent

Clarify mixed help aliases and invocation-local CLI modes in the exact CLI contract

## Affected Canonical Specs

- `cli`

## Acceptance Criteria

- 1. The CLI error-case table explicitly states that every mixed or repeated help alias is consumed and help exits 0. 2. The invocation-local invariant explicitly states that prior help and output flags cannot affect a later run. 3. The exact semantic successor is based on e3b9064 and strict SpecSync plus the trust gate pass.

## No-spec Rationale

Not applicable
