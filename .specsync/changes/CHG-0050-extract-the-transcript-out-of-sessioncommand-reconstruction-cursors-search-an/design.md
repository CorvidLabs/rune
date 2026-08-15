---
change: CHG-0050-extract-the-transcript-out-of-sessioncommand-reconstruction-cursors-search-an
artifact: design
---

# Design

`Session::Transcript` loads a log into retained text plus the count rotation dropped, and answers
the four questions asked of it: `cursor` (total produced, including what was discarded), `from`
(everything after an absolute cursor), `screen`, and `grep`.

Keeping `dropped` on the object rather than threading it through every call is what makes the
cursor arithmetic hard to get wrong — before, four separate methods each took a `dropped` argument
and each had to remember what it meant.

The command keeps option parsing, result assembly and everything that is genuinely about being a
CLI. `filter` stays there because `--grep` is an option; the searching itself moved.
