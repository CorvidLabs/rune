# rune

A Ruby CLI tool and library designed from the ground up to be **human & AI agent first-class**.

`rune` serves as a universal pseudo-terminal (PTY) runner and structured data bridge for any CLI command or interactive TUI application.

Every command produces formatted, colored terminal output for humans — and structured JSON or live streaming NDJSON for AI agents. Same tool, same commands, dual interface.

---

## Capabilities

1. **Dual Output (Human TTY / Agent JSON & NDJSON)**
   - Terminal mode: formatted colored output (`rune version`)
   - Agent JSON mode: `--json` or automatic pipe detection (`rune version | cat`)
   - Agent Streaming mode: `--ndjson` for live event streams (`rune version --ndjson`)
2. **Universal PTY Process Runner (`rune run`)**
   - Spawns any CLI tool or TUI inside a pseudo-terminal session
   - Strips ANSI escape codes, cursor movements, and control sequences automatically
   - Disables terminal pagers (`PAGER=cat`) so queries return immediately without hanging
   - Measures process execution duration in milliseconds and detects interactive prompts
3. **Structured Auto-Parsers (`Rune::Parsers`)**
   - `TableParser`: Parses space or pipe-delimited terminal tables into arrays of hashes
   - `KeyValueParser`: Parses key-value output (`key: val`) into typed hashes
   - `TextSanitizer`: Normalizes line endings and cleans ANSI escape codes
4. **Interactive Script DSL (`Rune::Script`)**
   - Step-by-step TUI script automation DSL for driving interactive terminal prompts and TUI menus

---

## Install

```sh
gem install rune
```

Or from source:

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

---

## Usage Examples

### 1. Execute Any CLI Command in Agent JSON Mode
```sh
rune run --json git status
```
```json
{
  "status": "ok",
  "data": {
    "command": "git status",
    "exit_code": 0,
    "clean_output": "On branch main\nnothing to commit, working tree clean\n",
    "prompt_detected": false,
    "duration_ms": 21.05
  }
}
```

### 2. Live NDJSON Streaming Mode
```sh
rune run --ndjson fledge lanes run check
```
```json
{"event":"result","status":"ok","data":{"command":"fledge lanes run check","exit_code":0,"clean_output":"...","duration_ms":1652.8}}
```

### 3. Parse Tabular CLI Output to Hashes
```ruby
require 'rune'

text = <<~TABLE
  NAME           STATUS   VERSION
  fledge-plugin  active   1.0.0
  rust-cli       ready    2.1.0
TABLE

parsed = Rune::Parsers::TableParser.parse(text)
# => [{ name: 'fledge-plugin', status: 'active', version: '1.0.0' }, ...]
```

### 4. Drive Interactive TTY / TUI Applications
```ruby
require 'rune'

# Harness an interactive TUI program with input keystrokes
runner = Rune::PTYRunner.new("fledge plugins search --interactive", input: "\x03")
result = runner.run
# => Result with exit_code 130, clean_output, duration_ms
```

---

## CorvidLabs Integration

`rune` integrates with the [CorvidLabs trust toolchain](https://github.com/CorvidLabs):

- **[fledge](https://github.com/CorvidLabs/fledge)** — Task runner & project lifecycle. `rune` is a native `fledge` plugin defined via `plugin.toml`. Install directly via:
  ```sh
  fledge plugins install rune
  fledge rune run --json git status
  ```
- **[spec-sync](https://github.com/CorvidLabs/spec-sync)** — Contract enforcement (`specs/`)
- **[augur](https://github.com/CorvidLabs/augur)** — Change risk scoring
- **[attest](https://github.com/CorvidLabs/attest)** — Commit provenance

---

## Architecture & Internals

For a deep dive into how pseudo-terminals, non-blocking stream reading, ANSI sanitization, prompt detection, and script execution work under the hood in Ruby, see:

- 📖 **[Pseudo-TTY (PTY) Architecture Guide](docs/pty_architecture.md)** — Guide for developers and AI agents.

---

## Development & Verification

```sh
fledge run test         # Run RSpec test suite (41 examples)
fledge run lint         # Run RuboCop linter (0 offenses)
fledge lanes run verify # Full CI gate (lint + tests + spec-sync)
```

---

## License

MIT
