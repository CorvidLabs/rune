# Doc i18n dogfooding: input-side rune findings and harness errors

Consolidated from 5 translation jobs (each drove a real agent CLI through `rune session`,
conducting the whole session in the target language):

| Doc | Language | CLI | conducted_in_language |
|---|---|---|---|
| docs/sessions.md | pt-BR | claude | true |
| docs/pty_architecture.md | pt-BR | claude | true |
| docs/getting_started.md | es | grok | true |
| docs/getting_started.md | fr | kimi | true |
| docs/getting_started.md | pt-BR | claude | true |

All 5 report `conducted_in_language: true` — no fallback to English mid-session in any job, and
nothing in any job's notes contradicts that self-report. **No language needs a redo on this
criterion.**

Below, findings that recur across independent jobs/CLIs are merged into one mechanism. Verified
items were reproduced against the local build (`ruby -Ilib bin/rune`) using small synthetic PTY
children written for this check — not by re-running claude/grok/kimi, which aren't available in
this environment. A synthetic child isolates the *rune* mechanism from any one product's specific
rendering choices, and lets a control be run alongside the reproduction rather than trusting a
single observation.

## Verified findings

### 1. CONFIRMED — a *decorated* redraw of the operator's own input defeats the `--wait-for-regex` echo veto
Reported by: pt-BR/sessions (claude, chunk 3, `PRONTO_TRES`).

`Echo.condense` strips ANSI escapes and whitespace, then requires the condensed echo to appear as
one **contiguous** substring around a candidate match. A TUI that renders a submitted prompt inside
a bordered "chat bubble" — one non-whitespace glyph (e.g. `| `) prefixed to every wrapped line —
inserts characters `condense` does not strip, so the copy no longer matches contiguously and the
veto silently fails.

Reproduced with a 587-byte multi-line prompt containing `PRONTO_TRES`, sent to two otherwise
identical synthetic children:
- **Bordered redraw** (`| ` prefix per wrapped line): `send --wait-for-regex 'PRONTO_TRES'`
  returned `matched:true, settled:true` in **0.67s** — output was only the bordered echo, no real
  reply (which arrives 3s later) present anywhere in it.
- **Control, same wrapping/colour/timing, no border glyph**: the identical send correctly ran to
  the full timeout (`matched:false, timed_out:true`) because the echo veto recognized the plain
  redraw as a copy of the input and withheld it — proving the border glyph, not the redraw or the
  wrapping itself, is what breaks the veto.

### 2. CONFIRMED — a reused wildcard pattern can match a *prior turn's* stale, already-delivered answer
Reported by: pt-BR/sessions (claude, `SECAO_PRONTA \d+`), pt-BR/pty_architecture (claude,
`PRONTO \d+`), fr/getting_started (kimi, `PRONTO \d+`).

`Echo`/`repaint?` only defend against the pattern matching a copy of *this send's input*. Nothing
defends against a full-screen child redrawing its own scrollback — including a **previous turn's
real, correct answer** — as part of producing a new turn; those bytes are genuinely new on the wire
(fed into the match window as `@fresh`), so a pattern reused turn-to-turn matches them.

Reproduced: turn 1 established a real `DONE 1`. Turn 2 reused `--wait-for-regex 'DONE \d+'` against
a child that clears the screen and reprints all prior answers before computing the new one (3s
delay). The send returned `matched:true, settled:true` in **0.67s**, holding only the redrawn
`DONE 1` — `DONE 2` (the true answer) wasn't in the captured output at all.

### 3. CONFIRMED — `--since=<cursor>` landing mid-UTF-8-character degrades gracefully
Reported by: es/getting_started (grok).

`Transcript#from` calls `.scrub` on the byteslice (`lib/rune/session/transcript.rb:89`), which
Ruby defines to replace invalid byte sequences with U+FFFD. Reproduced: child printed `está não
código á`; `read --since=4` (the byte offset of the lone continuation byte of `á` in `está`)
returned `status: ok`, valid JSON, `output: "� não código á\r\n"` — no crash, no broken envelope,
exactly one replacement character at the split point.

### 4. CONFIRMED — cursor-positioning escapes used as spacing vanish under `clean_output`/`--grep`, not replaced by a space
Reported by: pt-BR/getting_started (claude, "words concatenated with no spaces"),
pt-BR/pty_architecture (claude, `FEITO \d+` permanently times out despite `--screen` showing
`FEITO 3` stably).

`TextSanitizer::ANSI_REGEX` deletes any CSI sequence outright (`gsub(ANSI_REGEX, '')`), including
cursor-forward/cursor-column escapes a TUI may use for padding instead of printing a literal space
byte. Reproduced: child printed `PRONTO\e[1C3` (cursor-forward-1 instead of a space); `clean_output`
came back as `PRONTO3`. This is one mechanism explaining two separately reported symptoms: prose
that reads as run-together words, and a pattern with a literal space (`FEITO \d+`) that can never
match the ANSI-stripped stream even though the terminal-rendered `--screen` shows `FEITO 3` cleanly
and stably — because the raw bytes never contained a literal space to begin with.

