---
change: CHG-0058-integrate-the-post-0-8-0-fixes-two-quadratics-exec-fidelity-geometry-cursors
artifact: testing
---

# Testing

519 examples, from 454 at the branch point. Every regression test added here was verified to fail
against its own fix reverted.

Two testing lessons are worth more than the count. A regression test written for a reported leak
passed against deliberately broken code and was deleted rather than kept — a test that cannot fail is
worse than none. And twice a false "cannot reproduce" came from a fixture more specific than the
thing it tested: literal spaces where the mechanism was cursor positioning, and text immediately
after a position where each token was wrapped in SGR. Both bugs were real.
