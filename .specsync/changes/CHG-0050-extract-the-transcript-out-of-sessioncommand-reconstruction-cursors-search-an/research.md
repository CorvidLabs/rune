---
change: CHG-0050-extract-the-transcript-out-of-sessioncommand-reconstruction-cursors-search-an
artifact: research
---

# Research

| file | before | after |
|------|--------|-------|
| `lib/rune/commands/session_command.rb` | 930 | 853 |
| `lib/rune/session/transcript.rb` | — | 86 |

The disk-accounting tests previously reached into the command for
`read_transcript_file` and `slice_from`; they now construct a `Transcript` directly, which is
the point of the extraction — they no longer need a command object to ask a question about a log.
