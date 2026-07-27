# frozen_string_literal: true

require_relative "lib/xzst/version"

Gem::Specification.new do |spec|
  spec.name          = "xzst"
  spec.version       = XZST::VERSION
  spec.authors       = ["Leif"]
  spec.email         = ["leif@corvidlabs.xyz"]

  spec.summary       = "A human & agent first-class CLI tool"
  spec.description   = "xzst — a Ruby CLI designed equally for humans and AI agents. " \
                        "Every command produces beautiful terminal output for humans and " \
                        "structured JSON for agents. Optionally integrates with the " \
                        "CorvidLabs trust toolchain (fledge, spec-sync, augur, attest)."
  spec.homepage      = "https://github.com/CorvidLabs/xzst"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.files         = Dir["lib/**/*", "bin/*", "LICENSE", "README.md"]
  spec.bindir        = "bin"
  spec.executables   = ["xzst"]
  spec.require_paths = ["lib"]

  # Zero runtime dependencies — stdlib only
end
