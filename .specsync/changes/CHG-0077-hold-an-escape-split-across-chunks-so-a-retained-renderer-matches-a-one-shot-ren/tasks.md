---
change: CHG-0077-hold-an-escape-split-across-chunks-so-a-retained-renderer-matches-a-one-shot-ren
artifact: tasks
---

# Tasks

- [x] Reproduce the divergence between a retained instance and a one-shot render
- [x] Hold an unterminated sequence for the next chunk, restoring the consumed `ESC`
- [x] Bound the carry with `MAX_CARRY_BYTES` so an unclosed OSC cannot buffer without limit
- [x] Handle a chunk ending on a bare `ESC`
- [x] Extend `INCOMPLETE` to cover an ST terminator split across chunks (pre-existing defect)
- [x] Validate across 2571 split configurations over ten escape families
- [x] Verify both arms of the fix against deliberately reverted code
- [x] Measure retained against growing-prefix rendering cost
- [x] Document the new constant and the two invariants in the parsers spec
