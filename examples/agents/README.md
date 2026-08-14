# Examples for agents

Programmatic usage: rune returning **structured data** a program can act on, with no human at the
keyboard. Each script runs directly (`ruby examples/agents/<name>.rb`) with no setup beyond a
checkout.

| Example | Shows |
|---|---|
| `pty_runner_example.rb` | Running any CLI in a pty and reading the structured `Result` |
| `table_parser_example.rb` | Turning tabular CLI output into arrays of hashes |
| `script_automation_example.rb` | Driving an interactive prompt with the `Script` DSL |
| `session_pipeline.rb` | One agent driving another through a persistent `rune session` |

The CLI equivalent of all of these is `--json`: every command returns the same envelope on stdout,
so `rune run --json -- git status | jq .data.clean_output` is the shell-side version.
