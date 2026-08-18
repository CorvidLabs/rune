---
change: CHG-0067-make-tail-count-a-carriage-return-as-a-line-break-and-report-matched-on-a-reg
artifact: testing
---

# Testing

After, on the same fixtures:

    run     --tail=2   truncated=true omitted_lines=3  clean 2 lines, raw 2 lines
    session --tail=2   truncated=true omitted_lines=5  clean 2 lines

Unit cases cover LF, CRLF, bare CR, an unterminated final line, a bound larger
than the input, and empty input — 6/6.

Each test falsified against deliberately unfixed code:

    mutation                          failures
    tail_lines reverted to LF-only    1 of 2 tail tests
    matched: false removed            the timeout expectation, exactly

568 examples, 0 failures; rubocop clean.

One existing expectation changed rather than being worked around: it pinned the
timeout outcome hash as `{settled: false, timed_out: true}` for a *regex* send,
which is the behaviour this corrects.
