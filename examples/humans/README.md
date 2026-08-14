# Examples for humans

Interactive programs meant to be **driven by a person at a terminal** — used to exercise and
demonstrate `rune watch` and `rune session attach`, both of which need a real TTY.

| Example | Shows |
|---|---|
| `demo_tui.rb` | An arrow-key TUI menu: raw-mode input, redraws, and a nested prompt |

```sh
rune watch -- ruby examples/humans/demo_tui.rb
```

`demo_tui.rb` is deliberately a *real* TUI (raw keystrokes, not line input), because that is what
exposes the terminal-handling bugs a line-buffered example never would.
