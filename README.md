# rune

A Ruby CLI tool designed from the ground up to be **human & agent first class**.

Every command produces beautiful, colored terminal output for humans — and structured JSON for AI agents. Same tool, same commands, dual interface.

## Install

```sh
gem install rune
```

Or from source:

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

## Usage

```sh
# Human mode (default in terminal)
rune version
# => rune v0.1.0
# => Ruby 4.0.5 (arm64-darwin25)
# => fledge:    ✓ available
# => spec-sync: ✓ available

# Agent mode (--json or piped)
rune version --json
# => {"status":"ok","data":{"name":"rune","version":"0.1.0","ruby":"4.0.5",...}}

# Auto-detects: piping triggers agent mode
rune version | jq .data.version
# => "0.1.0"
```

## CorvidLabs Integration

rune optionally detects and integrates with the [CorvidLabs trust toolchain](https://github.com/CorvidLabs):

- **[fledge](https://github.com/CorvidLabs/fledge)** — Task runner & project lifecycle
- **[spec-sync](https://github.com/CorvidLabs/spec-sync)** — Contract enforcement
- **[augur](https://github.com/CorvidLabs/augur)** — Change risk scoring
- **[attest](https://github.com/CorvidLabs/attest)** — Commit provenance

These tools enhance rune when present but are **never required**.

## Development

```sh
fledge run test        # Run tests
fledge run lint        # Lint
fledge lanes run check # Fast quality check
fledge lanes run verify # Full CI gate
```

## License

MIT
