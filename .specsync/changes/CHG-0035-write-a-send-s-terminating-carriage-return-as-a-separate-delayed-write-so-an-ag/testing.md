---
change: CHG-0035-write-a-send-s-terminating-carriage-return-as-a-separate-delayed-write-so-an-ag
artifact: testing
---

# Testing

The regression test drives a child that switches its tty to raw mode and reports the shape of every
read — length and how many carriage returns — rather than echoing bytes, since echoing a carriage
return would move the cursor and corrupt the transcript being asserted on.

It waits for the child to signal raw mode before sending. Without that wait the test measures the
line discipline instead: cooked mode holds the text until a terminator arrives and delivers both as
one read, which looks exactly like the bug. Real callers race the same way, which is why the docs
say to wait for the callee to be listening.

Verified both ways: fails against the unfixed supervisor, passes against the fix.

340 examples, 0 failures; lint clean.
