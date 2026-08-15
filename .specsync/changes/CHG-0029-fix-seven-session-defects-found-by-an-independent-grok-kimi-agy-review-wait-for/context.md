---
artifact: context
---

# Context

CHG-0028 delivered `rune session`. Three agent CLIs — grok, ollama/kimi and agy — were then asked
to review it read-only, each driven through a rune session (dogfooding the feature on itself). They
worked independently and produced overlapping but distinct findings.

Every claim was reproduced before being acted on. Two were rejected as wrong:

- agy: "the exit code is recorded as 0 after stop" — it is `null`, and the described path is not
  reached because the CLI SIGKILLs the supervisor before `conclude` runs.
- grok: "`supervisor.log` is 0644 under umask 022" — umask only removes permission bits, so it was
  already 0600. The same finding's claim about *parent* directories was correct and is fixed here.

This is a separate change from CHG-0028 because that change's deltas were already applied, and
SpecSync correctly refuses to let an applied definition be modified in place.
