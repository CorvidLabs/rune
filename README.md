# rune

A Ruby CLI tool and library designed from the ground up to be **human & AI agent first-class**.

`rune` serves as a universal pseudo-terminal (PTY) runner and structured data bridge for any CLI command or interactive TUI application.

Every command produces formatted, colored terminal output for humans and structured JSON for AI
agents. `rune watch` additionally writes a live NDJSON event stream while the human drives the
session. Same tool, same commands, dual interface.

`rune session` goes one step further: it holds an agent CLI — `claude`, `grok`, `codex` — open
across separate invocations, so one agent can drive another conversationally and a human can attach
to the same session and take over.

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
6. **Persistent Named Sessions (`rune session`)**
   - Holds a REPL-shaped child — `claude`, `grok`, `codex`, a shell — open *across* separate `rune`
     invocations, which neither `run` (buffers and returns once) nor `watch` (dies with its child)
     can do
   - **Send-and-settle**: write input, wait for the child to go quiet, get back exactly the output
     that send produced, turning an async TTY into a synchronous request/response call
   - `--screen` returns the *rendered terminal* rather than the raw byte stream, which matters
     because a full-screen agent interleaves its answer with its own repaints — one measured
     transcript went from 361KB of repaint traffic to a 1.1KB screen
   - `attach` hands the live session to a human terminal and **Ctrl-]** gives it back, still running
   - Sessions are named, project-scoped, and archivable; transcripts are bounded on disk and in
     memory, so a session left running for a day does not grow without limit

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
  "usage": "rune run [--timeout=SECONDS] [--max-output=BYTES] [--tail=N] [--separate-streams] [--] <command...>",
  "flags": [
    {
      "flag": "--timeout=SECONDS",
      "description": "Kill the wrapped command after N seconds (default 30). Before `--` only."
    },
    {
      "flag": "--max-output=BYTES",
      "description": "Bound clean_output/raw_output to BYTES each, keeping head+tail. Mutually exclusive with --tail. Before `--` only."
    },
    {
      "flag": "--tail=N",
      "description": "Keep only the last N lines of clean_output/raw_output. Mutually exclusive with --max-output. Before `--` only."
    },
    {
      "flag": "--separate-streams",
      "description": "Adds clean_stdout/clean_stderr (stderr on a pipe, not the pty) alongside the merged view. Before `--` only."
    }
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
rune watch -- ruby examples/humans/demo_tui.rb

# Or point the log somewhere specific:
rune watch --log=/tmp/session.ndjson -- ruby examples/humans/demo_tui.rb
```

In agent mode — `--json`, `--ndjson`, or any time stdout isn't a terminal — the live passthrough
moves to **stderr** so stdout carries nothing but the result envelope. The human keeps their live
view; the calling program gets clean JSON:

```sh
rune watch --json -- ruby examples/humans/demo_tui.rb 2>/dev/null | jq .data.log_path
```

### 6. Drive One Agent CLI From Another (`rune session`)

`run` buffers and returns once; `watch` needs a human at a terminal and ends with its child. Neither
can hold an agent REPL open across calls. `session` can:

```sh
# Start a named session. The child outlives this command.
rune session start --name reviewer -- grok

# Send a prompt and wait for the answer. --screen returns the rendered
# terminal, which is where the answer is actually legible.
rune session send --name reviewer --screen -- "Review lib/rune/session/supervisor.rb for races"

# Come back later — from another process, another agent, another hour.
rune session send --name reviewer --screen -- "Now just the highest-severity one, in one line"

rune session list          # what is running, how idle, what it last printed
rune session stop --name reviewer
```

**Why `--screen` rather than the raw output.** A full-screen agent repaints continuously, so the
byte stream contains every frame of every repaint with the answer split across them. Measured
against grok: a 361KB transcript rendered to a 1.1KB screen, and an answer the agent had plainly
displayed was absent from the byte stream in 3 of 3 turns and present in the rendered screen in 3 of
3. If you are matching on content, match on `screen`.

**Take the wheel yourself**, then give it back without stopping anything:

```sh
rune session attach --name reviewer   # Ctrl-] detaches; the session keeps running
```

Sessions are scoped to the enclosing git working tree, so `reviewer` in two checkouts is two
sessions. That is deliberate, and it is also the most common surprise — if `list` shows nothing,
check the directory you are in and `RUNE_HOME`:

```sh
rune session list --all-projects
```

**Finding one thing in a long transcript.** A day's work with a driven agent reached 379KB, and
neither `--since` nor `--tail` helps when what you want is in the middle:

```sh
rune session read --name reviewer --grep 'THE BOARD' --context 2
```

📖 Full guide, including settle tuning and the known limitations:
**[docs/sessions.md](docs/sessions.md)**.

---

## CorvidLabs Integration

`rune` integrates with the [CorvidLabs trust toolchain](https://github.com/CorvidLabs):

- **[fledge](https://github.com/CorvidLabs/fledge)** — Task runner & project lifecycle. `rune` is a native `fledge` plugin defined via `plugin.toml`. Install directly via:
  ```sh
  fledge plugins install CorvidLabs/rune
  fledge rune run --json -- git status
  ```
- **[spec-sync](https://github.com/CorvidLabs/spec-sync)** — Contract enforcement (`specs/`)
- **[augur](https://github.com/CorvidLabs/augur)** — Change risk scoring

---

## Architecture & Internals

- 📖 **[Getting Started guide](docs/getting_started.md)** — Output modes, `rune run` usage, timeouts, and parsers with real command output.
- 📖 **[Persistent sessions guide](docs/sessions.md)** — `rune session`: named PTY sessions that outlive a single invocation, and send-and-settle for driving one agent CLI from another.
- 📖 **[Pseudo-TTY (PTY) Architecture Guide](docs/pty_architecture.md)** — How pseudo-terminals, non-blocking stream reading, ANSI sanitization, prompt detection, script execution, and `rune watch`'s live bidirectional passthrough work under the hood in Ruby.
- 📖 **[Release guide](docs/releasing.md)** — Version synchronization, verification, provenance, tagging, and package publication.

---

## Development & Verification

```sh
fledge run test         # Run RSpec test suite (405 examples, 87% line coverage)
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
