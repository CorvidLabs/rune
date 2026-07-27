# xzst

A Ruby CLI tool designed from the ground up to be **human & agent first class**.

Every command produces beautiful, colored terminal output for humans — and structured JSON for AI agents. Same tool, same commands, dual interface.

## Install

```sh
gem install xzst
```

Or from source:

```sh
git clone https://github.com/CorvidLabs/xzst.git
cd xzst
bundle install
ruby bin/xzst version
```

## Usage

```sh
# Human mode (default in terminal)
xzst version
# => xzst v0.1.0
# => Ruby 4.0.5 (arm64-darwin25)
# => fledge:    ✓ available
# => spec-sync: ✓ available

# Agent mode (--json or piped)
xzst version --json
# => {"status":"ok","data":{"version":"0.1.0","ruby":"4.0.5",...}}

# Auto-detects: piping triggers agent mode
xzst version | jq .data.version
# => "0.1.0"
```

## CorvidLabs Integration

xzst optionally detects and integrates with the [CorvidLabs trust toolchain](https://github.com/CorvidLabs):

- **[fledge](https://github.com/CorvidLabs/fledge)** — Task runner & project lifecycle
- **[spec-sync](https://github.com/CorvidLabs/spec-sync)** — Contract enforcement
- **[augur](https://github.com/CorvidLabs/augur)** — Change risk scoring
- **[attest](https://github.com/CorvidLabs/attest)** — Commit provenance

These tools enhance xzst when present but are **never required**.

## Development

```sh
fledge test          # Run tests
fledge lint          # Lint
fledge lanes verify  # Full CI gate
```

## License

MIT
