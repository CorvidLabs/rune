---
change: CHG-0001-adopt-and-enforce-specsync-5-for-release-delivery
artifact: design
---

# Design

Three layers form the enforced gate:

1. Canonical contract validation runs strict export, dependency, required-section, and 100% source
   coverage checks.
2. Git staleness validation uses an inclusive one-commit threshold, requiring every mapped source
   change to be accompanied by a canonical spec update.
3. SpecSync 5 SDD policy requires meaningful delivery paths to be covered by a digest-approved
   active change with native verification evidence and closing approval.

Lifecycle history is enabled, only `active` and `stable` canonical specs are allowed in release CI,
and the GitHub Action runs lifecycle enforcement. The SDD policy treats Ruby library code, workflow
configuration, Fledge configuration, release scripts, and SpecSync policy/configuration as
meaningful delivery inputs.

The CLI semantic delta adds version synchronization as an invariant and replaces the stale literal
version example with a version-independent contract. Acceptance applies that delta atomically and
bumps the canonical spec version.
