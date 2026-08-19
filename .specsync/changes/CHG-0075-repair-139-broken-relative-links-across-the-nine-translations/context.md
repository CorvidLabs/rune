---
change: CHG-0075-repair-139-broken-relative-links-across-the-nine-translations
artifact: context
---

# Context

A user reported a single broken link in a translated document. A repo-wide markdown link scan
found 139.

## Why there were so many

Every translated document lives in `docs/i18n/`, two directories below the English source it was
translated from. The relative paths were carried over verbatim, so each resolved two levels too
shallow:

| pattern | count | resolved to |
|---|---|---|
| `](docs/X.md)` in all 9 `README.<lang>.md` | 54 | `docs/i18n/docs/X.md` |
| `](../X)` in all 9 `getting_started.<lang>.md` | 81 | `docs/X` instead of the repo root |
| `](i18n/X.pt-BR.md)` in 4 files | 4 | `docs/i18n/i18n/X.pt-BR.md` |

This is the same defect class as the License badge repaired earlier, which was fixed as a single
symptom rather than generalised. That is why it recurred here at scale, and it is the lesson worth
keeping: a path bug found in one file in `docs/i18n/` is a statement about the whole directory.

## Repair policy

Rather than mechanically re-rooting every path, links follow the reader:

- a link to a document that **has** a translation points at the translated sibling, so a reader who
  opened the Japanese page stays in Japanese
- a link to code, specs or examples points at the repo root via `../../`
- `releasing.md` is deliberately untranslated (internal maintainer doc), so it points at English

## Three defects a path scan cannot see

Found by independent per-language review run after the path repair:

1. **The path repair introduced a text/target mismatch.** In English, `[docs/sessions.md](docs/sessions.md)`
   has text equal to target. Retargeting to `sessions.<lang>.md` left the visible text reading
   `docs/sessions.md` — a working link with a lying label, in all 9 files. Link text now agrees
   with the target again, as in English.

2. **`README.ru.md` had a CommonMark rendering bug**, unique to Russian: `---` sat directly under a
   paragraph with no blank line. That is a setext heading underline, not a horizontal rule, so the
   paragraph rendered as an `<h2>` and the section rule vanished.

3. **Four stale one-language translation index blocks** (`pty_architecture.{ar,es,zh-CN}.md`,
   `sessions.fr.md`) listed 1 of 9 languages and sent readers to the Portuguese document. Each was
   followed by a sentence asserting *the translation itself* was authoritative, contradicting line 1
   of the same file, which correctly defers to English. The path repair had turned these into
   working links to the wrong place. Removed, matching the 32 clean siblings.

## Deliberately not done

**34 of 36 translated files carry no language index at all.** Only the four English sources have
the 9-language block, so a reader on a translated page cannot reach a sibling language. Two
independent reviewers flagged it. It is a convention decision across 36 files, not a broken link.

Untranslated link *text* remains in `README.hi.md` (7 labels) and `README.ru.md` (4), where every
target is correct. That is translation completeness, not link breakage.
