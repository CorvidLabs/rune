---
change: CHG-0008-keep-rune-watch-stdout-parseable-in-agent-mode-and-stop-the-trust-gate-passing-o
artifact: plan
---

# Plan

1. Route `WatchCommand`'s live display stream by output mode, honoring the `options` hash it
   already receives (R1, R2, R3).
2. Add unit coverage in `spec/rune/commands/watch_command_spec.rb` asserting the stream chosen for
   each of: `--json`, `--ndjson`, non-TTY stdout, and plain TTY stdout (R1, R2, R3).
3. Add the end-to-end stdout-purity group to `spec/rune/e2e_spec.rb`, covering every registered
   command in every agent output mode, with `watch` driven through a real pty (R4).
4. Update `specs/watch/watch.spec.md` with the new invariant, the new internal method, and a
   change-log entry; update `specs/cli/cli.spec.md`'s invariant 3/4 wording so the stdout-purity
   guarantee is stated once, canonically (R1).
5. Add the `Resolve trust range` and `Reject a vacuous trust range` steps to the CI trust job, wire
   `range` and `forward-from` into the Augur and Attest steps, and grant `pull-requests: read`
   (R5, R6).
6. Add `scripts/trust_range.sh` and point the `trust` task at it (R7).
7. Update `README.md` and `CHANGELOG.md`; correct the stale example count while in `README.md`.
8. Run `fledge lanes run verify`, `fledge run smoke-test`, and a manual reproduction of both
   defects to confirm each is closed.
