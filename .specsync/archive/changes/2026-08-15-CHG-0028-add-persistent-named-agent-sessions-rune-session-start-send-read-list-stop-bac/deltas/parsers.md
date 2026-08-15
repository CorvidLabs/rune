## MODIFIED

### SPEC SECTION Change Log
- v1: Active parsers spec contract
- v1: Added `PromptDetector` to this module's file/API coverage (previously untracked by
  spec-sync despite being public since `PTYRunner#detect_prompt?` shipped); documented the
  `<placeholder>` false-positive fix and the pre-existing digit-percent one. Also documented that
  `TableParser.parse` now validates `format:` unconditionally, not only for 2+-line input.
| 2026-07-29 | CHG-0016-fix-prompt-false-positives-and-command-registration-leaks-close-test-gaps-and: Fix prompt false positives and command registration leaks, close test gaps, and make dependency and stdout contracts reproducible |
| 2026-07-30 | Follow-up on the CHG-0016 prompt narrowing: cover macOS zsh `user@host cwd %`, `(venv)` prefixes, and versioned shells like `zsh-5.9%` without reintroducing bare-punctuation false positives |
| 2026-08-14 | CHG-0028-add-persistent-named-agent-sessions-rune-session-start-send-read-list-stop-bac: Broaden `TextSanitizer::ANSI_REGEX` beyond SGR-shaped CSI to also strip private-parameter CSI (`[?1049h`, `[?2026h`), OSC strings (`]0;title`), DCS/SOS/PM/APC strings, and keypad/cursor-key modes. The old pattern left a full-screen TUI's escape traffic almost entirely intact, so `clean_output` was unreadable for exactly the agent CLIs `rune session` drives. No public API change. |
