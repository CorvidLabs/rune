---
change: CHG-0016-fix-prompt-false-positives-and-command-registration-leaks-close-test-gaps-and
artifact: design
---

# Design

## Prompt recognition

Remove the catch-all trailing punctuation pattern and the unanchored question/capital pattern. Keep explicit confirmation, labeled prompt, wizard-marker, arrow, and shell-prompt shapes. This favors false negatives over false positives because agents can still inspect output, while a false `prompt_detected` value causes incorrect control flow.

## Command registration

Register a command at the moment its DSL name is declared. `CLI.register(command_class)` writes the registry directly; `Command.inherited` and its global `TracePoint` disappear. `Command.name` becomes a getter/setter: with an argument it declares the CLI name, and without one it preserves Ruby's normal class-name reflection.

## Contract guards

Add direct tests for:

- issue #11's ordinary-output examples;
- anonymous `Class.new` registration and zero new enabled TracePoints;
- NDJSON failures using `event: "error"`;
- explicit `--log=PATH` creation mode `0600`.

Track `Gemfile.lock` and generate it with Bundler 2.4 so the Ruby 3.0–4.0 CI matrix consumes one dependency graph.
