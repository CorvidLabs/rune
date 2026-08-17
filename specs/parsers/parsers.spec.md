---
module: parsers
version: 11
status: active
files:
  - lib/rune/parsers/table_parser.rb
  - lib/rune/parsers/key_value_parser.rb
  - lib/rune/parsers/text_sanitizer.rb
  - lib/rune/parsers/prompt_detector.rb
  - lib/rune/parsers/screen_renderer.rb
  - lib/rune/parsers/screen.rb
---
# Parsers

## Purpose
Text parsing utilities for `rune`. Converts unstructured terminal text, tables, ANSI codes, and key-value lines into clean, structured Ruby hashes and arrays.

## Public API

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
| `scroll_region_up` | instance method | Scrolls the region up, losing its top row. |
| `scroll_region_down` | instance method | Scrolls the region down, losing its bottom row. |
| `RESYNC_SCAN_BYTES` | constant | How far past the tail cut to look for an escape to resync on. |
| `DEFAULT_TAIL_BYTES` | constant | How much of a transcript tail is replayed, bounding work for a long session. |
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

## Invariants

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
12. The rendering size is a caller's to supply and is resolved by `ScreenRenderer.dimensions`, which
    is also what a caller reports when it has to say which geometry a screen was rendered at. Absent
    or nonsensical dimensions become the defaults, and dimensions past `MAX_ROWS`/`MAX_COLUMNS` are
    clamped rather than allocated — the size now arrives from outside the process (a session records
    its child's winsize in a JSON file and reads it back), and the grid is allocated eagerly, so an
    unbounded value would be an allocation an untrusted file could ask for. This ceiling is a
    library backstop for a size that reached the renderer without passing through whatever recorded
    it; a caller that owns the size clamps it where it records it, and `session` clamps tighter.

## Behavioral Examples

- `TableParser.parse("NAME STATUS\nrune active")` returns `[{ name: 'rune', status: 'active' }]`.
- `TableParser.parse("Name | Status\nrune | active", format: :pipe)` forces pipe parsing even without a `|`-only header separator row.
- `KeyValueParser.parse("threads: 4")` returns `{ threads: 4 }`.
- `PromptDetector.detect?('Continue? (y/n) ')` returns `true`; `PromptDetector.detect?('Downloading
  100%')` and `PromptDetector.detect?('Install with: fledge plugins install <owner/repo>')` both
  return `false` despite ending in characters (`%`, `>`) the underlying prompt patterns otherwise
  match on.
- `PromptDetector.detect?('user@host:~$ ')`, `PromptDetector.detect?('leif@MacBook-Pro rune % ')`,
  `PromptDetector.detect?('(venv) user@host:~$ ')`, and `PromptDetector.detect?('zsh-5.9%')` all
  return `true`, while `PromptDetector.detect?('TODO: fix #')`, `PromptDetector.detect?('##')`,
  `PromptDetector.detect?('Building... 45%')`, and `PromptDetector.detect?('Is it ok? Yes')`
  return `false`.

## Error Cases
| Condition | Behavior |
|-----------|----------|
| Empty input | Returns empty array or empty hash |
| `TableParser.parse` with an unknown `format:` value | Raises `ArgumentError` |

## Known Limitations

- **Space-delimited heuristic is column-alignment dependent.** `TableParser`'s `:space` mode splits on runs of 2+ spaces (falling back to single-space token spans only when the header has one word). Cell values that don't align to the header's column boundaries, or that contain internal runs of 2+ spaces, can be misattributed to the wrong column. When source output is unreliable or known in advance, pass an explicit `format:` rather than relying on `:auto`.
- **`ScreenRenderer` is not a terminal emulator.** It implements what moves the cursor and what
  erases; it does not model scroll regions, alternate-screen buffers as separate grids, tab-stop
  changes, character sets, or double-width characters. A child that relies on those will render
  approximately. Colours and modes are consumed and discarded by design — they cannot move the
  cursor, so they cannot change which text is on screen.
- **A rendered screen shows the end state, not the history.** Anything the child scrolled or
  repainted away is gone, which is the point, but it means the screen is not a substitute for the
  transcript when the question is "what happened" rather than "what is displayed".
- **`:auto` detection is a single check.** It only inspects whether the header line contains `|` — free-text tables whose header happens to contain a literal pipe character will be misdetected as pipe tables unless `format: :space` is passed explicitly.

## Dependencies
- Ruby stdlib only

## Change Log

- v1: Active parsers spec contract
- v1: Added `PromptDetector` to this module's file/API coverage (previously untracked by
  spec-sync despite being public since `PTYRunner#detect_prompt?` shipped); documented the
  `<placeholder>` false-positive fix and the pre-existing digit-percent one. Also documented that
  `TableParser.parse` now validates `format:` unconditionally, not only for 2+-line input.
