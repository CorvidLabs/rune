# Examples for agents

Programmatic usage: rune returning **structured data** a program can act on, with no human at the
keyboard. Each runs directly with no setup beyond a checkout, and none of them need API keys —
they default to shells and small Ruby children so they work anywhere.

Two integration paths are shown. Most examples `require` the library directly; `cli_envelope.rb`
deliberately does not, and drives the `rune` executable as a subprocess instead — the path for
anything that can only run commands, in any language.

| Example | Shows |
|---|---|
| `parsing_pipeline.rb` | The library end: run any CLI in a pty, parse tables and key/value output into hashes, bound output, read exit codes |
| `session_pipeline.rb` | A persistent session: start once, hold a multi-turn conversation, inspect, stop |
| `multi_agent_fanout.rb` | Several named sessions at once — ask them all the same question and compare |
| `resilient_send.rb` | The four ways a driven agent misbehaves, and how to handle each without an exception |
| `script_automation_example.rb` | Driving an interactive prompt with the `Script` DSL |
| `pty_runner_example.rb` | The smallest `PTYRunner` call |
| `table_parser_example.rb` | `TableParser` on its own |
| `cli_envelope.rb` | Driving rune as a **subprocess** — no `require 'rune'` anywhere, just the JSON envelope |

Point the session examples at a real agent CLI to see the actual use case:

```sh
RUNE_SESSION_CMD=grok RUNE_SETTLE_MS=4000 ruby examples/agents/session_pipeline.rb
RUNE_FANOUT="grok,claude" RUNE_SETTLE_MS=4000 ruby examples/agents/multi_agent_fanout.rb
```

The rule they all illustrate: a driven agent failing is **data**, not an exception. `send` returns
`settled`/`timed_out` on an ordinary `Result`, so the caller decides what happens next.
