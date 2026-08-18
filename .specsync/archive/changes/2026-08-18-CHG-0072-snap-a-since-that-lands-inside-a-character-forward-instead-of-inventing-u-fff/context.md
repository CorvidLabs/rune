---
change: CHG-0072-snap-a-since-that-lands-inside-a-character-forward-instead-of-inventing-u-fff
artifact: context
---

# Context

Found by the native-language i18n dogfood (`RUNE_NATIVE_I18N.md` §5.3) and independently by
the doc-i18n pass (`RUNE_DOC_I18N_FULL.md` §4.3): five of six in-language agents reported
`--since` landing mid-character and coming back with U+FFFD under `status: ok`.

Reproduced on this tree against `ruby -Ilib bin/rune`, on a `cat` session whose payload is
`こY` (bytes `E3 81 93 59`):

    --since=0  fffd=0  head="こY…"
    --since=1  fffd=2  head="<FFFD><FFFD>Y…"
    --since=2  fffd=1  head="<FFFD>Y…"
    --since=3  fffd=0  head="Y…"

`--since=1` returned *more* bytes than `--since=0`, because two orphaned continuation bytes
became two 3-byte replacement characters. A consumer cannot tell rune's slicing from a
U+FFFD the child actually emitted.

Cursors rune itself issues never land here — `UTF8StreamDecoder` holds a trailing incomplete
sequence, verified independently at 0/84 mid-character cursors. This only bites a caller
doing arithmetic on a documented byte offset (`--since=$((cursor-200))`), which is safe on
ASCII and unsafe on roughly half the offsets of a 3-byte script.

The existing suite test only asserted `be_valid_encoding`. `.scrub` produces valid UTF-8,
so that test stayed green through the defect.

Snap forward, not back: including the split character would return bytes *before* the
cursor the caller asked for. The split character is not available from this offset.
`.scrub` stays as a safety net for genuinely invalid bytes after the snap point.
