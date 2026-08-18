---
change: CHG-0067-make-tail-count-a-carriage-return-as-a-line-break-and-report-matched-on-a-reg
artifact: requirements
---

# Requirements

1. A line ends at CR, LF or CRLF everywhere the tail bound counts them.
2. The kept text is byte-identical to that stretch of the original, so CR output
   is not rewritten as LF output.
3. `run --tail` bounds both streams it returns.
4. A regex send reports `matched:` however it ended.
5. The spec, the guide and `--help` describe what the code actually does.
