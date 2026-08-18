---
id: CHG-0066-stop-a-read-mid-escape-withhold-an-unterminated-sequence-from-the-text-and-the
state: accepted
type: feature
base_commit: 4abd95c8461be099fc5030a740ea456ec7d242d1
---

# Stop a read mid-escape: withhold an unterminated sequence from the text and the cursor

## Intent

Stop a read mid-escape: withhold an unterminated sequence from the text and the cursor

## Affected Canonical Specs

- `session`
- `pty_runner`

## Acceptance Criteria

- A read stops at the last complete escape sequence and its cursor stops there too, so a sequence split across two pty reads is never delivered as visible text and never left headless for the next read. list's last_line is summarised from the reassembled tail rather than one event. Verified on the exact reported reproduction: clean_output, screen and last_line all agree the child printed RED, where previously clean_output said 1mRED and screen said RED in the same reply. Three regression tests, each falsified against deliberately unfixed code.

## No-spec Rationale

Not applicable
