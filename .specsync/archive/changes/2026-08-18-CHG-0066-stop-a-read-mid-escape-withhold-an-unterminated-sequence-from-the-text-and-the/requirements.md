---
change: CHG-0066-stop-a-read-mid-escape-withhold-an-unterminated-sequence-from-the-text-and-the
artifact: requirements
---

# Requirements

1. A read never delivers the bytes of an unterminated escape sequence.
2. Its cursor stops before them, so the next read sees the sequence whole.
3. `clean_output` and `screen` in one reply do not contradict each other.
4. `list` `last_line` agrees with both.
5. Nothing is lost: the withheld bytes are returned once the sequence completes.
