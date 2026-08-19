---
change: CHG-0074-correct-the-wait-for-regex-reprint-advice-qualify-reprint-not-visible-histor
artifact: context
---

# Context

Internal review of CHG-0073, before merge. Two pieces of caller-facing advice were stronger
than the mechanism:

- "Visible history" is not what `send` scans. It matches bytes after the send-time cursor.
  `'\$ $'` is still the right bash pattern even when a prompt is already on screen. The
  defect is a *reprint* of earlier output as new bytes.
- `child_busy` does not wait through the measured child (reprint, 3s silence, then `DONE N`).
  It is a `read` field meaning "still printing". After the reprint, idle crosses 800ms and
  `child_busy` is false while `DONE 2` has not been printed.

Also drops the duplicate CHG-0073 changelog row and the 36→38 version skip.