### 5. CONFIRMED — CR-driven streaming/spinner redraws become one `clean_output` line per frame, not one final line
Reported by: fr/getting_started (kimi, "~40-line answer produced 1000-1700+ lines of duplicated,
growing-prefix clean_output").

`TextSanitizer.strip_ansi` maps bare `\r` to `\n` (`tr("\r", "\n")`). A terminal renders repeated
`\r`-overwrites as one line updating in place; a flattened text log cannot do that, so each
overwrite becomes its own line. Reproduced: a child streaming a 23-character string one character
at a time via `\r`-overwrite produced 24 `clean_output` lines (`""`, `"B"`, `"Be"`, `"Bem"`, ...,
full string) instead of one. Scales linearly with frame count, matching the reported blow-up on a
longer real answer. Grepping for a *unique* substring near the end of the intended answer still
finds exactly one occurrence, so the final content is not corrupted — only inflated with
intermediate frames, as the fr job itself independently confirmed by the same technique.

### 6. CONFIRMED (mechanism) — `session send` does not bracket multi-line text as a paste, so embedded newlines read as separate submissions to the child
Reported by: fr/getting_started (kimi, "~110-line send sat fully populated and un-submitted for 3+
minutes until one more bare Enter").

`Supervisor#handle_send` writes `request[:text]` verbatim (`lib/rune/session/supervisor.rb:789`)
then a trailing `\r`; there is no bracketed-paste wrapping (`\e[200~ ... \e[201~`) around a
multi-line payload. Reproduced against `bash -i`: a single `send` call whose text contained one
embedded `\n` was executed as **two separate commands** (`echo LINE_ONE` ran the instant the
embedded `\n` arrived; `echo LINE_TWO` ran on rune's trailing `\r`), not treated as one multi-line
paste. This confirms the *root mechanism* — an embedded newline in a `send` payload is
indistinguishable from an Enter keypress to anything reading the pty. The exact kimi symptom
(everything sits displayed and unsubmitted, rather than being split into premature runs) is
TUI-dependent — Ink-based composers commonly buffer multi-line paste differently from a bash
readline prompt — so that specific downstream behavior is plausible but not reproduced here;
flagging it as a real, structural gap rather than closing it as unverified.

## Reported, plausible, not independently reproduced here

These depend on the specific third-party CLI's own rendering/UI choices, which aren't available to
re-run in this environment (no local claude/grok/kimi binaries). Each is internally consistent with
what the transcripts show and is not contradicted by anything in the source, so neither confirmed
nor refuted:

- **Full-screen TUI Markdown rendering strips literal backticks/`**`/`#`** from what `--screen`
  and `clean_output` show (es/grok and fr/kimi both report this independently, for two different
  CLIs, with a diff between the chat-pane path and a Write-tool file-on-disk path as evidence). This
  is the child's own renderer converting markup to styling before it ever reaches the pty as bytes,
  not something rune can see through — both jobs' workaround (have the child write the target text
  to a file instead of relaying it through the chat pane) is the correct one and is exactly what all
  5 jobs converged on independently.
- **kimi's "thinking" preview narrating and resolving an arithmetic sentinel itself**, satisfying
  `--wait-for-regex` before the real answer (fr job). Not the echo-veto or the stale-repaint
  mechanisms above — a third, distinct shape: genuinely new output, genuinely matching the pattern,
  just not the output the caller meant. Closer to a pattern-choice risk than a rune defect; the
  existing docs' "choose a pattern that cannot appear in your own prompt" guidance doesn't yet
  extend to "or in the model's own narrated plan," which this suggests it should.

## Harness errors (self-inflicted, catalogued for future runs)

- `--json` placed after the `--` separator forwards it to the child instead of rune (hit by both
  es/grok and fr/kimi on their first `session start`; both caught and corrected it immediately).
- Trusting `send`'s own `matched`/`settled`/`sent` fields as proof of completion/delivery, instead
  of cross-checking `--screen` or the destination file — the root cause every job eventually
  identified behind findings 1–2 and 6 above. Every job that hit this pivoted to writing translated
  content directly to disk via the child's own Write tool and verifying from there, which is the
  right mitigation.
- Outer Bash-tool 120s default timeout killing a `session send` piped through a second process
  (`| ruby -e ...`) even with a longer `--timeout-ms`, when the underlying rune call had likely
  already finished (pt-BR/sessions). Fixed by redirecting to a file instead of piping.
- A parent-harness command classifier transiently blocking unrelated read-only rune commands after
  a denied `--dangerously-skip-permissions` attempt (pt-BR/sessions) — self-resolved on retry, not a
  rune issue.

## What this means for the docs

`docs/sessions.md` already documents the closest sibling of finding 1 ("a repainted copy of the
input covers a match... the honest claim is every echo shape we could capture is excluded, not
cannot happen") and the closest sibling of finding 4 (`--grep` matching the cleaned stream, not the
screen). Findings 2, 5, and 6 are not currently called out and were each independently rediscovered
by more than one job; they'd be reasonable additions to `docs/sessions.md`'s existing "known
limitations" callouts, but that edit is out of scope for this pass (not requested, and would be a
docs *change* rather than a *verification*).
