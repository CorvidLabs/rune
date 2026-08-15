---
change: CHG-0050-extract-the-transcript-out-of-sessioncommand-reconstruction-cursors-search-an
artifact: testing
---

# Testing

No new behaviour, so the test is that nothing changed: 387 examples pass, including the four rotation
tests that encode cursor semantics across a rotation and the four search tests.

Those disk tests are also the evidence the extraction was worth doing — they used to reach through
a command object for `read_transcript_file` and `slice_from` to ask a question about a file, and
now ask the file.
