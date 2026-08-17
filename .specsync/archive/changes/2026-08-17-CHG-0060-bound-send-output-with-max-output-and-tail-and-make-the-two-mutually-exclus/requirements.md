---
change: CHG-0060-bound-send-output-with-max-output-and-tail-and-make-the-two-mutually-exclus
artifact: requirements
---

# Requirements

1. `send` honours `--max-output` and `--tail`.
2. `clean_output` is derived from the bounded raw text, so it and `output`
   describe the same window and one `omitted_bytes` is true of both.
3. `--max-output` with `--tail` is refused on every session subcommand, with the
   message `rune run` already uses.
4. No change to the transcript, the cursor, or what attached clients see — the
   bound is one caller's view of one reply.
