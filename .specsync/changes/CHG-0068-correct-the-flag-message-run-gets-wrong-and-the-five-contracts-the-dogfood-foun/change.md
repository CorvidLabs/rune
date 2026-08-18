---
id: CHG-0068-correct-the-flag-message-run-gets-wrong-and-the-five-contracts-the-dogfood-foun
state: accepted
type: feature
base_commit: 023f4078ec28548d58aaa35bfd985e5a843781e9
---

# Correct the flag message run gets wrong, and the five contracts the dogfood found documented wrong

## Intent

Correct the flag message run gets wrong, and the five contracts the dogfood found documented wrong

## Affected Canonical Specs

- `pty_runner`
- `session`

## Acceptance Criteria

- A flag rune run owns, spelled correctly but given a space-separated value, gets a message naming the real problem instead of Unknown option plus a remedy that hands the flag to the child. The known-flag set is derived from the parser so it cannot drift. Four further findings are confirmed as documentation defects and corrected where each is stated: the two run output fields describe different windows under max-output, omitted_bytes reconciles only on ASCII, grep matches the cleaned transcript rather than the rendered screen, and screen is bounded by geometry rather than by the read filters. Every code path keeps its current behaviour except the one message.

## No-spec Rationale

Not applicable
