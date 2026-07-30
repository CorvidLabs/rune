---
id: CHG-0015-record-exact-supersession-for-the-committed-cli-help-contract-and-document-cli-r
state: archived
type: documentation
base_commit: e433ab7d590e01f8acfb6d8c27fbabcfca35fdf4
---

# Finalize the committed CLI help contract and document CLI reuse recovery

## Intent

Finalize the committed CLI help contract and document CLI reuse recovery

## Affected Canonical Specs

- `cli`

## Acceptance Criteria

- 1. The CLI error-case table states that a reused CLI after help resets modes and dispatches normally. 2. The final CLI contract preserves every previously accepted help and stdout-purity guarantee. 3. Strict SpecSync and the unified trust gate pass with no stale evidence after overlapping accepted records are freshly reverified.

## No-spec Rationale

Not applicable
