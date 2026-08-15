---
change: CHG-0041-bound-the-supervisor-s-in-memory-transcript-to-a-window-so-a-persistent-session
artifact: context
---

# Context

Dogfooding a dimension nobody had looked at: what a supervisor costs while a session runs. Sessions
are meant to be persistent — that is the entire feature — and nothing had ever measured one over
time.

`@transcript` accumulated every byte the child had ever produced and was never trimmed. Against a
child emitting 500KB/s, resident memory tracked output one-for-one: 27MB to 69MB in eighty seconds,
climbing linearly and never coming down. File descriptors were flat, so this was the only leak, but
it is the one that matters for a process designed to outlive the invocation that started it. An
agent TUI is chatty — grok produced 4.6MB in a single council run — so a session left up for a
working day would reach gigabytes.
