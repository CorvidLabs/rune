# frozen_string_literal: true

require_relative "lib/rune/version"

Gem::Specification.new do |spec|
  spec.name          = "rune"
  spec.version       = Rune::VERSION
  spec.authors       = ["Leif"]
  spec.email         = ["leif@corvidlabs.xyz"]

  spec.summary       = "A human & agent first-class CLI tool"
  spec.description   = "rune — a Ruby CLI designed equally for humans and AI agents. " \
                        "Every command produces beautiful terminal output for humans and " \
                        "structured JSON for agents. Optionally integrates with the " \
                        "CorvidLabs trust toolchain (fledge, spec-sync, augur, attest)."
  spec.homepage      = "https://github.com/CorvidLabs/rune"
  spec.license       = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "https://github.com/CorvidLabs/rune/releases"
  spec.metadata["allowed_push_host"] = "https://rubygems.pkg.github.com/CorvidLabs"

  spec.required_ruby_version = ">= 3.0"

  spec.files         = Dir["lib/**/*", "bin/*", "LICENSE", "README.md", "plugin.toml"]
  spec.bindir        = "bin"
  spec.executables   = ["rune"]
  spec.require_paths = ["lib"]

  # Zero runtime dependencies — stdlib only
end
