---
change: CHG-0014-clarify-mixed-help-aliases-and-invocation-local-cli-modes-in-the-exact-cli-contr
artifact: testing
---

# Testing

- Confirm invariant 15 explicitly covers help, JSON, and NDJSON leakage.
- Confirm the error-case table covers mixed and repeated help aliases.
- Run the configured verification lane.
- Run `fledge spec check --strict` and `fledge trust verify`.
