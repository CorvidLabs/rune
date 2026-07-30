---
id: CHG-0010-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and
state: archived
type: feature
base_commit: 0b2218b4b054368a0cd6562e289ffff9f9199395
---

# Add --help and -h at the top level and per subcommand with declarable usage and flags, while fixing duplicate help aliases and per-run help state

## Intent

Add --help and -h at the top level and per subcommand with declarable usage and flags, while fixing duplicate help aliases and per-run help state

## Affected Canonical Specs

- `cli`
- `pty_runner`
- `watch`

## Acceptance Criteria

- 1. rune --help, rune -h, and rune help return the command overview with exit 0 in human, JSON, NDJSON, and piped modes. 2. rune COMMAND --help, rune COMMAND -h, and rune help COMMAND return that command's declared usage and flags without constructing a PTY runner. 3. Help-looking arguments after the first -- separator are passed unchanged to the wrapped command. 4. Every help alias before the separator is removed while help intent is accumulated, so mixed or repeated aliases such as rune --help -h still return help. 5. Reusing one CLI instance for a help invocation followed by a normal invocation does not leak help rendering state or raise. 6. Command subclasses declare usage and flags through the Command DSL, and help output remains a structured Result. 7. README and getting-started examples use the separator-safe invocation form and document CLI discovery. 8. Full Fledge verification, smoke tests, strict SpecSync, Augur, and Attest gates pass.

## No-spec Rationale

Not applicable
