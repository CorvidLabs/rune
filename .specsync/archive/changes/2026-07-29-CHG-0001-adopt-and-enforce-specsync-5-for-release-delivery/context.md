---
change: CHG-0001-adopt-and-enforce-specsync-5-for-release-delivery
artifact: context
---

# Context

Rune currently maps every library file to a canonical module spec and runs SpecSync in strict,
100%-coverage mode. That gate does not enable git staleness detection, so a mapped source file can
change without its spec changing. The 0.2.1 release-prep commit demonstrated the gap:
`lib/rune/version.rb` changed while `specs/cli/cli.spec.md` remained one commit behind, yet CI passed.

The repository also has no SpecSync 5 SDD policy, disables lifecycle history, and does not run
lifecycle enforcement in CI. This change adopts those layers and makes release delivery subject to
the same deterministic contract and evidence requirements as runtime changes.
