---
id: CHG-0060-bound-send-output-with-max-output-and-tail-and-make-the-two-mutually-exclus
state: accepted
type: feature
base_commit: 7041cb9163a91f82075fe50e1be202ceba717a09
---

# Bound send output with --max-output and --tail, and make the two mutually exclusive

## Intent

Bound send output with --max-output and --tail, and make the two mutually exclusive

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- rune session send honours --max-output and --tail, which it previously parsed and ignored while returning status ok. clean_output is derived from the bounded raw text so the two fields describe the same window and one omitted count is true of both. --max-output combined with --tail is refused on every session subcommand with the same message rune run already uses. Four tests cover these, each verified to fail against deliberately unfixed code. ROADMAP.md's 0.8.0 review table is re-measured against the tree: seven of eight closed, and the oversized-send entry corrected because measurement contradicted it.

## No-spec Rationale

Not applicable
