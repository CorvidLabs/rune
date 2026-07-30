---
change: CHG-0013-finalize-commit-anchored-exact-cli-spec-coverage-for-the-accepted-help-stack
artifact: testing
---

# Testing

- Confirm the base commit is `bf384e40f45bbf7e8eb1c3d3f09b00af137b91d3`.
- Confirm `specs/cli/cli.spec.md` is unchanged by CHG-0013.
- Run the configured verification lane.
- Run `fledge spec check --strict` and `fledge trust verify`.
