---
module: parsers
version: 1
status: active
files:
  - lib/rune/parsers/table_parser.rb
  - lib/rune/parsers/key_value_parser.rb
  - lib/rune/parsers/text_sanitizer.rb
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

## Invariants
1. `TableParser.parse` converts header titles to lowercase underscored symbols.
2. `KeyValueParser.parse` coerces integer, float, and boolean values automatically.
3. `TextSanitizer.strip_ansi` returns an empty string for nil input.
4. `TableParser.parse` with `format: :auto` (default) detects pipe vs. space tables by checking whether the header line contains `|`; `format: :pipe`/`:space` bypass detection entirely.

## Behavioral Examples
- `TableParser.parse("NAME STATUS\nrune active")` returns `[{ name: 'rune', status: 'active' }]`.
- `TableParser.parse("Name | Status\nrune | active", format: :pipe)` forces pipe parsing even without a `|`-only header separator row.
- `KeyValueParser.parse("threads: 4")` returns `{ threads: 4 }`.

## Error Cases
| Condition | Behavior |
|-----------|----------|
| Empty input | Returns empty array or empty hash |
| `TableParser.parse` with an unknown `format:` value | Raises `ArgumentError` |

## Known Limitations
- **Space-delimited heuristic is column-alignment dependent.** `TableParser`'s `:space` mode splits on runs of 2+ spaces (falling back to single-space token spans only when the header has one word). Cell values that don't align to the header's column boundaries, or that contain internal runs of 2+ spaces, can be misattributed to the wrong column. When source output is unreliable or known in advance, pass an explicit `format:` rather than relying on `:auto`.
- **`:auto` detection is a single check.** It only inspects whether the header line contains `|` — free-text tables whose header happens to contain a literal pipe character will be misdetected as pipe tables unless `format: :space` is passed explicitly.

## Dependencies
- Ruby stdlib only

## Change Log
- v1: Active parsers spec contract
