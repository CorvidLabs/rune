---
change: CHG-0028-add-persistent-named-agent-sessions-rune-session-start-send-read-list-stop-bac
artifact: research
---

# Research

Findings from reading the existing code before designing.

## 1. Neither existing execution model can persist

`PTYRunner` buffers and returns once; `PTYWatcher` streams live but hard-fails
`unless @input.tty?` (`lib/rune/pty_watcher.rb:61`) and writes to a screen. So `watch` is
structurally unavailable to an agent, and `run` cannot hold a REPL open. Confirmed by reading both
classes rather than assumed.

## 2. `prompt_detected` will usually be false for agent CLIs

`PROMPT_PATTERNS` (`lib/rune/parsers/prompt_detector.rb`) matches shell PS1 forms, `[y/N]`,
`Password:`, `➜`. Its own comment states the intent: "Positive matches only... prefer a rare false
negative over a false positive." Agent REPLs generally present none of these shapes.

**This is the single most load-bearing finding in the design.** It is why settle-time is the
primary completion signal and `prompt_detected` is advisory only. Had this gone unchecked, the
obvious design — "wait for a prompt" — would have hung on nearly every real target.

## 3. Nothing to reuse for persistence; a lot to reuse for I/O

Greps confirm the repo currently has **no** `ENV[...]` usage, no `socket`, no FIFO, no
`Process.detach`/`setsid`/`pgroup` anywhere in `lib/` or `spec/`. So `RUNE_HOME`, the Unix socket,
and detached process management are all genuinely new ground.

Conversely `UTF8StreamDecoder`, `OutputLimiter`, `PromptDetector`, `TextSanitizer`, the `Result`
envelope, the `Command` `usage`/`flag` DSL, and `PTYWatcher`'s NDJSON event vocabulary are all
directly reusable — which is the evidence that this feature fits the codebase rather than bolting a
parallel stack onto it.

## 4. Security precedent already exists

`watch_command.rb:130` creates logs `0600`, collision-safe and symlink-resistant. Session state
follows the same standard rather than inventing one.

## 5. The last-non-blank-line rule is currently private

CHG-0024 put `prompt_detected_in?` inside `PTYRunner`. Sessions need identical semantics, so it is
extracted to a shared home instead of duplicated.
