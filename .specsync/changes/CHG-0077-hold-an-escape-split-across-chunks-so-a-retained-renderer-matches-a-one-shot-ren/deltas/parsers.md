## MODIFIED

### SPEC SECTION Public API


| Name | Type | Description |
|------|------|-------------|
| `TableParser` | class | Class method `.parse(text, format: :auto)` converts space or pipe-delimited table text into array of hashes. `format:` accepts `:auto` (default heuristic), `:pipe`, or `:space` to force a parsing mode; raises `ArgumentError` for any other value. |
| `KeyValueParser` | class | Class method `.parse(text)` converts key-value text lines (`key: val`) into typed hashes. |
| `TextSanitizer` | class | Class method `.strip_ansi(text)` strips ANSI escape codes and normalizes line endings. |
| `ScreenRenderer` | class | Class method `.render(text, rows:, columns:, tail_bytes:)` replays a terminal byte stream onto a virtual screen and returns what a terminal would be showing. |
| `PromptDetector` | class | Class method `.detect?(line)` reports whether a single line of (possibly ANSI-colored) output looks like an interactive prompt awaiting input — used by `PTYRunner`/`PTYWatcher` to set `prompt_detected` in their results. |
| `Rune` | module | Top-level rune namespace. |
| `Parsers` | module | Namespace for terminal-output parsing helpers. |
| `parse` | class method | Parses the supplied text using the parser's documented format contract. |
| `parse_pipe_table` | internal method | Builds rows from pipe-delimited headers and cells. |
| `parse_space_table` | internal method | Builds rows from aligned whitespace-delimited columns. |
| `find_headers_and_spans` | internal method | Derives normalized headers and source-column spans. |
| `multi_space_spans` | internal method | Computes spans for headers separated by two or more spaces. |
| `single_space_spans` | internal method | Computes fallback spans from individual non-space tokens. |
| `set_span_ends` | internal method | Completes each detected column span using the following start offset. |
| `extract_values` | internal method | Selects split-based or span-based value extraction for a row. |
| `extract_by_spans` | internal method | Slices row values according to detected header positions. |
| `normalize_header` | internal method | Converts a header to a lowercase underscored symbol. |
| `build_row` | internal method | Zips normalized headers with values, filling missing cells with empty strings. |
| `strip_ansi` | class method | Removes supported ANSI sequences and normalizes CRLF/CR line endings. |
| `ANSI_REGEX` | constant | Escape-sequence pattern removed by `TextSanitizer`. |
| `render` | class method | Replays a byte stream onto a virtual screen and returns the visible text. |
| `Screen` | class | The grid and cursor a terminal maintains, separated from escape-sequence parsing. |
| `write` | instance method | Writes characters at the cursor, wrapping at the right margin. |
| `to_s` | instance method | Returns the visible screen, right-trimmed with trailing blank lines removed. |
| `insert_blanks` | instance method | ICH: shifts the rest of the line right, losing what falls off the edge. |
| `delete_characters` | instance method | DCH: shifts the rest of the line left over the deleted characters. |
| `erase_characters` | instance method | ECH: blanks characters in place without shifting. |
| `insert_lines` | instance method | IL: inserts blank lines at the cursor row, pushing the rest down. |
| `delete_lines` | instance method | DL: removes lines at the cursor row, pulling the rest up. |
| `scroll_up` | instance method | SU: scrolls the screen up, blanking the lines it exposes. |
| `scroll_down` | instance method | SD: scrolls the screen down, blanking the lines it exposes. |
| `DEFAULT_ROWS` | constant | Rows assumed when no size is given. |
| `DEFAULT_COLUMNS` | constant | Columns assumed when no size is given. |
| `MAX_ROWS` | constant | Ceiling on a caller-supplied row count, since the grid is allocated eagerly. |
| `MAX_COLUMNS` | constant | Ceiling on a caller-supplied column count, for the same reason. |
| `dimensions` | class method | The size a render will actually use, given what the caller asked for. |
| `CSI` | constant | The ECMA-48 CSI grammar: parameters, then intermediates, then a final byte. |
| `IGNORED` | constant | Escape forms consumed and dropped, because anything not consumed is printed. |
| `INCOMPLETE` | constant | A sequence the stream ended in the middle of, its terminator not yet arrived. |
| `full_reset` | instance method | RIS: clears the grid, homes the cursor and resets the scroll region. |
| `soft_reset` | instance method | DECSTR: resets region, saved cursor and origin without clearing the display. |
| `scroll_region` | instance method | DECSTBM: confines scrolling to a band of rows, and homes the cursor. |
| `private_modes` | instance method | Applies every mode in a `CSI ? Pm h/l` parameter list. |
| `private_mode` | instance method | One DEC private mode: the alternate buffer, DECAWM, or a cursor save. |
| `ansi_modes` | instance method | Applies every mode in a `CSI Pm h/l` parameter list; only IRM changes the grid. |
| `alternate_buffer` | instance method | Enters or leaves the alternate buffer for modes 1049, 1047 and 47. |
| `enter_alternate` | instance method | Switches to a cleared alternate buffer, optionally saving the cursor. |
| `leave_alternate` | instance method | Restores the primary buffer, optionally restoring the cursor. |
| `designate_charset` | instance method | Designates ASCII or DEC Special Graphics into a G0/G1 slot. |
| `shift_out` | instance method | SO: selects G1 for subsequent graphics. |
| `shift_in` | instance method | SI: selects G0 for subsequent graphics. |
| `ALTERNATE_MODES` | constant | The alternate-buffer modes, mapped to whether each one saves the cursor. |
| `GRAPHICS` | constant | DEC Special Graphics, the `acsc` set ncurses draws boxes with. |
| `CONTINUATION` | constant | Marks the right half of a wide glyph: a column for the cursor, nothing for the render. |
| `render_row` | internal method | Renders one row of cells to the text a terminal would show. |
| `render_cell` | internal method | One cell as displayed, including an orphan continuation holding its column. |
| `wide?` | internal predicate | Whether a cell holds a glyph two columns wide. |
| `heal` | internal method | Restores the wide-glyph invariant after an operation moved cells. |
| `write_char` | internal method | Places one graphic according to the columns it occupies. |
| `settle_wrap` | internal method | Takes a pending wrap, early if a wide glyph would split at the margin. |
| `place` | internal method | Writes a glyph and its continuation, then heals the row. |
| `combine` | internal method | Attaches a zero-width character to the cell before the cursor. |
| `CharacterWidth` | module | Columns a character occupies, from a curated UAX #11 subset. |
| `of` | module function | 0 for a combining mark, 2 for a wide glyph, 1 otherwise. |
| `ASCII_CEILING` | constant | Below this every character is a single-column graphic; the hot path. |
| `ZERO` | constant | Codepoint ranges that occupy no column. |
| `WIDE` | constant | Codepoint ranges that occupy two columns. |
| `translate` | internal method | Maps a graphic through the active charset, passing ASCII through unchanged. |
| `BYTE_CONTROLS` | constant | Control byte to the operation it performs, including SO/SI. |
| `MODE_FORM` | constant | `CSI Pm h/l`, with an optional private prefix, and nothing else. |
| `scroll_region_up` | instance method | Scrolls the region up, losing its top row. |
| `scroll_region_down` | instance method | Scrolls the region down, losing its bottom row. |
| `RESYNC_SCAN_BYTES` | constant | How far past the tail cut to look for an escape to resync on. |
| `DEFAULT_TAIL_BYTES` | constant | How much of a transcript tail is replayed, bounding work for a long session. |
| `MAX_CARRY_BYTES` | constant | Ceiling on an unterminated escape held for the next chunk, so an unclosed OSC cannot buffer without bound. |
| `TAB_WIDTH` | constant | Columns between tab stops. |
| `PRINTABLE` | constant | Pattern for bytes the renderer writes rather than interprets. |
| `CONTROLS` | constant | CSI final byte to the screen operation it performs. |
| `ESCAPES` | constant | Single-byte escapes that move the cursor, so cannot be discarded. |
| `detect?` | class method | Reports whether a cleaned line resembles a supported interactive prompt. |
| `PROMPT_PATTERNS` | constant | Positive prompt-detection patterns. |
| `FALSE_POSITIVES` | constant | Exclusions applied before positive prompt matching. |

