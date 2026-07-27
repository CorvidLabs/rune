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
