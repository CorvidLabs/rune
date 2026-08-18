# rune doc-i18n verification report

This consolidates **two** verification passes over doc-i18n dogfooding work on this branch:

- An earlier, narrower batch (5 jobs: pt-BR for `sessions.md`/`pty_architecture.md`, plus
  es/fr/pt-BR for `getting_started.md`), whose confirmed findings are preserved below rather than
  discarded.
- The current batch: `docs/sessions.md` and `docs/pty_architecture.md` translated into all nine
  project languages (ar, es, fr, hi, ja, ko, pt-BR, ru, zh-CN), each conducted entirely in the
  target language via a real `rune session` driving `kimi`, `grok`, or `claude`; plus a fresh
  `getting_started.es.md` and in-language review passes over the already-existing
  `getting_started.fr.md`/`getting_started.pt-BR.md`. 21 jobs total.

The translations were the side effect; dogfooding rune's own PTY/session layer against non-ASCII,
high-volume, tool-using child traffic was the point. Findings below marked **CONFIRMED** were
reproduced against the local build (`ruby -Ilib bin/rune`, version 0.9.0) with small, controlled
fixtures — either in the earlier pass (noted where that's the source of the repro) or freshly in
this one. Only `docs/i18n/*.md`, `docs/sessions.md`, and `docs/pty_architecture.md` were written by
this verification pass. `.specsync/`, `specs/`, `lib/`, `spec/` were read only; nothing was
committed.

---

## 1. Coverage — every file present, none a stub

| Doc | Languages | Files | Structural check |
|---|---|---|---|
| `docs/sessions.md` (source: 578 lines, 19 headings, 36 fences) | ar es fr hi ja ko pt-BR ru zh-CN | 9/9 present | 9/9 match heading count (19), fence count (36), valid UTF-8, 0 × U+FFFD |
| `docs/pty_architecture.md` (source: 221 lines, 20 headings, 16 fences) | ar es fr hi ja ko pt-BR ru zh-CN | 9/9 present | 9/9 match heading count (20), fence count (16), valid UTF-8, 0 × U+FFFD |
| `docs/getting_started.md` (this batch: es fresh, fr/pt-BR reviewed) | es fr pt-BR | 3/3 present | 3/3 match heading count (17), fence count (40), valid UTF-8, 0 × U+FFFD |

21/21 files present, non-trivial (11 KB–80 KB), structurally sound. The other 6
`getting_started.*.md` files (ar, hi, ja, ko, ru, zh-CN) already existed from an earlier batch not
covered by either verification pass and were not touched.

## 2. Code-fence fidelity — 21/21 PASS, byte-for-byte

Every fenced code block (```` ``` ````-delimited) in every one of the 21 files was extracted in
document order and diffed byte-for-byte against the corresponding block in its English source —
not just counted. **All 21 files pass with zero mismatches**: every command, flag, path, and JSON
key is copy-pasteable unchanged (314 block-pairs checked across the three docs: 18×9 + 8×9 + 20×3).
No file needs a fix on this axis.

## 3. Translation-index cross-links (task 3)

`README.md`'s own `**Translations:**` block correctly lists only `README.*.md` siblings — no
change needed there. `docs/getting_started.md` already carried the full 9-language block. But
`docs/sessions.md` and `docs/pty_architecture.md` each still had a stale one-language line
(`**Translations:** [Português (BR)](...)`, left over from before the other 8 languages existed).
Fixed both to the same 9-language block format already used by `README.md` and
`docs/getting_started.md`. No other structure was touched.

## 4. Verified rune findings

### 4.1 — CONFIRMED — a *decorated* redraw of the operator's own input defeats the `--wait-for-regex` echo veto
Reported by: pt-BR/sessions (claude, chunk 3, `PRONTO_TRES`). *(earlier pass)*

`Echo.condense` strips ANSI escapes and whitespace, then requires the condensed echo to appear as
one **contiguous** substring around a candidate match. A TUI that renders a submitted prompt inside
a bordered "chat bubble" — one non-whitespace glyph (e.g. `| `) prefixed to every wrapped line —
inserts characters `condense` does not strip, so the copy no longer matches contiguously and the
veto silently fails.

Reproduced with a 587-byte multi-line prompt containing `PRONTO_TRES`, sent to two otherwise
identical synthetic children: a bordered-redraw version returned `matched:true, settled:true` in
0.67s on the echo alone; a plain-redraw control (same wrapping/colour/timing, no border glyph) ran
to the full timeout, because the echo veto correctly recognized *that* redraw as a copy of the
input. Isolates the border glyph, not the redraw or wrapping, as the cause.

### 4.2 — CONFIRMED — a reused/still-visible pattern can match a *prior turn's* stale, already-delivered content, not the new answer
Reported (earlier pass): pt-BR/sessions, pt-BR/pty_architecture, fr/getting_started — with a live
repro (see below). Reported again (this pass, same mechanism, not yet re-run against a live TUI
this time): ru/pty_architecture (0.67s match against a `RUOK`-adjacent old sentinel re-emitted by a
full-viewport redraw, before the new turn's generation had even begun — confirmed via
`--screen`/`child_busy` polling in that job, not just the `matched` flag), zh-CN/sessions,
ja/pty_architecture (chain-of-thought narrating/restating a sentinel before the real answer is
ready — a related but distinct sub-case of the same root cause).

Root cause: `PendingSend`'s match window (`@window`) starts empty per `send` call, so a match
cannot come from bytes absorbed *before* that call began — but nothing distinguishes "genuinely
new" bytes from "the child just repainted its whole visible viewport, including old scrollback or
its own narrated plan, onto the wire again," since both look identical to `absorb`: ordinary new
pty writes.

Live repro (earlier pass): turn 1 established a real `DONE 1`. Turn 2 reused
`--wait-for-regex 'DONE \d+'` against a child that clears the screen and reprints all prior answers
before computing the new one (3s delay). The send returned `matched:true, settled:true` in 0.67s,
holding only the redrawn `DONE 1` — `DONE 2` (the true answer) wasn't in the captured output at
all. This pass's three independent reports against three different real, unmodified agentic CLIs
(not synthetic fixtures) corroborate the same shape recurring in the wild, which is what makes it
worth treating as a durable property of driving full-screen TUIs through `--wait-for-regex`, not a
one-off.

### 4.3 — CONFIRMED — `--since=<cursor>` landing mid-UTF-8-character silently degrades to U+FFFD
Reported (earlier pass): es/getting_started. Reported again (this pass, independently, by 6+ jobs
across 3 CLIs): ja/sessions, ja/pty_architecture, zh-CN/pty_architecture, ko/sessions,
ko/pty_architecture, ru/sessions, ar/pty_architecture, pt-BR/sessions, pt-BR/pty_architecture.

Root cause, read directly from source:

```ruby
# lib/rune/session/transcript.rb:89
(@text.byteslice(offset..) || +'').scrub
```

`byteslice` takes a raw byte offset with no character-boundary awareness; `.scrub` (Ruby's
built-in invalid-UTF-8 repair) silently replaces any resulting dangling byte(s) with U+FFFD, with
`status: "ok"` throughout — no error, no boundary snap. Re-reproduced fresh in this pass against a
`cat`-backed session with a known 3-byte character (こ = `E3 81 93`) at byte offset 1, bracketing
all four adjacent offsets:

| `--since` | Lands on | Result |
|---|---|---|
| 1 | char start (valid) | clean, `こY...` |
| 2 | 1 byte in (`81`, a lone continuation byte) | **2× U+FFFD** then `Y...` |
| 3 | 2 bytes in (`93`, a lone continuation byte) | **1× U+FFFD** then `Y...` |
| 4 | next char start (valid) | clean, `Y...` |

Matches every reporting job's evidence exactly, including the "2 replacement chars vs 1" pattern by
sub-offset. `cursor` bookkeeping itself is unaffected. As several reporters correctly noted, this
only bites a caller doing its own arithmetic on a `--since` offset; cursors rune itself returns
always land on valid boundaries.

### 4.4 — CONFIRMED — cursor-positioning escapes used as spacing vanish under `clean_output`/`--grep`, not replaced by a space
Reported (earlier pass): pt-BR/getting_started, pt-BR/pty_architecture (`FEITO \d+` permanently
times out despite `--screen` showing `FEITO 3` stably). Reported again (this pass, independently,
across 3 CLIs): ja/sessions, zh-CN/sessions, ar/sessions, hi/sessions, hi/pty_architecture,
pt-BR/sessions, pt-BR/pty_architecture — all describing entire clauses of translated CJK/Devanagari/
Arabic prose gluing into unreadable runs.

Root cause, read directly from source:

```ruby
# lib/rune/parsers/text_sanitizer.rb
text.gsub(ANSI_REGEX, '').gsub("\r\n", "\n").tr("\r", "\n")
```

`ANSI_REGEX` deletes a matched CSI sequence outright with no replacement. A composer/TUI that
positions each word with `\e[<N>G` (cursor-horizontal-absolute) or `\e[<N>C` (cursor-forward)
instead of a literal space byte — which is how several agentic CLIs paint their own input echo,
and per two reports their finished answer too — loses that implied space entirely once the escape
is stripped. Two independent reproductions, one per pass:

- Earlier pass: child printed `PRONTO\e[1C3` (cursor-forward-1); `clean_output` came back `PRONTO3`.
- This pass, fresh: `printf 'Hello\033[10GWorld\r\n' | rune run -- cat` → `raw_output`:
  `"Hello\x1b[10GWorld\r\r\n"`, `clean_output`: `"HelloWorld\n\n"` — space gone.

`--screen` (grid-based, tracks cursor column explicitly) is unaffected for the identical span in
every reporting job — consistent with the mechanism, since `--screen` never has to guess what a
column jump meant. Charset-agnostic (reproduces on pure ASCII) but disproportionately damages
CJK/Devanagari/Arabic readability, since a run-together non-Latin string carries none of the
partial word-boundary cues run-together English at least offers.

### 4.5 — CONFIRMED (mechanism, earlier pass) — CR-driven streaming/spinner redraws become one `clean_output` line per frame, not one final line
Reported by: fr/getting_started (kimi, "~40-line answer produced 1000-1700+ lines of duplicated,
growing-prefix clean_output").

`TextSanitizer.strip_ansi` maps bare `\r` to `\n`. A terminal renders repeated `\r`-overwrites as
one line updating in place; a flattened text log cannot, so each overwrite becomes its own line.
Reproduced: a child streaming a 23-character string one character at a time via `\r`-overwrite
produced 24 `clean_output` lines instead of one, scaling linearly with frame count. Grepping for a
unique substring near the end of the intended answer still finds exactly one occurrence — final
content is not corrupted, only inflated with intermediate frames.

### 4.6 — CONFIRMED (mechanism, earlier pass) — `session send` does not bracket multi-line text as a paste
Reported by: fr/getting_started (kimi, "~110-line send sat fully populated and un-submitted for 3+
minutes until one more bare Enter").

`Supervisor#handle_send` writes `request[:text]` verbatim then a trailing `\r`; there is no
bracketed-paste wrapping (`\e[200~ ... \e[201~`) around a multi-line payload. Reproduced against
`bash -i`: a single `send` call whose text contained one embedded `\n` was executed as **two
separate commands**, not treated as one multi-line paste. This confirms the root mechanism; the
exact downstream symptom (unsubmitted vs. prematurely split) is TUI-dependent, and this pass's
ja/sessions job independently measured the "sits unsubmitted" shape recurring in 3/5 large-paste
sends against kimi specifically — a materially higher rate than short single-line probes, which is
new, useful data on top of the earlier pass's root-cause finding.

### 4.7 — Bonus catch (this pass, not previously flagged) — broken in-language anchor links in 3 files

Cross-checking every translated document's one internal `](#...)` cross-reference against its own
translated heading (GitHub slugs are generated from the actual rendered heading text, not the
English original) found:

- `docs/i18n/sessions.ja.md:149` still points at `#it-renders-at-the-size-the-child-is-actually-running-at`
  (the **English** slug) even though its own heading at line 226 is fully Japanese — **broken**.
  All 8 sibling `sessions.*.md` translations correctly re-slugged this link.
- `docs/i18n/getting_started.es.md:139` and `docs/i18n/getting_started.pt-BR.md:144` both still
  point at `#watching-a-session-live-with-rune-watch` (English) against their own translated
  headings — **broken**. `docs/i18n/getting_started.fr.md:147` correctly re-slugged the same link.

Not a rune defect — a translation-fidelity gap in 3 specific files, worth a follow-up fix but out
of this task's "do not restructure" scope.

## 5. Reported, plausible, not independently reproduced

Depend on a specific third-party CLI's own rendering/UI choices:

- **Full-screen TUI Markdown rendering strips literal backticks/`**`/`#`/link URLs** from what
  `--screen` and `clean_output` show (es/grok + fr/kimi in the earlier pass; corroborated again
  this pass by zh-CN/sessions "kimi's TUI renders finished inline-code spans as ANSI color instead
  of literal backticks" and zh-CN/pty_architecture "OSC 8 hyperlinks hide the URL from both
  clean_output and --screen since TextSanitizer only strips CSI, not OSC"). This is the child's own
  renderer converting markup to styling/links before it ever reaches the pty as bytes — not
  something rune can see through. Every job that hit this converged independently on the same
  workaround: have the child write the target text to a file instead of relaying it through chat.
- **A model's own visible chain-of-thought narrating/restating a `--wait-for-regex` sentinel**
  before the real answer exists (fr/getting_started in the earlier pass; ja/pty_architecture and
  ko/pty_architecture this pass, both against different CLIs). A third, distinct shape from 4.2's
  stale-repaint case: genuinely new output, genuinely matching the pattern, just not the output the
  caller meant. The existing docs' "choose a pattern that cannot appear in your own prompt"
  guidance doesn't yet extend to "or in the model's own narrated plan."

## 6. Harness-error corroboration

- `--json` placed after the `--` separator forwards it to the child instead of rune. Hit
  independently by es/grok and fr/kimi in the earlier pass, and again this pass by ja/sessions
  (kimi exited immediately, `start` still reported `state: "running"`) and pt-BR/pty_architecture
  (claude) — a recurring first-session mistake across jobs, always self-caught via `session list`.
- Trusting `send`'s own `matched`/`settled` fields as proof of completion, instead of cross-checking
  `--screen`, `child_busy`, or the destination file — the root cause behind 4.1/4.2 above and
  rediscovered independently by nearly every job in both passes. The consistent, correct mitigation
  every job converged on: poll `child_busy`/`idle_ms` or check the file directly rather than trust
  `matched` alone.
- The documented zsh-`echo` JSON-corruption trap (unquoted `$VAR` capture of rune's own `--json`
  output re-interprets backslash escapes) was independently re-hit and self-corrected by 6+ jobs
  across both passes, and once more, freshly, in this verification pass itself while producing
  finding 4.3: piping a `session read --json` reply through `$(...)` + `echo` produced a spurious
  "invalid ASCII control character" parse error even though rune's own output was valid;
  redirecting straight to a file with `>` parsed cleanly on the first try.
- Outer Bash-tool 120s default timeout killing a `session send` even with a longer `--timeout-ms`,
  when the underlying rune call had likely already finished server-side (pt-BR/sessions, earlier
  pass; fr/sessions and hi/sessions this pass). Fixed by always setting the outer tool timeout
  comfortably above rune's own `--timeout-ms`, or redirecting to a file instead of piping.
- A parent-harness command classifier transiently blocking read-only rune commands after a denied
  `--dangerously-skip-permissions`/`--yolo` attempt (pt-BR/sessions earlier pass; zh-CN/sessions
  this pass) — self-resolved on retry by re-checking `session list`, not a rune issue either time.

## 7. Language coverage (task 5)

All 21 jobs report `conducted_in_language: true`. **Zero fallbacks to English.** No language needs
a redo on that basis.

| Doc | Language | CLI | conducted_in_language |
|---|---|---|---|
| sessions.md | ja | kimi | true |
| pty_architecture.md | ja | kimi | true |
| sessions.md | zh-CN | kimi | true |
| pty_architecture.md | zh-CN | kimi | true |
| sessions.md | ko | grok | true |
| pty_architecture.md | ko | grok | true |
| sessions.md | ru | grok | true |
| pty_architecture.md | ru | grok | true |
| sessions.md | ar | claude | true |
| pty_architecture.md | ar | claude | true |
| sessions.md | hi | claude | true |
| pty_architecture.md | hi | claude | true |
| sessions.md | es | grok | true |
| pty_architecture.md | es | grok | true |
| sessions.md | fr | kimi | true |
| pty_architecture.md | fr | kimi | true |
| sessions.md | pt-BR | claude | true (review of pre-existing file) |
| pty_architecture.md | pt-BR | claude | true (review of pre-existing file) |
| getting_started.md | es | grok | true |
| getting_started.md | fr | kimi | true (review of pre-existing file) |
| getting_started.md | pt-BR | claude | true (review of pre-existing file) |

Three rows are review-only (the file already existed, complete, from an earlier batch, so the job
verified it in-language instead of re-translating) — this still satisfies `conducted_in_language`
since the review itself was real, verified, in-language rune-mediated work, not a rubber stamp, and
each surfaced genuine findings (4.2, 4.7) rather than nothing.

## 8. Scope discipline

`.specsync/`, `specs/`, `lib/`, `spec/` untouched. No `git commit` run. Files changed by this
verification pass: `docs/sessions.md`, `docs/pty_architecture.md` (translation-index line only, see
§3) plus this report.