| `carriage_return` | instance method | Returns the cursor to column zero without changing the row. |
| `backspace` | instance method | Moves the cursor one column left without deleting what follows. |
| `tab` | instance method | Advances to the next tab stop. |
| `newline` | instance method | Moves down a row, scrolling the region when already at its bottom. |
| `index` | instance method | ESC D: down one row, scrolling at the region bottom. |
| `next_line` | instance method | ESC E: down one row and back to column zero. |
| `reverse_index` | instance method | ESC M: up one row, scrolling the region down at its top. |
| `save_cursor` | instance method | Records the cursor position and pending-wrap state. |
| `restore_cursor` | instance method | Returns the cursor to the saved position and state. |
| `cursor_up` | instance method | CUU: up N rows, clamped to the screen. |
| `cursor_down` | instance method | CUD: down N rows, clamped to the screen. |
| `cursor_right` | instance method | CUF: right N columns, clamped to the line. |
| `cursor_left` | instance method | CUB: left N columns, clamped to column zero. |
| `cursor_next_line` | instance method | CNL: down N rows and to column zero. |
| `cursor_previous_line` | instance method | CPL: up N rows and to column zero. |
| `cursor_column` | instance method | CHA: to an absolute column on the current row. |
| `cursor_row` | instance method | VPA: to an absolute row, keeping the column. |
| `cursor_position` | instance method | CUP: to an absolute row and column. |
| `erase_display` | instance method | ED: erases the screen, inclusive of the cell under the cursor. |
| `erase_line` | instance method | EL: erases the line, inclusive of the cell under the cursor. |


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
11a. A `ScreenRenderer` **instance** renders the same screen however the stream is chunked. The grid
    was always retained across `render` calls but the parser was not: a `StringScanner` built fresh
    per call could not see that the previous chunk ended mid-sequence, so the remainder failed to
    match CSI, fell through to `PRINTABLE` and was written onto the grid as literal text. Feeding a
    stream one byte at a time put every escape byte of it on screen. An unterminated sequence is
    therefore held for the next chunk, as a real terminal holds it in its parser, bounded by
    `MAX_CARRY_BYTES` so an unclosed OSC cannot buffer without limit; past that ceiling the bytes
    are dropped, which is what a one-shot render already did with them. This is the property a
    retained per-session `Screen` depends on, and it is worth ~10x per tick against re-rendering a
    growing prefix — measured 1034ms/tick against 100ms/tick over 20 frames of a 40x120 TUI repaint.
    That does not by itself make per-tick screen matching affordable: 100ms/tick is still above
    `POLL_INTERVAL`, and `Screen#heal` running per glyph is the remaining cost.
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

