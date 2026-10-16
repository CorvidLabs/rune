---
change: add-isolated-rune-session-fault-and-recovery-verification
artifact: context
---

# Context

Leif authorized focused local project audits, tests and reviewable PRs. This
candidate adds isolated failure/recovery verification for existing session
behavior. It changes no library or executable source. The primary checkout's
unpublished contract work and all unrelated/default-home sessions are preserved.

Initial review found a missing-identity signal guard and insufficient synthetic
controls. Subsequent review found copied-checkout and cleanup defects. The
current harness fails closed on missing/mismatched identity, stages coherent
disposable lib/bin copies, and preserves unresolved fixtures. Independent reviews
and real execution receipts are retained in the coordinator R1 report.

This is an unapproved draft definition prepared by agents, not a human scope
approval, acceptance or lifecycle review. Existing change records and Trust's
deliberately disabled provenance configuration remain untouched.

Hosted CodeQL identified the deliberately exponential regex introduced by the
new harness. The duplicate scenario is removed; the two existing timeout and
recovery regressions retain this responsibility unchanged. No security finding
is dismissed and no protection policy is edited. The draft remains unapproved.
