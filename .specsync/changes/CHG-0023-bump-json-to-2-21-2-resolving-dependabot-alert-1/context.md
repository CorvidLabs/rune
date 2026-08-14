---
change: CHG-0023-bump-json-to-2-21-2-resolving-dependabot-alert-1
artifact: context
---

# Context

Dependabot alert #1: `json` <= 2.21.1 has a freed-buffer dereference in
`JSON::ResumableParser#partial_value` on truncated duplicate-key streams. `json` is a transitive
dev dependency (`rubocop (~> 2.3)`), not part of rune's runtime surface (rune itself is
stdlib-only). 2.21.2 is the first patched version.
