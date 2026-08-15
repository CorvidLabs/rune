---
change: CHG-0028-add-persistent-named-agent-sessions-rune-session-start-send-read-list-stop-bac
artifact: context
---

# Context

Requested directly after the 0.3.0 release: "Can we start working on the idea that Rune can just
drive any agent TTY or any agent runner CLI" — one agent (`claude -p`, codex, grok, cursor,
amp, ...) orchestrating others, remembering and reusing a specific session for back-and-forth.

rune is already positioned as a "Universal TTY <-> AI Agent bridge", and 0.3.0's work was largely
driven by exactly this usage (issues #12/#14/#15/#30 all came out of dogfooding rune driving grok
as a subagent). This change is the natural next step: 0.3.0 made *one-shot* agent invocation
robust; this makes *conversational* agent invocation possible at all.

Two decisions were taken explicitly by the user before design:

1. **Persistence mechanism** — per-session detached supervisor, stdlib only (over a tmux backend or
   a central daemon), preserving rune's zero-runtime-dependency stance.
2. **v1 scope** — broker *plus* send-and-settle, with per-agent profiles explicitly deferred.

Scope discipline carried from the design discussion: rune stays a session **broker**, not a message
bus. Cross-session routing — "they all talk to each other" — belongs to the calling agent, which
already has session names to address. Building routing into rune would turn a thin transparent
wrapper into a framework, which is the opposite of what makes it useful.