| 2026-07-29 | CHG-0016-fix-prompt-false-positives-and-command-registration-leaks-close-test-gaps-and: Fix prompt false positives and command registration leaks, close test gaps, and make dependency and stdout contracts reproducible |
| 2026-07-30 | Follow-up on the CHG-0016 prompt narrowing: cover macOS zsh `user@host cwd %`, `(venv)` prefixes, and versioned shells like `zsh-5.9%` without reintroducing bare-punctuation false positives |
| 2026-08-14 | CHG-0028-add-persistent-named-agent-sessions-rune-session-start-send-read-list-stop-bac: Broaden `TextSanitizer::ANSI_REGEX` beyond SGR-shaped CSI to also strip private-parameter CSI (`[?1049h`, `[?2026h`), OSC strings (`]0;title`), DCS/SOS/PM/APC strings, and keypad/cursor-key modes. The old pattern left a full-screen TUI's escape traffic almost entirely intact, so `clean_output` was unreadable for exactly the agent CLIs `rune session` drives. No public API change. |
| 2026-08-14 | CHG-0028-add-persistent-named-agent-sessions-rune-session-start-send-read-list-stop-bac: Add persistent named agent sessions: rune session start/send/read/list/stop, backed by a per-session detached supervisor holding the PTY, with send-and-settle so one agent CLI can drive another synchronously |
| 2026-08-15 | CHG-0033-render-the-terminal-screen-for-session-send-and-read-so-an-agent-driving-a-full: Render the terminal screen for session send and read, so an agent driving a full-screen agent can find the answer instead of searching every repaint frame |
| 2026-08-15 | CHG-0037-fix-two-defects-found-by-having-grok-and-claude-review-this-branch-through-rune: Fix two defects found by having grok and claude review this branch through rune itself: erase-line excluded the cursor cell, and backpressure defeated the terminator delay |
| 2026-08-15 | CHG-0039-fix-six-defects-found-by-a-read-only-grok-kimi-and-agy-council-review-of-0-5-0: Fix six defects found by a read-only grok, kimi and agy council review of 0.5.0: renderer escapes and last-column cursor, a send accepted mid-delivery, a send settled before submission, stop killing before teardown, a false exit code, and a skipped process-group kill |
| 2026-08-16 | CHG-0052-the-screen-tail-can-cut-an-escape-sequence-in-half-and-print-its-remainder-onto: The screen tail can cut an escape sequence in half and print its remainder onto the screen |
| 2026-08-16 | CHG-0054-four-agent-pre-1-0-review-nine-bugs-fixed-and-fifteen-documentation-claims-tha: Four-agent pre-1.0 review: nine bugs fixed, and fifteen documentation claims that were wrong |
| 2026-08-16 | CHG-0056-second-review-round-the-regex-echo-bug-fixed-four-renderer-defects-fixed-and: Second review round: the regex echo bug fixed, four renderer defects fixed, and one rule disproved |
| 2026-08-17 | CHG-0058-integrate-the-post-0-8-0-fixes-two-quadratics-exec-fidelity-geometry-cursors: Integrate the post-0.8.0 fixes: two quadratics, exec fidelity, geometry, cursors, and the guide gate |
