---
id: CHG-0020-add-opt-in-bounded-output-to-rune-run-max-output-bytes-head-tail-truncation-a
state: accepted
type: feature
base_commit: 98894483a078c7e3fcf3739086d4b2cc88a00cd3
---

# Add opt-in bounded output to rune run: --max-output=BYTES head+tail truncation and --tail=N, closing #12

## Intent

Add opt-in bounded output to rune run: --max-output=BYTES head+tail truncation and --tail=N, closing #12

## Affected Canonical Specs

- `pty_runner`

## Acceptance Criteria

- rune run --max-output=BYTES truncates clean_output and raw_output to at most BYTES each, keeping head and tail and reporting truncated/omitted_bytes in the result data; rune run --tail=N keeps only the last N lines of each and reports truncated/omitted_lines; neither flag changes default output when unset; combining both flags fails with a clear error; specs/pty_runner/pty_runner.spec.md documents the new flags, invariants, and error cases; new RSpec coverage for OutputLimiter, PTYRunner, and RunCommand passes; fledge lanes run verify passes.

## No-spec Rationale

Not applicable
