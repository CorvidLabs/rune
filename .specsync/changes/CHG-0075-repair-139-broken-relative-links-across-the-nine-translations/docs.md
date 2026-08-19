---
change: CHG-0075-repair-139-broken-relative-links-across-the-nine-translations
artifact: docs
---

# Docs

This change is entirely documentation: 22 files under `docs/i18n/`. No user-facing behaviour, CLI
surface or module contract changes, and nothing under `lib/` is touched.

## Measured outcome

- **Before:** 139 broken local links.
- **After:** 0 broken across 296 links (22 in-document anchors, 193 relative paths, 81 external).

Two scan hits remain and are false positives: literal link-syntax examples quoted in prose
(`[Português (BR)](...)` and `](#...)`) inside an untracked root-level report file.

External URLs were fetched: all 8 return 200, including the shields.io ruby badge whose `&`
required separate handling from a naive read loop. All 9 translated READMEs retain their 3 badges.

## Left open deliberately

- 34 of 36 translated files carry no language index; only the English sources have the 9-language
  block. A reader on a translated page cannot reach a sibling language. Convention decision.
- Untranslated link text in `README.hi.md` (7 labels) and `README.ru.md` (4). Targets are correct.
