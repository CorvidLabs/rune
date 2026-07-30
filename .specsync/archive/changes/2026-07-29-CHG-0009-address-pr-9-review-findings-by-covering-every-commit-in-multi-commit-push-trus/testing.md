---
change: CHG-0009-address-pr-9-review-findings-by-covering-every-commit-in-multi-commit-push-trus
artifact: testing
---

# Testing

## Regression coverage

| Test | Expected result |
|---|---|
| Three commits between push before/after SHAs | Resolver emits a range whose count is three |
| Only one push boundary is supplied | Resolver fails; no local fallback |
| Push before SHA is forty zeroes | Resolver fails closed |
| Push before and after SHAs are identical | Resolver rejects the empty range |
| E2E file with a shadow `pty.rb` raising `LoadError` | Four non-PTY examples pass; five PTY examples skip |
| Normal E2E agent-mode matrix | All command/mode stdout remains whole-document JSON |

The targeted Fledge test run covers `trust_range_spec`, `e2e_spec`, and `e2e_portability_spec`.

## Complete gates

- `fledge lanes run verify`
- `fledge run smoke-test`
- strict SpecSync change verification and acceptance for CHG-0008 and CHG-0009
- `fledge trust verify` with a non-empty explicit range
