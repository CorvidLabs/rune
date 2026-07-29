---
change: CHG-0010-add-help-and-h-at-the-top-level-and-per-subcommand-with-declarable-usage-and
artifact: testing
---

# Testing

## Automated coverage

- Bare `--help`, `-h`, and `help` return the overview.
- Per-command aliases return usage and declared flags without constructing `PTYRunner`.
- `rune help <command>` matches per-command alias behavior.
- Human, JSON, and NDJSON renderers receive structured help payloads.
- Help aliases after `--` reach the wrapped child unchanged.
- Mixed and repeated aliases are all removed before command resolution.
- An unknown command returns a structured failure and exit status 1.
- Reusing one `CLI` instance for help and then version renders both correctly.
- Command usage and flags are stored per subclass with an empty default.
- Every shipped command declares usage.

## Verification

- `fledge run test`
- `fledge run lint`
- `fledge lanes run verify`
- `fledge run smoke-test`
- `fledge spec check --strict`
- `fledge trust verify`

The manual matrix covers top-level help, each command's help, unknown-command help, JSON and NDJSON
output, TTY rendering, and separator passthrough.
