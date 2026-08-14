# Getting Started with rune

`rune` is a Ruby CLI and library built to be equally usable by a human at a terminal and an AI
agent driving it programmatically. Every command returns the same structured `Result` — only the
*rendering* changes based on how you're calling it.

## Install

The unqualified `rune` gem name is already taken on the public RubyGems.org registry by an
unrelated package, so `gem install rune` there installs the wrong thing. The supported end-user
installation path is the checksum-pinned formula in the CorvidLabs Homebrew tap:

```sh
brew install corvidlabs/tap/rune
rune version --json
```

Homebrew automatically adds the tap on first install. Upgrade Rune with:

```sh
brew upgrade corvidlabs/tap/rune
```

Clone the source only when developing Rune itself:

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

Or as a [fledge](https://github.com/CorvidLabs/fledge) plugin:

```sh
fledge plugins install rune
fledge rune run --json -- git status
```

## Discovering what's available

```sh
rune --help              # or -h, or `rune help`
rune run --help          # or `rune help run`, or `rune run -h`
```

Command help lists that command's own flags — `--timeout=SECONDS` for `rune run`, `--log=PATH` for
`rune watch` — alongside the global ones. It is structured in agent mode too, so discovery does not
require parsing the human rendering:

```sh
$ rune run --help --json | jq -c '.data.flags'
[{"flag":"--timeout=SECONDS","description":"Kill the wrapped command after N seconds (default 30). Before `--` only."}]
```

Help flags follow the same separator rule as everything else (below): `rune run -- mytool --help`
passes `--help` to `mytool`.

## The three output modes

`rune` picks a rendering mode automatically based on how it's invoked, or you can force one
explicitly with a flag. All three modes execute the exact same command logic — only the output
format differs.

### 1. Human TTY mode (default, interactive terminal)

When stdout is a real terminal and no `--json`/`--ndjson` flag is given, `rune` prints
colorized, human-formatted output:

```sh
$ rune version
rune v0.2.1
```

```sh
$ rune run -- echo "hello"
✓ echo hello (6.2ms, exit 0)

hello
```

### 2. Agent JSON mode (`--json`, or automatic pipe detection)

Pass `--json` explicitly, or simply pipe/redirect `rune`'s output — a non-TTY stdout switches
rendering to JSON automatically, no flag required:

```sh
$ ruby bin/rune run --json -- echo "hello agent"
{"status":"ok","data":{"command":"echo hello\\ agent","exit_code":0,"clean_output":"hello agent\n","raw_output":"hello agent\r\n","prompt_detected":false,"duration_ms":8.09}}
```

```sh
$ ruby bin/rune version | cat
{"status":"ok","data":{"name":"rune","version":"0.2.1","ruby":"4.0.5","ruby_platform":"arm64-darwin25","fledge":true,"specsync":true}}
```

Every JSON response has the same envelope: `{"status": "ok"|"error", "data": {...}}` (or
`{"status": "error", "error": "..."}` on failure).

Rune writes the final envelope to stdout for both success and failure. That gives agents one
parseable result channel, but it also means a human redirecting stdout redirects Rune-level error
messages too. Stderr is reserved for operational announcements and live `rune watch` passthrough
that must not corrupt structured stdout.

Global output flags are recognized only before the first `--` separator. Tokens after it belong to
the wrapped command and are preserved, so `rune run -- tool --json` passes `--json` to `tool`.

### 3. Agent NDJSON envelope mode (`--ndjson`)

`--ndjson` wraps the same result in an `{"event": "result"|"error", ...}` envelope instead of the
plain `{"status": ...}` shape `--json` uses — a format some agent harnesses expect uniformly for
every command, `rune run` included:

```sh
$ ruby bin/rune run --ndjson -- echo "hello stream"
{"event":"result","status":"ok","data":{"command":"echo hello\\ stream","exit_code":0,"clean_output":"hello stream\n","raw_output":"hello stream\r\n","prompt_detected":false,"duration_ms":11.45}}
```

For `rune run`, this is still exactly one line, emitted once the command finishes — `PTYRunner`
buffers the whole run and returns a single `Result`, so `--ndjson` here is an envelope choice, not
incremental streaming. For an actual live event stream as a long-running or interactive command
progresses, see [`rune watch`](#watching-a-session-live-with-rune-watch) below, which emits one
NDJSON line per output chunk as it happens.

## Running commands with `rune run`

`rune run` spawns any CLI command or interactive TUI inside a real PTY, strips ANSI escape
sequences, disables pagers, and measures execution time:

```sh
rune run -- git status
rune run --json -- npm test
rune run --ndjson -- fledge lanes run check
```

### Overriding the timeout

Every `rune run` invocation has a 30-second default timeout. Override it with `--timeout=SECONDS`,
placed *before* the `--` separator so it isn't mistaken for a flag belonging to the wrapped
command:

```sh
$ ruby bin/rune run --json --timeout=1 -- sleep 3
{"status":"ok","data":{"command":"sleep 3","exit_code":124,"clean_output":"\n[rune] Execution timed out after 1 seconds","raw_output":"\n[rune] Execution timed out after 1 seconds","prompt_detected":false,"duration_ms":1005.32}}
```

A timed-out command returns exit code `124` with a `[rune] Execution timed out after N seconds`
message appended to the captured output — it's still a normal `Result`, not an exception.

## Watching a session live with `rune watch`

`rune run` buffers a command's entire output and only returns it once the command finishes — great
for scripting and capture, but no good if you actually want to sit at the keyboard and drive an
interactive program while something else observes the session. `rune watch` is built for that: it
puts your terminal in raw mode, forwards every keystroke you type to the child live — including
raw escape sequences like arrow keys, not just whole lines — streams the child's output to your
screen as it happens (not at the end), and simultaneously logs every chunk as an NDJSON event — so
an AI agent can tail the session in real time while a human drives it.

```sh
# A small interactive demo program ships with rune specifically to try this against:
rune watch -- ruby examples/humans/demo_tui.rb
```

The event log defaults to a collision-safe, owner-only (`0600`) temp file, not stderr — mixing
NDJSON events into the same terminal as the live passthrough was the original design, and real
usage immediately showed it was the wrong default (the interleaved JSON made the session
unreadable). The path is announced once, up front:

```
[rune watch] live event log: /tmp/rune-watch-20260728-12345-abcd.ndjson
```

`tail -f` that path from another pane (or have an agent tail it) to watch the session live, with
your own terminal staying clean. Point it somewhere specific instead with `--log=PATH`:

```sh
rune watch --log=/tmp/session.ndjson -- ruby examples/humans/demo_tui.rb
```

Each log line is a JSON object: `{"event":"start","command":"...","pid":...}`, then one
`{"event":"output","bytes":N,"text":"..."}` per chunk as it streams, then
`{"event":"exit","exit_code":N}` when the child exits.

### `rune watch` in agent mode

`rune watch` follows the same output-mode rules as every other command. Under `--json`, `--ndjson`,
or any time stdout isn't a terminal, the live passthrough moves to **stderr** and stdout carries
only the result envelope — so a wrapping program can parse stdout directly while the human at the
keyboard still sees their session:

```sh
rune watch --json -- ruby examples/humans/demo_tui.rb 2>/dev/null | jq .
```

```json
{
  "status": "ok",
  "data": {
    "command": "ruby examples/humans/demo_tui.rb",
    "exit_code": 0,
    "duration_ms": 4820.11,
    "log_path": "/tmp/rune-watch-20260728-12345-abcd.ndjson"
  }
}
```

Drop the `2>/dev/null` to keep watching the session yourself while the JSON is captured elsewhere.

`rune watch` requires a real terminal (it refuses to run if stdin isn't a TTY — there's no
meaningful non-interactive mode) and won't work over `rune run`'s own PTY inception, so it can't be
demonstrated in a piped example the way the rest of this guide is. `examples/humans/demo_tui.rb`'s top-level
menu is a real arrow-key selector (↑/↓ + Enter, or `q` to quit) rather than type-a-number-and-press-
Enter, specifically to exercise raw single-byte and escape-sequence forwarding — the thing a purely
line-buffered menu never touches. `examples/humans/demo_tui.rb`'s own header comment has copy-pasteable
commands, and `spec/rune/pty_watcher_spec.rb` shows how the underlying forwarding/logging mechanics
are unit-tested, including a test that drives the arrow-key menu itself end-to-end (a fake terminal
object plus `IO.pipe`s drives a real interactive child process without needing an actual controlling
terminal).

## Parsing structured text

`Rune::Parsers::TableParser` and `Rune::Parsers::KeyValueParser` turn unstructured terminal output
into Ruby hashes:

```ruby
require 'rune'

Rune::Parsers::TableParser.parse(<<~TABLE)
  NAME           STATUS   VERSION
  fledge-plugin  active   1.0.0
TABLE
# => [{ name: 'fledge-plugin', status: 'active', version: '1.0.0' }]
```

`TableParser.parse` accepts a `format:` keyword (`:auto` by default, or `:pipe`/`:space` to force
a parsing mode) — see [`specs/parsers/parsers.spec.md`](../specs/parsers/parsers.spec.md) for the
heuristic's known limitations before relying on `:auto` against unfamiliar output.

## Next steps

- [`examples/smoke_test.rb`](../examples/smoke_test.rb) — `ruby examples/smoke_test.rb` or `fledge
  run smoke-test`. A standalone, assertion-based tour of real behavior (no bundler/rspec required):
  output modes, `--timeout` validation, parsers, `Script`, signal forwarding, prompt detection.
- [`examples/humans/demo_tui.rb`](../examples/humans/demo_tui.rb) — the interactive demo used throughout the
  `rune watch` section above. [`examples/agents/pty_runner_example.rb`](../examples/agents/pty_runner_example.rb),
  [`table_parser_example.rb`](../examples/agents/table_parser_example.rb), and
  [`script_automation_example.rb`](../examples/agents/script_automation_example.rb) are smaller,
  single-concept scripts — each runnable directly (`ruby examples/<name>.rb`) with no setup beyond
  `require_relative '../lib/rune'`.
- [PTY Architecture Guide](pty_architecture.md) — how the PTY runner, stream reading, prompt
  detection, and `rune watch`'s live passthrough work internally.
- [`specs/`](../specs/) — machine-checked module contracts (`spec-sync`) for `cli`, `parsers`,
  `pty_runner`, and `watch`.
- [`AGENTS.md`](../AGENTS.md) — conventions for adding new commands and working with the trust
  toolchain.
