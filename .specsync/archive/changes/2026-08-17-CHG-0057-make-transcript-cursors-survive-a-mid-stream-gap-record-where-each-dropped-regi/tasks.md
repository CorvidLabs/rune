---
change: CHG-0057-make-transcript-cursors-survive-a-mid-stream-gap-record-where-each-dropped-regi
artifact: tasks
---

# Tasks

- [x] `lib/rune/session/supervisor.rb`: carry a failed write as a gap and record it when writing
      resumes; report `transcript_gap_bytes` while it is still owed; back off a failed rotation.
- [x] `lib/rune/session/store.rb`: count `truncated` in the kept region, skip a torn fragment,
      `whole_record?`/`parseable?`.
- [x] `lib/rune/session/transcript.rb`: `record_gap`, `gaps`, `retained_offset`, gap-aware `from`.
- [x] `harnesses/transcript_gaps.rb`: oracle-checked before/after table.
- [x] `spec/rune/session_spec.rb`: 15 examples, each verified against its own fix reverted.
- [x] `specs/session/session.spec.md`: Public API entries and invariants 41w–41z.
- [x] `docs/sessions.md`: what `dropped_bytes` now covers, and `transcript_gap_bytes`.
