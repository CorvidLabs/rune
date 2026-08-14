---
change: CHG-0020-add-opt-in-bounded-output-to-rune-run-max-output-bytes-head-tail-truncation-a
artifact: context
---

# Context

Issue #12: `PTYRunner` buffers a command's entire run in memory with no limit, duplicating it
across `clean_output` and `raw_output`. `rune run --json --timeout=5 -- yes` produces an 18.7MB
single-line JSON document — too large for any LLM context window, and the primary agent-facing
failure mode `rune` is supposed to avoid.

The issue offers two suggested fixes: `--max-output=BYTES` with explicit truncation metadata
(head+tail, not just one end), and making `raw_output` opt-in via `--raw`. This change implements
the first in full. It intentionally does not implement the second as a default-behavior flip:
ROADMAP.md's 0.2.0 non-goals explicitly called out changing the `Result`/`Renderer` JSON envelope
shape as breaking for existing agent consumers, and that principle still holds post-freeze.
`--max-output` already bounds `raw_output` too when a caller opts in, which resolves the reported
18.7MB failure mode without silently changing the default payload shape for everyone else.
