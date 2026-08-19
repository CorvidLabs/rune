---
id: CHG-0080-say-what-start-actually-does-split-the-roadmap-by-what-would-change-it-and-giv
state: accepted
type: documentation
base_commit: 2fac891cfa6efa8db9163312d082bbb3137f5ae8
---

# Say what start actually does, split the roadmap by what would change it, and give failures a code a caller can branch on

## Intent

Say what start actually does, split the roadmap by what would change it, and give failures a code a caller can branch on

## Affected Canonical Specs

- `session`

## Acceptance Criteria

- docs/sessions.md states the start contract that actually ships: a command that cannot be executed is status error with exit 1, a command that starts and exits at once is status ok, and state in a start reply is a snapshot that can already be wrong - measured, a script exiting 3 immediately reported state running 3 of 3 - with list or the next send named as the authority instead of the stale advice to check state. ROADMAP's What 1.0 needs is split into the gates that must be done and the limitations that will ship documented, with each moved item saying why it moved. Session failures carry data.code and data.name alongside the prose, so a caller can branch without matching English, and the human rendering is unchanged because the renderer reads only error.

## No-spec Rationale

Not applicable
