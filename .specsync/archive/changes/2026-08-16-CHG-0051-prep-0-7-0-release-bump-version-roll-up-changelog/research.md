---
change: CHG-0051-prep-0-7-0-release-bump-version-roll-up-changelog
artifact: research
---

# Research

Contents, by where each came from:

| item | origin |
|------|--------|
| `read --grep` / `--context` | reported gap: 379KB pulled into context to find one line |
| `child_busy` / `idle_ms` | reported workaround: grepping the callee's rendered UI |
| `prompt_detected` table | reported symptom, wrong cause — code correct, docs wrong |
| `settled`'s third case | false "finished" 260s early |
| `exit_code` meaning | 8/8 dispatches returned 0, including wrong ones |
| screen tear | reported, two fixes measured and rejected |
| `Session::Transcript` | internal, no behaviour change |
