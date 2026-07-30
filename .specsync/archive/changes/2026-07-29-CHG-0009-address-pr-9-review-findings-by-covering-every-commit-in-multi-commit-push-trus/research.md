---
change: CHG-0009-address-pr-9-review-findings-by-covering-every-commit-in-multi-commit-push-trus
artifact: research
---

# Research

## Review evidence

- PR #9's P1 review demonstrated that `HEAD~1..HEAD` covers only one commit regardless of push
  batch size.
- PR #9's P2 review demonstrated that top-level `require 'pty'` raises before RSpec reaches
  `PTYRunner.pty_available?` skips.

## Existing platform contracts

- GitHub push events expose immutable `before` and `after`/`sha` boundaries.
- `actions/checkout` already uses `fetch-depth: 0`, so both commits are available to range
  validation.
- `lib/rune/pty_runner.rb` rescues `LoadError` from `require 'pty'` and exposes
  `PTYRunner.pty_available?`.
- Ruby's `RUBYOPT=-I<path>` permits a subprocess test to shadow `pty.rb` and reproduce the missing
  extension deterministically.

## Scope

No Rune public API or canonical runtime behavior changes. The work closes CI enforcement and
test-portability gaps in CHG-0008's already-applied guarantees.
