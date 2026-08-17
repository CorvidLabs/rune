---
change: CHG-0057-make-transcript-cursors-survive-a-mid-stream-gap-record-where-each-dropped-regi
artifact: testing
---

# Testing

`bundle exec rspec` — 488 examples, 0 failures. `fledge run lint` — clean.
`ruby harnesses/transcript_gaps.rb` — PASS (exits non-zero on any disagreement with the oracle).

Each new example was verified against its own fix reverted, which is the only thing that proves it
can fail:

| revert | examples that fail |
|---|---|
| `retained_offset` back to `since - dropped` | 4 of 7 mapping examples (the 3 that survive are the "unchanged behaviour" guards, which must pass both ways) |
| supervisor gap machinery back to the old `log_event` | 6 of 8 durability examples |
| `truncated` not counted in `output_bytes_from` | 2 (mid-stream hole counted twice: cursor 327_000 against 315_000) |
| whole-record guard removed | 1 (-3000 bytes per torn fragment, at four of eight tear points) |
| last-line parse branch removed from `whole_record?` | 1 (10 disagreements in 1760 swept cases) |
