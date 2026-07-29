---
change: CHG-0008-keep-rune-watch-stdout-parseable-in-agent-mode-and-stop-the-trust-gate-passing-o
artifact: requirements
---

# Requirements

## R1 — `rune watch` stdout is parseable whenever the caller is a machine

When `--json` or `--ndjson` is given, or when stdout is not a TTY, the whole of `rune watch`'s
stdout MUST parse as a single JSON document (or, for `--ndjson`, a single JSON line). The wrapped
child's live output MUST NOT appear on stdout in any of those cases.

## R2 — the human passthrough is unchanged on a real terminal

When stdout is a TTY and neither output flag is set, the live stream MUST continue to be written to
stdout exactly as it is today, byte for byte and with the same flush behavior. Interactive use is
the primary use case and must not regress.

## R3 — the live view survives agent mode

In agent mode the live stream MUST be written to stderr rather than discarded, so a human driving
the session still sees it while a wrapping process captures stdout.

## R4 — the contract is enforced by an end-to-end test, not by inspection

The suite MUST drive the real `bin/rune` executable and assert that the entirety of its stdout
parses with a real JSON parser, for every registered command in every agent output mode, including
`watch`. The assertion must be over complete stdout, not a substring match.

## R5 — the trust gate never passes on an empty range

CI MUST compute an explicit commit range appropriate to the triggering event, and MUST fail with a
clear error when that range contains zero commits. A gate that inspects nothing must not report
success.

## R6 — provenance follows a squash merge onto the landed commit

When a push to `main` corresponds to a squash-merged pull request whose head carries a passing
attestation, that provenance MUST be forwarded to the landed commit before verification, so the
gate reflects the review that actually happened instead of failing on a hash mismatch.

## R7 — local verification matches CI

`fledge run trust` MUST select the same non-empty range logic locally, falling back to
`HEAD~1..HEAD` when `origin/main..HEAD` is empty, so an agent or human following `AGENTS.md` gets
a meaningful answer on `main`.

## Out of scope

Separating the wrapped child's stdout from its stderr, bounding `PTYRunner`'s output buffering,
adding `--help`, and the `prompt_detected` false-positive rate are all real findings from the same
audit but are tracked separately; none of them are required to close R1-R7.
