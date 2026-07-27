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
| `TableParser` | class | Class method `.parse(text)` converts space or pipe-delimited table text into array of hashes. |
| `KeyValueParser` | class | Class method `.parse(text)` converts key-value text lines (`key: val`) into typed hashes. |
| `TextSanitizer` | class | Class method `.strip_ansi(text)` strips ANSI escape codes and normalizes line endings. |

## Invariants
1. `TableParser.parse` converts header titles to lowercase underscored symbols.
2. `KeyValueParser.parse` coerces integer, float, and boolean values automatically.
3. `TextSanitizer.strip_ansi` returns an empty string for nil input.

## Behavioral Examples
- `TableParser.parse("NAME STATUS\nrune active")` returns `[{ name: 'rune', status: 'active' }]`.
- `KeyValueParser.parse("threads: 4")` returns `{ threads: 4 }`.

## Error Cases
| Condition | Behavior |
|-----------|----------|
| Empty input | Returns empty array or empty hash |

## Dependencies
- Ruby stdlib only

## Change Log
- v1: Active parsers spec contract
