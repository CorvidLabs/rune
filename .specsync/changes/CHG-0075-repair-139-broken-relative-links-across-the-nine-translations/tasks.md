---
change: CHG-0075-repair-139-broken-relative-links-across-the-nine-translations
artifact: tasks
---

# Tasks

- [x] Build a link checker resolving anchors via GitHub's slug algorithm, skipping code fences
- [x] Validate the slug function against known-working English anchors before trusting non-ASCII
- [x] Repair 54 root-relative `docs/X.md` links across the 9 translated READMEs
- [x] Repair 81 `../X` links across the 9 translated getting-started guides
- [x] Repair 4 stray `i18n/` path prefixes
- [x] Review each language independently for defects a path scan cannot see
- [x] Repair the text/target mismatch the retargeting introduced in all 9 READMEs
- [x] Insert the missing blank line before `---` in `README.ru.md` (setext heading defect)
- [x] Remove 4 stale one-language index blocks and their contradictory authority lines
- [x] Confirm 0 broken links across 296, 8/8 external URLs at 200, 3 badges per translated README
