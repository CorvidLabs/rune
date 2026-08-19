---
change: CHG-0075-repair-139-broken-relative-links-across-the-nine-translations
artifact: design
---

# Design

## The checker

Verification is a repo-wide markdown link scan that resolves three link classes:

- in-document anchors, by recomputing GitHub's heading slug
- relative file paths, resolved against the containing file's directory
- cross-file anchors, requiring both that the file exists and that it contains the anchor

Fenced code blocks are stripped before scanning so example links inside ``` are not checked.

The slug implementation keeps letters, marks, numbers, connector punctuation, hyphen and space,
downcases, trims, and replaces whitespace runs with hyphens. It was validated against two
known-working English anchors before being trusted against Arabic, Devanagari, CJK and Cyrillic
headings, because a slug function that is wrong about non-ASCII would silently report every
translated anchor as broken.

## Why policy, not re-rooting

Mechanically rewriting `](docs/X.md)` to `](../X.md)` would have produced 139 working links that
all dump a translated reader back into English halfway through a guide. Pointing at the translated
sibling keeps the reader in their language; the exception is `releasing.md`, where English is the
only correct target because no translation exists by design.

## Ordering

The path repair ran first and the per-language review second, deliberately. The review was then
able to catch the text/target mismatch that the repair itself introduced — a defect that did not
exist before the fix and would not have been visible to a scan run only beforehand.
