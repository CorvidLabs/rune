---
id: CHG-0075-repair-139-broken-relative-links-across-the-nine-translations
state: accepted
type: documentation
base_commit: ebaec04c478ab3eba17752fa69962f1e6add5049
---

# Repair 139 broken relative links across the nine translations

## Intent

Repair 139 broken relative links across the nine translations

## Affected Canonical Specs

- None

## Acceptance Criteria

- A repo-wide markdown link scan reports 0 broken local links across docs/i18n/ (296 links checked; the only remaining hits are literal link-syntax examples quoted in prose in an untracked report file). Links to documents that have a translation point at the translated sibling; links to code, spec and example paths point at the repo root via ../../; releasing.md continues to point at English because it is deliberately untranslated. Link text agrees with link target, as in the English sources. No translation index block claims the translation is authoritative. All 8 external URLs return 200 and all 9 translated READMEs retain their 3 badges.

## No-spec Rationale

Only translated documentation under docs/i18n/ changes. Relative paths copied verbatim from the repo-root English sources resolved two levels too shallow. No file under lib/ is touched and no canonical spec module gains or loses an obligation.
