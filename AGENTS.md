# Agent Instructions — rune

## Overview
rune is a Ruby CLI tool designed to be equally usable by humans and AI agents.

## Key Principle
**Every command returns structured data.** Commands never print directly.
They return a `Result` object that the `Renderer` formats for the context:
- Terminal (TTY) → human-pretty colored output
- Piped / `--json` → structured JSON

## Working with the Codebase

### Running tasks (use fledge)
```
fledge run test        # Run RSpec test suite
fledge run lint        # Run RuboCop
fledge lanes run verify # Full CI gate
fledge lanes run fix    # Auto-format + lint
```

### Adding a new command
1. Create `lib/rune/commands/your_command.rb`
2. Extend `Rune::Command`
3. Define `name`, `summary`, `call`, and `human_render`
4. Add `require_relative` in `lib/rune.rb`
5. Add tests in `spec/rune/commands/your_command_spec.rb`
6. Add/update the spec in `specs/`

### Architecture rules
- Zero external runtime dependencies (stdlib only)
- All commands must work in both human and agent mode
- All commands must have RSpec tests
- All public modules must have spec-sync contracts

<!-- CorvidLabs trust toolchain: BEGIN (managed, do not edit inside) -->
## CorvidLabs trust toolchain

This repository uses one trust gate. Every session must use it and must not bypass or weaken it.

- Run `fledge trust verify` before calling a change complete.
- Keep module specs synchronized with implementation changes.
- Treat an Augur block verdict as a hard stop that must be surfaced and de-risked.
- Record and verify provenance with Attest after the repository's verification lane passes.
- Keep generated trust configuration and this managed block in place.

<!-- CorvidLabs trust toolchain: END -->
