## MODIFIED

### SPEC SECTION Invariants


1. `TableParser.parse` converts header titles to lowercase underscored symbols.
2. `KeyValueParser.parse` coerces integer, float, and boolean values automatically.
3. `TextSanitizer.strip_ansi` returns an empty string for nil input.
4. `TableParser.parse` with `format: :auto` (default) detects pipe vs. space tables by checking whether the header line contains `|`; `format: :pipe`/`:space` bypass detection entirely.
5. `TableParser.parse` raises `ArgumentError` for an unrecognized `format:` value regardless of
   input size — validated unconditionally, not only once the input has 2+ non-empty lines.
6. `PromptDetector.detect?` strips ANSI codes before matching, and returns `false` (never raises)
   for `nil`, empty, or whitespace-only input.
7. `PromptDetector.detect?` recognizes explicit confirmations, labeled prompts, anchored
   interactive-wizard markers, arrow prompts, and recognizable shell prompts
   (`user@host:path$`, macOS-style `user@host cwd %`, optional `(venv)` prefixes, and named
   shells such as `bash-5.2#` / `zsh-5.9%`). Arbitrary prose questions and ordinary output
   ending in a bare `#`, `>`, `$`, or `%` are not sufficient evidence of a prompt. This
   intentionally favors rare false negatives over false positives that cause an agent to take an
   incorrect interactive branch.

8a. `ScreenRenderer` obeys every sequence that moves the cursor, including the single-byte escapes
   `ESC D`, `ESC E` and `ESC M`, cursor save and restore in both DECSC/DECRC and CSI forms, `VPA`,
   the insert/delete/erase-character family, and line insert, delete and scroll. An unrecognised
   escape is not merely ignored: its introducer is consumed and the byte after it lands as text, so
   `hello\eDworld` rendered as `helloDworld`. Private-parameter CSI forms are modes and are never
   treated as their public namesakes.
8b. The cursor on the last column follows xterm rather than wrapping immediately: it stays on that
   cell with a pending wrap, and the wrap happens when the next graphic character arrives. Any
   explicit move clears the pending wrap. Leaving the column one past the end put it in a state no
   terminal uses, which every relative move — backspace, `CUB`, line feed, `EL` — then read wrong.
8. `ScreenRenderer.render` obeys the escape sequences that decide where text lands — cursor
   motion, erasing, and line discipline — rather than deleting them as `TextSanitizer` does. This
   is the difference between every frame of a repaint and only the frame on screen: measured
   against grok, a 361KB transcript stripped to 36.9KB of escape-free text but rendered to 1.1KB,
   and an answer absent from the stripped text was present in the rendered screen.
9. `ScreenRenderer` erases inclusive of the cell under the cursor, in both directions, per ECMA-48.
   Excluding it left one character of a repainted line surviving that a real terminal would have
   cleared.
10. `ScreenRenderer.render` never fails to consume input. Its scanner advances on every iteration,
   including for bytes it does not act on, because a scan loop that can match without consuming is
   a hang rather than a wrong answer.
11. `ScreenRenderer.render` returns an empty string for nil or empty input, tolerates invalid
    UTF-8, and bounds work by rendering only the tail of a long transcript.
11a. A `ScreenRenderer` **instance** renders the same screen however the stream is chunked, for any
    sequence that fits within `MAX_CARRY_BYTES`. The grid was always retained across `render` calls
    but the parser was not: a `StringScanner` built fresh per call could not see that the previous
    chunk ended mid-sequence, so the remainder failed to match CSI, fell through to `PRINTABLE` and
    was written onto the grid as literal text. Feeding a stream one byte at a time put every escape
    byte of it on screen. An unterminated sequence is therefore held for the next chunk, as a real
    terminal holds it in its parser.

    **The ceiling is a real limit, not a formality, and it fails worse than a one-shot render
    rather than the same way.** Past it the carry is dropped and the sequence's payload is printed
    onto the grid; a one-shot render of the same bytes shows nothing, because it never has to hold
    anything across a boundary. Measured: a terminated `\e]52;c;<12KB base64>\a` split at 4096
    rendered 11 bytes one-shot and 1935 bytes of base64 retained. An earlier version of this
    invariant claimed the ceiling "degrades to what a one-shot render already did", which is false
    in both directions and is recorded here because it was published before it was checked.

    The ceiling is therefore set far above any producer's read size rather than equal to it. At
    4096 it was exactly `Session::Supervisor::READ_CHUNK`, so a sequence that did not complete
    inside one pty read could never be carried — an 8205-byte sequence survived 0 of 14 start
    offsets. At 64KB a sequence spanning sixteen reads completes, and a hostile stream that opens
    an OSC and never closes it still holds no more than the ceiling. It does not close the hole:
    OSC 52 clipboard payloads and iTerm2 `OSC 1337` inline images are unbounded, so no finite
    ceiling can. Discarding until the terminator instead of resetting to ground was rejected — it
    loses the case actually served today, where `tail` hands the renderer a window beginning inside
    a sequence whose terminator is off the front, and a discard state would swallow the rest of the
    screen rather than a few KB.

    This is the property a retained per-session `Screen` depends on, and it is worth ~10x per tick
    against re-rendering a growing prefix — measured 1034ms/tick against 100ms/tick over 20 frames
    of a 40x120 TUI repaint. That does not by itself make per-tick screen matching affordable:
    100ms/tick is still above `POLL_INTERVAL`, and `Screen#heal` running per glyph is the remaining
    cost. The instance path also assumes **decoded** input: it carries escape bytes only, so a
    multi-byte character split across chunks is scrubbed to replacement characters on both sides.
    Every producer already reads through `UTF8StreamDecoder`, which is what makes that safe.
