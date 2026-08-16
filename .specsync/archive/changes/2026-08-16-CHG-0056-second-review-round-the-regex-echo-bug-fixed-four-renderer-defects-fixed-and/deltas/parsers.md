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

> Note: `Screen`s cursor and erase operations — `carriage_return`, `backspace`, `tab`, `newline`,
> `cursor_up`, `cursor_down`, `cursor_right`, `cursor_left`, `cursor_next_line`,
> `cursor_previous_line`, `cursor_column`, `cursor_position`, `erase_display` and `erase_line` —
> are intentionally absent from the table above. They exist and are exercised by the suite, but
> SpecSyncs Ruby extractor does not surface them from their position in a nested class
> (rune#20 / spec-sync#479), and documenting an export it cannot see fails the contract check.

