---
change: CHG-0076-correct-the-max-canon-claims-an-unterminated-1024-byte-line-wedges-the-session
artifact: tasks
---

# Tasks

- [x] Measure the exact boundary with an out-of-band detector (child reports read sizes to a file)
- [x] Determine whether the terminator or the payload is the rejected byte at N=1024
- [x] Establish that the failure wedges the session rather than losing one line, with a post-recovery
      control ruling out delayed buffering
- [x] Reproduce outside rune with a bare `PTY.spawn` single `write()` to prove it is not rune
- [x] Isolate the discriminator by holding the child constant and flipping only `ICANON`
- [x] Measure `bash` and `python3` while busy, disproving the raw-mode exemption
- [x] Test recovery: `\x15`, `\x04`, `\x03`
- [x] Establish that BEL is not a usable detector in either direction
- [x] Re-verify the ROADMAP `python3 -q` claim by `len()` and sha256 rather than the echo
- [x] Correct `ROADMAP.md`, `docs/sessions.md`, `specs/session/session.spec.md`
- [x] Bump the session spec version and add the Change Log row
