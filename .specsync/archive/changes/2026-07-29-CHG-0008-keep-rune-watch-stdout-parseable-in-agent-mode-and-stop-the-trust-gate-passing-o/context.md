---
change: CHG-0008-keep-rune-watch-stdout-parseable-in-agent-mode-and-stop-the-trust-gate-passing-o
artifact: context
---

# Context

Both defects were found by an independent adversarial audit of `v0.2.1` run against this
repository and against the Homebrew-installed `0.2.1` binary. Neither is a regression: both have
been present since `rune watch` and the trust wiring shipped.

## Defect 1 — `rune watch` breaks the structured-output contract

`WatchCommand#call` builds its watcher with `PTYWatcher.new(clean_args, log: log)` and never
passes `output:`. `PTYWatcher`'s `output:` therefore falls back to its `$stdout` default, so the
wrapped child's live bytes are written straight to the process's real stdout — the same stream the
`Renderer` later writes the JSON envelope to. In agent mode the two interleave:

```
STDOUT: "JSONMODE\r\n{\"status\":\"ok\",\"data\":{...}}\n"
=> stdout parses as JSON: INVALID (unexpected character: 'JSONMODE' at line 1 column 1)
```

This violates `cli.spec.md` invariant 4 (`--json` forces JSON output) and invariant 3 (non-TTY
stdout triggers agent mode), and it is the only command that bypasses the renderer's injected `io`.
`rune version` and `rune run` are unaffected — verified with a real JSON parser under Unicode,
invalid UTF-8, embedded ANSI/NUL bytes, and multi-megabyte payloads.

The existing suite cannot see this. `watch_command_spec.rb` replaces `PTYWatcher` with an
`instance_double`, so the real display stream is never exercised, and `e2e_spec.rb` never invokes
`watch` at all.

## Defect 2 — the risk and provenance gates pass on an empty range

`fledge trust verify` and both CI trust actions default to the range `origin/main..HEAD`. On
`main`, where local `HEAD` equals `origin/main`, that range is empty and the gates report success
without inspecting anything:

```
Augur Risk Gate     range: origin/main..HEAD -> augur verdict: proceed - risk 0/100
Attest Provenance   range: origin/main..HEAD -> attest verify - [ok] PASS (0 commits checked)
```

Because pull requests are squash-merged, the attestation recorded against a reviewed PR head SHA
never applies to the differently-hashed landed commit. Two commits on `main` are consequently
unattested while every gate reports green:

```
$ attest verify --range HEAD~2..HEAD --policy .attest.json ; echo $?
  x 79f7b969fd  requireAttestation: commit has no attestations
  x 2ec05cf246  requireAttestation: commit has no attestations
1
```

`docs/releasing.md` step 2 already requires attesting the landed commit; nothing enforces it, and a
green `fledge trust verify` on `main` actively suggests it was done.
