# Examples for humans

Interactive programs meant to be **driven by a person at a terminal**. They exist to exercise and
demonstrate `rune watch` and `rune session attach`, both of which need a real TTY — and to give the
agent-facing examples something realistic to drive that costs no API quota.

| Example | Shows |
|---|---|
| `demo_tui.rb` | An arrow-key TUI menu: raw-mode input, redraws, and a nested prompt |
| `fake_agent.rb` | A stand-in agent REPL — prompts, thinks with a spinner, then answers |
| `confirm_flow.rb` | The three prompt shapes rune has to cope with: `[y/N]`, a hidden password, and a numbered choice |

```sh
# Drive a TUI live, with an agent tailing the NDJSON log from another pane
rune watch -- ruby examples/humans/demo_tui.rb

# Hold a session open, take the wheel, then hand it back (Ctrl-] detaches)
rune session start  --name demo -- ruby examples/humans/fake_agent.rb
rune session send   --name demo --settle-ms 2000 "hello"
rune session attach --name demo
rune session stop   --name demo

# Answer prompts by hand, or script them and read the structured result
rune watch -- ruby examples/humans/confirm_flow.rb
printf 'y\nhunter2\n2\n' | rune run --json -- ruby examples/humans/confirm_flow.rb | jq .data
```

`demo_tui.rb` and `fake_agent.rb` are deliberately *real* TUIs — raw keystrokes and repaint traffic,
not line input. That is what exposes the terminal-handling bugs a line-buffered example never would;
several rune fixes came from exactly this.
