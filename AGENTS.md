# Agent Instructions — xzst

## Overview
xzst is a Ruby CLI tool designed to be equally usable by humans and AI agents.

## Key Principle
**Every command returns structured data.** Commands never print directly.
They return a `Result` object that the `Renderer` formats for the context:
- Terminal (TTY) → human-pretty colored output
- Piped / `--json` → structured JSON

## Working with the Codebase

### Running tasks (use fledge)
```
fledge test         # Run RSpec test suite
fledge lint         # Run RuboCop
fledge lanes verify # Full CI gate
fledge lanes fix    # Auto-format + lint
```

### Adding a new command
1. Create `lib/xzst/commands/your_command.rb`
2. Extend `XZST::Command`
3. Define `name`, `summary`, `call`, and `human_render`
4. Add `require_relative` in `lib/xzst.rb`
5. Add tests in `spec/xzst/commands/your_command_spec.rb`
6. Add/update the spec in `specs/`

### Architecture rules
- Zero external runtime dependencies (stdlib only)
- All commands must work in both human and agent mode
- All commands must have RSpec tests
- All public modules must have spec-sync contracts
