---
artifact: context
---

# Context

CHG-0028 shipped `rune session`; CHG-0029 fixed seven defects found by a three-agent review. Both
left a short list of gaps documented as Known Limitations rather than half-fixed. This change closes
four of them, at the point where they had stopped being theoretical:

- attach was advertised as interactive takeover but rendered a full-screen agent at the headless
  40x120 inside whatever terminal a human actually had;
- a single-threaded event loop still had blocking writes on it, which two independent reviewers
  flagged;
- silent control connections accumulated with no bound;
- concurrent `start` of one name was narrowed but explicitly not airtight.

The remaining limitations are deliberately untouched: settle is still a heuristic, `PromptScanner`
still duplicates `PTYRunner`'s rule, `stop` still signals recorded pids, and `clean_output` is still
de-escaped text rather than a rendered screen.