11b. The ST terminator of an OSC or DCS is two bytes, and a buffer ending between them leaves a body
    that `[^\a\e]*` cannot cover. Such a sequence must still read as incomplete; before this it read
    as complete-but-unrecognised and its body was printed, so a transcript ending mid-ST rendered
    `]0;title` as visible text.
12. The rendering size is a caller's to supply and is resolved by `ScreenRenderer.dimensions`, which
    is also what a caller reports when it has to say which geometry a screen was rendered at. Absent
    or nonsensical dimensions become the defaults, and dimensions past `MAX_ROWS`/`MAX_COLUMNS` are
    clamped rather than allocated — the size now arrives from outside the process (a session records
    its child's winsize in a JSON file and reads it back), and the grid is allocated eagerly, so an
    unbounded value would be an allocation an untrusted file could ask for. This ceiling is a
    library backstop for a size that reached the renderer without passing through whatever recorded
    it; a caller that owns the size clamps it where it records it, and `session` clamps tighter.

13. The renderer honours the modes that decide what the grid *contains*, and only those. Every
    `?`-prefixed form used to be dropped whole, which is right for the ones that change a real
    terminal's hardware — cursor visibility, bracketed paste, mouse reporting — and wrong for two:

    - **The alternate screen buffer** (1049, and the older 1047/47). An agent CLI enters it at
      startup, so without it every byte printed before the switch stayed on the grid. Measured on a
      real shell entering and leaving a TUI: the old renderer showed `BEFORE_TUI / INSIDE_TUI /
      AFTER_TUI` and the new one shows `BEFORE_TUI / AFTER_TUI`, because content written in the
      alternate buffer is discarded with it. 1049 saves and restores the cursor and 1047/47 do not,
      which is the reason 1049 exists. Entering twice is idempotent rather than a second save — the
      alternative overwrites the primary buffer with the alternate one. A full reset returns to the
      primary buffer, so pre-reset output cannot reappear at the next exit.
    - **DECAWM** (7). With autowrap off the pending wrap is never taken: the cursor stays on the
      last cell and further graphics overwrite it, which is how a TUI paints a bottom-right corner
      without scrolling the screen out from under itself.

    The scroll region is deliberately not part of the buffer snapshot. DECSTBM margins belong to the
    terminal rather than to a buffer, so a region set inside the alternate buffer survives the
    switch back.

14. IRM (`CSI 4 h`) shifts the rest of the line right rather than overwriting, reusing ICH so
    the clamp at the right margin cannot diverge between the two. DECSTR returns it to reset.

15. `ESC ( 0` designates DEC Special Graphics, the `acsc` set every ncurses program draws boxes
    from, and SO/SI select G1/G0. Dropping the designation printed `qqq` where a border belonged.
    Only 0x5F-0x7E are remapped, so text between `ESC ( 0` and `ESC ( B` is not mangled, and any
    designation other than `0` returns the slot to ASCII rather than guessing at a national set.

16. `TextSanitizer` strips the two-byte escapes as well as the structured ones. Found by
    driving Claude Code through `rune session`: every read's `clean_output` opened with a literal
    `\e7\e8`, present uncapped as well as capped, so the stripper rather than the truncation.
    `ScreenRenderer` already acted on `[DEM78c]`, so the two parsers in this module disagreed about
    what an escape is and the sanitizer was the one that was wrong. Verified against a live Claude
    Code session: 2 escapes in `clean_output` before, 0 after.

17. **A cell holds one glyph and its combining marks, and a wide glyph occupies two columns.** A
    row is an `Array` of cells rather than a `String`, so a column index is an array index and a
    cell can hold any number of characters without moving the ones after it. `CONTINUATION` marks
    the right half of a wide glyph: it occupies a column for cursor arithmetic and contributes
    nothing to the rendered line.

    Insert, delete, erase and scroll all slice the row and any of them can separate a glyph from
    its continuation, so the invariant is restored by one `heal` pass after each mutation rather
    than taught to twelve operations independently. Healing blanks *both* halves when either is
    destroyed, which is what a terminal does — half a character is not something it can show.

    Zero-width characters attach to the cell before them, so a decomposed `é` is one column and a
    ZWJ emoji sequence keeps its joiner. Under the previous `String` rows this was impossible:
    appending a mark put every later index in that row off by one and the next graphic overwrote
    it.

    **This corrects an earlier version of this invariant, which claimed a cell model had been
    measured *worse* than the one-column gap and reverted.** That conclusion was wrong, and the
    error was mine rather than the measurement's: the A/B compared two working trees and
    misattributed which output came from which side. Re-measured against three explicit revisions
    on the same 56,928-byte grok capture that had emitted a CJK table:

        cc8bb3c  (one column)   "東h京   Tokyo"    "大 阪   Osaka"
        ad76e22  (one column)   "東h京   Tokyo"    "大 阪   Osaka"
        cell model             "東京  Tokyo"     "大阪  Osaka"

    The one-column model corrupts real agent output and always did — an agent positions its columns
    assuming two per CJK glyph, and a renderer that counts one puts every later write in the wrong
    place. The synthetic case is `\e[H東京\e[1;5HX`, which a terminal renders `東京X` and one column
    per glyph renders `東京  X`.

