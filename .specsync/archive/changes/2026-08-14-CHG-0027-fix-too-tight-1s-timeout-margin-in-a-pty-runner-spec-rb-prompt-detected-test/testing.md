---
change: CHG-0027-fix-too-tight-1s-timeout-margin-in-a-pty-runner-spec-rb-prompt-detected-test
artifact: testing
---

# Testing

- `bundle exec rspec spec/rune/pty_runner_spec.rb -e "reports prompt_detected: true for a --timeout kill"` — passes in isolation.
- `fledge run test` — full suite green.
