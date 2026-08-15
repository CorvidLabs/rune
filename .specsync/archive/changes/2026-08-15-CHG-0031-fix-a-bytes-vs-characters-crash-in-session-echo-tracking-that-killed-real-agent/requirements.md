---
change: CHG-0031-fix-a-bytes-vs-characters-crash-in-session-echo-tracking-that-killed-real-agent
artifact: requirements
---

# Requirements

1. Echo tracking must not raise on multibyte output. `echo_still_arriving?` bounded its loop by
   byte length while indexing by character, so it asked for more characters than existed, got nil,
   and `start_with?(nil)` raised.
2. `beyond_echo` must strip exactly the echo. It advanced by the echo's byte length using
   character-based slicing, so a non-ASCII prompt ate the first characters of the reply.
3. A supervisor that dies for any reason must record why, and must not leave the session marked
   running.
4. The settle default must be set by measurement against a real agent CLI, not by taste.
5. A send issued while the child was still producing output must be visible to the caller.
