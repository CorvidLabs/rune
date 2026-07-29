# rune

A Ruby CLI tool and library designed from the ground up to be **human & AI agent first-class**.

`rune` serves as a universal pseudo-terminal (PTY) runner and structured data bridge for any CLI command or interactive TUI application.

Every command produces formatted, colored terminal output for humans and structured JSON for AI
agents. `rune watch` additionally writes a live NDJSON event stream while the human drives the
session. Same tool, same commands, dual interface.

📖 New here? Start with the **[Getting Started guide](docs/getting_started.md)**.

---

## Capabilities

1. **Dual Output (Human TTY / Agent JSON & NDJSON)**
   - Terminal mode: formatted colored output (`rune version`)
   - Agent JSON mode: `--json` or automatic pipe detection (`rune version | cat`)
   - Agent NDJSON mode: `--ndjson` for a consistent result envelope (`rune version --ndjson`)
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
5. **Live Interactive Passthrough (`rune watch`)**
   - Puts your terminal in raw mode and forwards keystrokes to the child live, byte-for-byte
   - Streams the child's output to your screen as it happens (unlike `rune run`, which buffers and
     returns everything at the end)
   - Simultaneously logs every chunk as an NDJSON event to a temp file (path announced once, or
     `--log=PATH`) so an AI agent can tail the session live while a human drives it

---

## Install

The unqualified `rune` gem name is already taken on the public RubyGems.org registry by an
unrelated package, so `gem install rune` there installs the wrong thing. Install the maintained,
checksum-pinned formula from the CorvidLabs Homebrew tap:

```sh
brew install corvidlabs/tap/rune
rune version --json
```

Upgrade later releases through the same channel:

```sh
brew upgrade corvidlabs/tap/rune
```

For source development:

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

---

## Usage Examples

### 0. Discover the CLI

```sh
rune --help              # every command, plus the global flags
rune run --help          # one command's usage and its own flags
rune help watch          # same thing, spelled the other way
```

Help is structured too, so an agent can discover the surface without scraping text:

```sh
rune run --help --json | jq '.data | {usage, flags}'
```
```json
{
  "usage": "rune run [--timeout=SECONDS] [--] <command...>",
  "flags": [
    { "flag": "--timeout=SECONDS", "description": "Kill the wrapped command after N seconds (default 30). Before `--` only." }
  ]
}
```

> **Use `--` before the wrapped command.** Every rune flag — `--json`, `--ndjson`, `--help`,
> `--timeout`, `--log` — is recognized *only* before the first `--`. That is what lets
> `rune run -- gh pr list --json number` pass `--json` to `gh` instead of consuming it. Without the
> separator, rune takes the flag for itself and the wrapped command silently never sees it.

### 1. Execute Any CLI Command in Agent JSON Mode
```sh
rune run --json -- git status
```
```json
{
  "status": "ok",
  "data": {
    "command": "git status",
    "exit_code": 0,
    "clean_output": "On branch main\nnothing to commit, working tree clean\n",
    "raw_output": "On branch main\r\nnothing to commit, working tree clean\r\n",
    "prompt_detected": false,
    "duration_ms": 21.05
  }
}
```

### 2. NDJSON Result Envelope
```sh
rune run --ndjson -- fledge lanes run check
```
```json
{"event":"result","status":"ok","data":{"command":"fledge lanes run check","exit_code":0,"clean_output":"...","duration_ms":1652.8}}
```

`rune run --ndjson` emits that single envelope when the command finishes. Use `rune watch` for a
live stream of output events.

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

### 5. Watch a Session Live (Human Drives, Agent Tails)
```sh
# Puts your terminal in raw mode, forwards your keystrokes live — including
# raw escape sequences like arrow keys, not just whole lines — and streams
# output to your screen as it happens. Logs an NDJSON event per chunk to a
# temp file (announced once, up front) so an agent can `tail -f` it live
# without any JSON noise landing in your own terminal. The demo's top-level
# menu is a real arrow-key selector (↑/↓ + Enter, or q to quit).
rune watch -- ruby examples/demo_tui.rb

# Or point the log somewhere specific:
rune watch --log=/tmp/session.ndjson -- ruby examples/demo_tui.rb
```

In agent mode — `--json`, `--ndjson`, or any time stdout isn't a terminal — the live passthrough
moves to **stderr** so stdout carries nothing but the result envelope. The human keeps their live
view; the calling program gets clean JSON:

```sh
rune watch --json -- ruby examples/demo_tui.rb 2>/dev/null | jq .data.log_path
```

---

## CorvidLabs Integration

`rune` integrates with the [CorvidLabs trust toolchain](https://github.com/CorvidLabs):

- **[fledge](https://github.com/CorvidLabs/fledge)** — Task runner & project lifecycle. `rune` is a native `fledge` plugin defined via `plugin.toml`. Install directly via:
  ```sh
  fledge plugins install rune
  fledge rune run --json -- git status
  ```
- **[spec-sync](https://github.com/CorvidLabs/spec-sync)** — Contract enforcement (`specs/`)
- **[augur](https://github.com/CorvidLabs/augur)** — Change risk scoring
- **[attest](https://github.com/CorvidLabs/attest)** — Commit provenance

---

## Architecture & Internals

- 📖 **[Getting Started guide](docs/getting_started.md)** — Output modes, `rune run` usage, timeouts, and parsers with real command output.
- 📖 **[Pseudo-TTY (PTY) Architecture Guide](docs/pty_architecture.md)** — How pseudo-terminals, non-blocking stream reading, ANSI sanitization, prompt detection, script execution, and `rune watch`'s live bidirectional passthrough work under the hood in Ruby.
- 📖 **[Release guide](docs/releasing.md)** — Version synchronization, verification, provenance, tagging, and package publication.

---

## Development & Verification

```sh
fledge run test         # Run RSpec test suite (179 examples, 98%+ line coverage)
fledge run lint         # Run RuboCop linter (0 offenses)
fledge lanes run verify # Full CI gate (lint + tests + strict 100%-coverage spec-sync)
fledge lanes run release # Verify, smoke-test, and build the release gem
fledge run smoke-test   # Runnable, assertion-based tour of real behavior (examples/smoke_test.rb)
COVERAGE=1 bundle exec rspec  # Same suite, plus an HTML coverage report at coverage/index.html
```

`examples/smoke_test.rb` is a standalone, dependency-free script (no bundler/rspec required) that
exercises `rune run`, `--timeout`, `TableParser`/`KeyValueParser`, `Script`, signal forwarding, and
prompt detection against the real CLI binary, with pass/fail output and a non-zero exit on failure.
Useful as a quick manual sanity check, or on a machine without the dev dependencies installed.

---

## License

MIT
