# rune native-language i18n dogfooding report

Six agents translated `docs/getting_started.md` into Japanese, Simplified Chinese, Korean, Russian,
Arabic and Hindi — and, unlike the previous round, **conducted the entire rune session in the
language they were translating into**. The translations are the side effect. The point is that
every byte written *into* the pty was non-ASCII, which is ground the previous round never touched.

This document is a **verification pass**, not a transcription. Every claim below was re-run against
the local build (`ruby -Ilib bin/rune`, 0.9.0, `RUNE_HOME=/tmp/native-verify`) on fresh probe
sessions. Verdicts are mine. Where a reporter's framing did not survive re-measurement I say so, and
several did not — including one finding this round overturns from the *previous* report.

Nothing outside this file was written. `.specsync/`, `specs/`, `lib/` and `spec/` were read only.

> **Tree note.** `lib/rune/commands/session_command.rb` and `spec/rune/session_spec.rb` were already
> modified when this pass began (a concurrent agent's improvement to the `no_such_session` message,
> naming the owning project). I did not author or revert them. The change touches only an error path
> none of the findings below exercise, so no verdict depends on it.

---

## 1. Why this round found different things

The previous round sent **English prompts** and could therefore only observe what rune did with
non-ASCII **output**. Everything it found lived on the read path: `--tail`, `--grep`, `clean_output`,
`--max-output`, screen rendering.

Conducting the session in-language moves non-ASCII onto the **write** path — the argv, the pty
write, the line discipline, the echo boundary, the session name. Four of the confirmed findings
below are structurally unreachable from an English-prompt round:

| Finding | Why only an in-language round finds it |
|---|---|
| Cooked-mode overflow **jams the channel** | Needs a >1024-byte single line. Japanese hits it at 341 characters, Korean at ~341 — an ordinary paragraph. English needs 1024. |
| Mid-character cut fabricates U+FFFD | Requires the 1024-byte cut to land inside a character. Impossible in ASCII. |
| `command` display field is illegible | Requires a non-ASCII argument. |
| Non-ASCII session name rejected | Requires naming a session in your own script. |

That is the honest answer to "what did conducting in-language expose": **the input path is largely
sound, and the four places it is not are places English can never reach.**

---

## 2. Language discipline — who actually stayed in-language

`conducted_in_language` is self-assessed, and the six agents applied visibly different standards. The
flag as reported is not comparable across runs, so here is what each actually did.

| Language | Reported | Agent dialogue | Ancillary probe traffic | Assessment |
|---|---|---|---|---|
| Russian | `true` | 13 sends, 100% Cyrillic | none — instructed grok to read line ranges from disk | **Cleanest.** No English through the pty at all. |
| Simplified Chinese | **`false`** | 7 sends, 100% 简体中文 | ASCII payloads to `cat` / `sh` control children | **Stricter than its own flag.** Nothing English reached the agent. |
| Japanese | `true` | 5 sends, 100% Japanese; approvals driven with raw `\033[B`/`\r` | ASCII control arms in probes | Equivalent to zh-CN, flagged the other way. |
| Arabic | `true` | 8 sends, 100% Arabic | ASCII control arms, disclosed | Equivalent to zh-CN, flagged the other way. |
| Hindi | `true` | 5 sends, Hindi prose with English identifiers embedded | — | Fair: identifiers must stay English by the brief. |
| Korean | `true` | 8 sends Korean **plus English source sections quoted verbatim into the agent** | — | **Weakest `true`.** English bytes did reach the child, unlike zh-CN's. |

**No round quietly reverted to English.** All six conducted the actual translation dialogue in the
target language, and the input-path findings rest on genuinely non-ASCII sends.

The inconsistency worth recording: **zh-CN marked itself `false` for exactly the practice Japanese
and Arabic marked `true` for** (ASCII control arms against non-agent children), while Korean marked
`true` despite piping English source text to the agent. Read literally, the flag would rank the most
scrupulous reporter lowest. The paired ASCII control is *methodologically required* — two of the
strongest findings below are stated as a delta against one, and a control is what killed the largest
candidate finding of the round. A future brief should ask for "language used with the driven agent"
and treat control payloads as a separate, expected disclosure.

---

## 3. Verdicts at a glance

| # | Claim | Reporters | Side | Verdict |
|---|---|---|---|---|
| 1 | Cooked-mode overflow jams **every later send**; rune reports `settled:true, state:running` | ja | input | **CONFIRMED — new** |
| 2 | Overflow cut mid-character fabricates U+FFFD in `clean_output` | ja | input | **CONFIRMED — new** |
| 3 | `command` display field backslash-escapes every non-ASCII character | ar | input | **CONFIRMED — new** |
| 4 | Non-ASCII session name rejected; message says "letters" | ar | input | **CONFIRMED — new** |
| 5 | `ScreenRenderer.resync` uses a char index as a byte offset | ko, ru | output | **CONFIRMED — new** |
| 6 | `--wait-for-regex` satisfied by a repaint of an **earlier reply's** sentinel | hi | output | **CONFIRMED — new** |
| 7 | `--since` mid-character silently returns U+FFFD | zh, ko, ar, hi, ru | read | **CONFIRMED — low severity** |
| 8 | `--screen` over-charges Devanagari width | hi | output | **CONFIRMED, mechanism corrected** |
| 9 | MAX_CANON truncation bites CJK/Hangul at ⅓ the characters | ja, ko, ar | input | **CONFIRMED — already documented** |
| 10 | `--wait-for-regex` matches the raw byte stream, not the screen | ko, ru | output | **CONFIRMED — already in ROADMAP:82** |
| 11 | Escape-interleaving is "far worse for Korean than English" | ko | output | **REFUTED** |
| 12 | `--screen` charges one column per codepoint | hi | output | **REFUTED as framed** |
| 13 | *Previous round, Rank 5:* combining marks "charged a column each" | prior report | output | **REFUTED** |

---

## 4. Input-side findings — the new ground

### 4.1 A single over-long send jams the channel permanently, and rune reports success — **CONFIRMED**

The documented limitation (`docs/sessions.md:499`, `specs/session/session.spec.md:983`) covers the
loss of the over-long line: *"1023 bytes arrive, 1024 do not… Chunk it, or drive a raw-mode target."*
It does not say that **every subsequent send to that session is also swallowed.**

Paired arms against `cat`, differing only in the size of the **first** send:

```
CONTROL(1023B)  FIRST  sent=1023 settled=true timed_out=nil state=running back=2048
CONTROL(1023B)  probe0 echoed=true  ...  out="PROBE\nPROBE\n"
CONTROL(1023B)  probe1 echoed=true
CONTROL(1023B)  probe2 echoed=true

OVERFLOW(1200B) FIRST  sent=1200 settled=true timed_out=nil state=running back=1025
OVERFLOW(1200B) probe0 echoed=false settled=true timed_out=nil state=running out="\a\a\a\a\a\a"
OVERFLOW(1200B) probe1 echoed=false settled=true timed_out=nil state=running
OVERFLOW(1200B) probe2 echoed=false settled=true timed_out=nil state=running
```

The probes are ordinary 5-byte sends. Every one returns `settled: true`, `timed_out: nil`,
`state: running` — the envelope of a successful send. The only trace is a run of BEL bytes in
`clean_output`, the tty ringing for each rejected byte.

Recovery exists and is undiscoverable. A bare **U+0015 (line kill)** clears it instantly:

```
after CTRL-U    echoed=true settled=true state=running out="PROBE\nPROBE\n"
```

Grepping `docs/`, `specs/` and `ROADMAP.md` for `line.kill|0x15|subsequent send|jam` returns
nothing. The mechanism is the kernel line discipline, not a rune write bug — which is why this is
filed as a **reporting and recovery gap**: rune has the BELs in hand and answers "fine".

Why it is a native-language finding despite being byte-based: the bound is **1024 bytes**, so
Japanese trips it at 341 characters and Korean at ~341, where English survives to 1024. The JA
reporter's real prompts were 400–500 characters and only worked because the child ran raw mode.

### 4.2 The overflow cut lands mid-character and fabricates a U+FFFD — **CONFIRMED**

Same 1200-byte send, one arm per script, fresh `cat` session each:

```
ja  sent_bytes=1200 back_bytes=1027 back_chars=343  FFFD=1 valid=true  tail="あああああ<U+FFFD>"
asc sent_bytes=1200 back_bytes=1025 back_chars=1025 FFFD=0 valid=true
```

341 × あ = 1023 bytes fit; the 1024th byte accepted is the **first byte of character 342**, and its
two continuation bytes are discarded. The tty echoes the orphan, `TextSanitizer` scrubs it, and a
Japanese caller reading `clean_output` sees 341 characters they typed plus one character that exists
nowhere in their input. The spec says the line is *"silently discarded… the child never sees it"* —
true of the child, not of the transcript the caller is handed. Severity genuinely low; it is a
contract mismatch, not an encoding bug.

### 4.3 The `command` display field is illegible for any non-ASCII argument — **CONFIRMED**

```
$ rune run --json -- echo 'مرحبا بالعالم'
  command      = "echo \\م\\ر\\ح\\ب\\ا\\ \\ب\\ا\\ل\\ع\\ا\\ل\\م"
  clean_output = "مرحبا بالعالم\n"

$ rune run --json -- echo 'hello world'
  command      = "echo hello\\ world"          <- one escape, for the space

$ rune run --json -- echo '日本語 テスト'
  command      = "echo \\日\\本\\語\\ \\テ\\ス\\ト"
```

`Shellwords.join` escapes every character outside `[A-Za-z0-9_\-.,:+/@\n]`, which is every Arabic,
CJK, Cyrillic, Devanagari and Hangul codepoint. **Not Arabic-specific** — the AR reporter framed it
as such; it is universal to non-Latin scripts, and I confirmed CJK and Cyrillic independently.

Scope is confined to the joined display string; `meta.json`, the `session list` row and the
`session start` reply all carry the clean argv array. It is not shell-incorrect and it round-trips
through `Shellwords.split`. But `docs/getting_started.md:180` and `specs/watch/watch.spec.md:131`
describe this field as a *"shell-escaped display reconstruction for humans"*, and for a non-Latin
argument no human can read it. The field's only purpose is the one it fails at.

### 4.4 A session named in your own script is rejected, by a message that says it shouldn't be — **CONFIRMED**

```
$ rune session start --name جلسة --json -- cat
{"status":"error","error":"Invalid session name \"جلسة\". Use letters, digits, '.', '_' or '-' (max 64 chars), starting with a letter or digit."}

$ rune session start --name сессия --json -- cat
{"status":"error","error":"Invalid session name \"сессия\". ..."}
```

`lib/rune/session/store.rb:28` — `NAME_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z/`. ASCII
letters only, while the message at `session_command.rb:1178` says "letters, digits". جلسة is four
letters; сессия is six. The reader is told their name qualifies and has nowhere to go.

Restricting names to ASCII is **defensible** — they become directory and socket path components — so
this is filed against the message, not the rule. The name is echoed back correctly, so rune received
it intact and rejected it on the pattern.

### 4.5 MAX_CANON truncation — **CONFIRMED, already documented**

Reproduced (§4.1, §4.2). The limit, the exact 1023/1024 boundary and the silence are all recorded at
`docs/sessions.md:499-505` and `specs/session/session.spec.md:983-989`, including that raw-mode
children are unaffected. The reporters' contribution is the **character-count framing** — the same
byte ceiling costs a CJK or Hangul caller two thirds of their line — which is a fair addition to the
docs but not a new defect. Not filed. The *jam* (§4.1) is the new part.

---

## 5. Output-side findings

### 5.1 `ScreenRenderer.resync` reads a character index as a byte offset — **CONFIRMED**

`lib/rune/parsers/screen_renderer.rb:204-207`:

```ruby
escape = window.byteslice(0, RESYNC_SCAN_BYTES).to_s.index("\e")   # CHARACTER index
return window if escape.nil? || escape.zero?

window.byteslice(escape..).to_s                                     # BYTE offset
```

They coincide only on ASCII. Reproduced offline from a synthetic >512KB fixture with **no session
and no agent involved** — source valid UTF-8, zero U+FFFD in all arms, window cut verified to land
exactly at the head of each run, suffix filled with `\e[0m` no-ops so row 0 survives:

```
case                       escC   escB   winOK   srcFFFD  scrFFFD  row0
ASCII before ESC (control) 2      2      true    0        0        "ZZ"
1 x 3-byte braille         1      3      true    0        2        "<FFFD><FFFD>ZZ"
2 x 3-byte braille         2      6      true    0        1        "<FFFD>⢿ZZ"
3 x 2-byte Cyrillic        3      6      true    0        1        "<FFFD>нZZ"
2 x 3-byte CJK             2      6      true    0        1        "<FFFD>本ZZ"
3 x 3-byte Devanagari      3      9      true    0        0        "िनZZ"
1 x 2-byte Arabic          1      2      true    0        1        "<FFFD>ZZ"
1 x 4-byte emoji           1      4      true    0        3        "<FFFD><FFFD><FFFD>ZZ"
```

Rendering the identical text with `tail_bytes: nil` gives **zero U+FFFD in every arm**, which is what
isolates `resync` from the window cut's own `.scrub`.

**Two distinct symptoms**, and only the first was reported:

1. **Fabricated U+FFFD** — the screen shows replacement characters that exist nowhere in the
   transcript. Both reporters measured this live (ru at cursor 722,429; ko at 2.9 MB, transcript
   U+FFFD count zero).
2. **`resync` fails at its own job** — the Devanagari arm slices at byte 3, which happens to be a
   valid boundary, so there is no U+FFFD; but `िन` survives on screen when the whole point of
   resync is to drop everything before the first ESC. The comment above the method says *"Resyncing
   to the first `ESC` drops that remainder."* Cutting short of the ESC leaves it.

Reachability is real, not theoretical: it needs a transcript over `DEFAULT_TAIL_BYTES` (512 KB) with
non-ASCII in the 256 bytes after the cut — routine for a long agent session in any non-Latin
language. Invisible on ASCII, where the two indices coincide.

### 5.2 `--wait-for-regex` is satisfied by a repaint of an *earlier reply's* sentinel — **CONFIRMED**

This is the most consequential output-side finding of the round, and the HI reporter partly
disowned it as their own sentinel-reuse error. The underlying defect is real and independent of that.

I reproduced it deterministically with an **ASCII sentinel the caller never types at all**. The child
reprints its scrollback on every input line, then works for 6 seconds, then prints a new reply:

```
send0 elapsed=6.4s   matched=true settled=true | distinct replies child has EVER made=1 (expected 1)
send1 elapsed=0.4s   matched=true settled=true | distinct replies child has EVER made=1 (expected 2)
send2 elapsed=5.87s  matched=true settled=true | distinct replies child has EVER made=2 (expected 3)
```

`send1` returns in **0.4 s** with `matched: true, settled: true` while the child is still sleeping and
has printed nothing new. The match was the repaint of reply #1's sentinel.

`Echo#repaint?` (`pending_send.rb:470`) suppresses a match covered by a copy of the **current
input**. Nothing covers a repaint of **earlier output**, so a long-lived TUI that repaints its
scrollback re-arms every sentinel it has ever printed. `ROADMAP.md:82`'s table covers *"caller's
prompt in a composer box"* — the caller's input. This is a different false positive and is not
recorded anywhere.

This is script-neutral. It surfaced in the Hindi run because agent CLIs repaint scrollback, not
because of Devanagari.

### 5.3 `--since` at a mid-character offset silently returns U+FFFD — **CONFIRMED, low severity**

Reported independently by five of the six agents. Transcript `हिन्दी 日本語 مرحبا Привет`:

```
--since=0  status=ok bytes=108 FFFD=0 valid=true head="हिन्दी 日本語"
--since=1  status=ok bytes=111 FFFD=2 valid=true head="<FFFD><FFFD>िन्दी 日本"
--since=2  status=ok bytes=108 FFFD=1 valid=true head="<FFFD>िन्दी 日本語"
--since=3  status=ok bytes=105 FFFD=0 valid=true head="िन्दी 日本語 "
--since=4  status=ok bytes=108 FFFD=2 valid=true head="<FFFD><FFFD>न्दी 日本語"
```

One U+FFFD per orphaned continuation byte, `status: ok`, `valid_encoding?` true — a consumer cannot
distinguish rune's slicing damage from a U+FFFD the child emitted. Mechanism:
`lib/rune/session/transcript.rb:89`, `(@text.byteslice(offset..) || +'').scrub`.

Note the arithmetic consequence: `--since=1` returns **more** bytes (111) than `--since=0` (108),
because two orphan bytes become two 3-byte replacement characters. Cursor arithmetic does not
reconcile on a misaligned cursor.

**Severity is bounded by a negative result I verified independently** (§7.1): rune never *hands out*
a bad cursor. This only bites a caller doing arithmetic on one — e.g. `--since=$((cursor-200))` to
back up, which is a natural thing to do with a documented byte offset, and which is safe for every
value on ASCII and unsafe for roughly half of them on a 3-byte script.

### 5.4 `--wait-for-regex` matches the raw byte stream — **CONFIRMED, already recorded**

Deterministic repro, child emitting per line
`\e[32m가\e[0m\e[32m나\e[0m  \e[32mA\e[0m\e[32mB\e[0m\r\n` then `다라 CD\r\n`:

```
contiguous Hangul (다라)          matched=true  timed_out=nil
contiguous ASCII (CD)            matched=true  timed_out=nil
escape-interleaved Hangul (가나)  matched=false timed_out=true
escape-interleaved ASCII (AB)    matched=false timed_out=true
```

`--screen` renders both rows correctly (`가나  AB`, `다라 CD`), so the pattern is plainly visible while
the wait fails. `ROADMAP.md:82` already records the byte stream as *"the wrong surface"* with a
mechanism table. The `--help` text does not carry the caveat, and `docs/sessions.md:156,464,493` still
recommends the flag as *"deterministic"* — which the previous report already filed as Rank 8.

---

## 6. Refutations — the useful part

### 6.1 "Escape-interleaving is far worse for Korean than English" — **REFUTED**

The KO summary states the defect is *"far worse for Korean than for English"* because grok emits a
cursor escape between every Hangul character but writes ASCII runs contiguously.

The **rune-side mechanism is script-neutral**. My paired control above shows `AB` failing exactly as
`가나` fails, in the same reply, from the same session. The asymmetry is entirely a property of the
child's painting — non-Latin text tokenizes at roughly one token per character, so grok paints it per
cell — and would vanish against a child that writes contiguously.

KO's own `controlled` section concedes this ("the fragmentation is grok's token-by-token painting,
not rune writing bytes wrongly"), and the RU reporter states it correctly throughout. But the summary
line, which is what a maintainer reads, attributes a child's behaviour to rune. The real and
reportable fact is narrower: **for a non-Latin sentinel against a token-painting TUI, ROADMAP:82's
"split by streaming token paint" row is not an occasional mechanism, it is the default one.**

### 6.2 "`--screen` charges one column per codepoint" — **REFUTED as framed; a narrower defect CONFIRMED**

HI's evidence reproduces byte-exactly. `D:हिन्दी\e[5GXY` really does render `D:हिXYदी`, and हिन्दी
really is charged 6 columns. But the stated mechanism is wrong, and the wrong mechanism points at
the wrong fix.

```
abcdef (6 ASCII)             codepoints=6 rune_cols=6
हिन्दी (6 cp, 3 clusters)     codepoints=6 rune_cols=6     <- over by 1 (the virama)
بَبَبَ (6 cp, 3 clusters)      codepoints=6 rune_cols=3     <- correct
日本語 (3 cp wide)            codepoints=3 rune_cols=6     <- correct
é decomposed (2 cp)          codepoints=2 rune_cols=1     <- correct
```

rune does **not** charge per codepoint. `lib/rune/parsers/character_width.rb` has a `ZERO` table, and
it works — for the scripts it covers. The actual defect is that **the table omits every Indic
combining mark**:

```
Arabic fatha      U+064E  width=0   (0x064B..0x065F covered)
Hebrew point      U+05B0  width=0   (0x0591..0x05BD covered)
Thai              U+0E34  width=0   (0x0E31, 0x0E34..0x0E3A covered)
Combining acute   U+0301  width=0   (0x0300..0x036F covered)
Devanagari virama U+094D  width=1   <- should be 0 (Mn)
Deva anusvara     U+0902  width=1   <- should be 0 (Mn)
Bengali virama    U+09CD  width=1   <- should be 0 (Mn)
Tamil virama      U+0BCD  width=1   <- should be 0 (Mn)
```

`U+0900..U+0DFF` is absent from `ZERO` entirely. rune over-charges a Devanagari string by exactly its
count of non-spacing marks, so it wraps early and lands an absolute-column escape in the wrong cell.
The file's own comment says the table is *"a curated subset… what it misses renders one column
wide"* — so this is a known-shape gap, not an oversight in logic. The fix is data, not code.

Two further corrections to HI's framing:

- **The "shearing" is not solely rune's.** `CSI n G` into the middle of a grapheme cluster is
  destructive in a real terminal too. rune's version differs in *where* it lands, because of the
  width error — not in *that* it lands destructively. The Arabic arm shears identically
  (`D:بَبَبَ\e[5GXY` → `D:بَبَXY`) while being width-correct.
- **The interleaved-ASCII example** (`"ि कितनी tarttbynreadingethedsourceुfile.ै"`) is the documented
  cursor-addressed-repaint limitation, which HI themselves correctly dropped elsewhere.

### 6.3 Previous round, Rank 5: "combining marks are charged a column each" — **REFUTED**

The AR reporter flagged a disagreement with `RUNE_I18N_DOGFOOD.md` Rank 5 and declined to assert a
regression without seeing the earlier fixture. They were right to flag it, and they are correct.

Re-running the prior report's **exact fixture** on this build:

```
w_ascii  (x*100 + |END)             src_cps=104 src_cols=104 END_on_row=0
w_bare   (beh*100 + |END)           src_cps=104 src_cols=104 END_on_row=0
w_marks  ((beh+fatha)*100 + |END)   src_cps=204 src_cols=104 END_on_row=0   <- prior report: row 1
```

The prior report recorded `END` on **row 1** with row 0 holding 120 codepoints, and concluded *"a
line occupying 104 real columns is treated as 204 and split at codepoint 120."* On 0.9.0 the marked
fixture puts END on **row 0**, with row 0 carrying 204 codepoints in 104 columns. Arabic combining
marks are zero-width and the wrap point is correct.

The half of Rank 5 that **stands**: marks are *preserved* codepoint-exact
(`0x5b 0x65 0x301 0x5d 0x5b 0x628 0x64e 0x5d …`), which does contradict
`specs/parsers/parsers.spec.md:222-225`'s claim that a decomposed `é` renders as `e`. The spec is
still wrong about the direction of failure. The half that **falls**: the column charge.

The generalisation *"vocalised Arabic and Devanagari wrap at roughly half width"* was true of
Devanagari and false of Arabic, and the previous round did not separate them. This round did,
because an Arabic-speaking and a Hindi-speaking agent measured the same claim independently and
disagreed — which is exactly what the parallel-language design is for.

---

## 7. Measured clean — negative results worth not re-running

These cost most of the probe budget across six runs and all reproduce. Recording them so nobody
spends the budget again.

### 7.1 Cursors rune issues never land mid-character

Child emitting mixed 3- and 4-byte text (あ 日 ह ب н 😀) **one byte at a time** at 4 ms intervals, so
every character is guaranteed to straddle pty reads; polled every 50 ms, each returned cursor fed
straight back as `--since`:

```
samples=84  distinct_cursors=84  final_cursor=3410
chunks with U+FFFD: 0 / 84
joined U+FFFD=0  valid=true
cursors landing ON a continuation byte: 0
reassembled == full transcript prefix: true
```

With 3- and 4-byte sequences and arbitrary poll boundaries, most of 84 samples would have split a
character absent a decoder. Observing zero is not luck: `lib/rune/utf8_stream_decoder.rb` holds an
incomplete trailing sequence in `@pending` until it completes.

### 7.2 The write path is byte-exact for every script tested

Raw-mode child reporting byte count and SHA-256 of exactly what it received:

```
ASCII x2000      sent=2000 child_got=2000 sha_match=true EXACT
Japanese x700    sent=2100 child_got=2100 sha_match=true EXACT
Devanagari x500  sent=9000 child_got=9000 sha_match=true EXACT
Arabic x600      sent=6000 child_got=6000 sha_match=true EXACT
Mixed + emoji    sent=4500 child_got=4500 sha_match=true EXACT
```

Nothing rune writes is re-encoded, re-chunked or truncated — including 9 KB of Devanagari and 4-byte
emoji. The MAX_CANON ceiling is a cooked-mode tty limit, not a rune write bound.

### 7.3 The echo detector is script-neutral

Against a child that consumes input and prints nothing, so any match could only be the caller's own
echo:

```
ASCII      matched=false timed_out=true elapsed=7.19s
Japanese   matched=false timed_out=true elapsed=7.15s
Devanagari matched=false timed_out=true elapsed=7.20s
Arabic     matched=false timed_out=true elapsed=7.20s
```

No arm was ever handed its own words back. `Echo.condense` operates on characters, not bytes, and
`PRINTED = /[^\s\e]+/` is script-agnostic by construction. Corroborated independently by the ja, zh,
ko and ar runs.

Also confirmed clean across the six runs and spot-checked here: `--screen` column arithmetic for CJK
(including the wide-glyph straddle at the right margin) and for Cyrillic; `last_line` truncating by
characters rather than bytes; `--grep` with non-Latin patterns; round-tripping non-ASCII through a
non-repainting child.

---

## 8. The translations

### 8.1 Structural fidelity — verified mechanically, all six pass

| lang | lines | fences | blocks | blocks vs EN | heading levels | U+FFFD | valid UTF-8 |
|---|---|---|---|---|---|---|---|
| EN | 328 | 40 | 20 | — | — | 0 | true |
| ja | 352 | 40 | 20 | **identical** | identical | 0 | true |
| zh-CN | 322 | 40 | 20 | **identical** | identical | 0 | true |
| ko | 231 | 40 | 20 | **identical** | identical | 0 | true |
| ru | 330 | 40 | 20 | **identical** | identical | 0 | true |
| ar | 325 | 40 | 20 | **identical** | identical | 0 | true |
| hi | 240 | 40 | 20 | **identical** | identical | 0 | true |

All twenty code blocks are **byte-identical to the English in every one of the six files** — a
stricter result than the previous round, where two of nine had translated comment prose inside
fences. Every command, flag, path, JSON key and identifier is copy-pasteable unchanged.

### 8.2 One objective quality defect the self-reviews missed

The guide has exactly one intra-document anchor. Three files retargeted it to the translated
heading; **three left the English anchor pointing at a heading that no longer exists**:

| lang | anchor | resolves |
|---|---|---|
| zh-CN | `#用-rune-watch-实时观看会话` | yes |
| ko | `#rune-watch로-세션을-실시간으로-보기` | yes |
| ar | `#متابعة-الجلسة-حياً-عبر-rune-watch` | yes |
| **ja** | `#watching-a-session-live-with-rune-watch` | **no** |
| **ru** | `#watching-a-session-live-with-rune-watch` | **no** |
| **hi** | `#watching-a-session-live-with-rune-watch` | **no** |

Worth dwelling on: zh-CN, ko and ar each **reported catching and fixing this themselves**. ja, ru and
hi all delivered detailed native-speaker review passes — ru listed ten separate prose nits by line
number — and none of the three noticed a dead link. A structural check catches it in a second; a
prose review does not, because the anchor is invisible in rendered output until clicked. **If this
exercise is repeated, make anchor resolution a mechanical gate.**

### 8.3 Naturalness — what the native-speaker judgements actually say

These are self-assessments by the same agent that drove the translation, and I cannot independently
verify prose quality in six languages. What I can report is that they are **specific, falsifiable and
unanimous in direction**: all six judged the output genuinely idiomatic rather than translationese,
and every one of the six backed it with concrete evidence and then listed defects it found anyway.

The evidence offered is the kind that is hard to fake:

- **ru** — "solid and publishable… but there is recognisable translationese in about ten places",
  naming two genuine reader-ambiguities: «долгая сборка — не простой» (*downtime* colliding with
  *simple*) and «выводы» (*conclusions*) in a document that uses «вывод» for *output* throughout.
- **zh-CN** — the tell is that it "restructures rather than maps clause-for-clause": "PTY inception"
  → 「PTY 套娃」, the actual Chinese idiom for nesting, not a literal 「盗梦空间」.
- **ja** — 「黙って優先順位が適用されるのではなくエラーになります」 for "an error rather than a silent
  precedence", a genuinely hard construction.
- **ar** — verbal-sentence word order and idiomatic connectors (فـ / أما...فـ / إذ) "instead of the
  calqued و chains machine translation produces".
- **hi** — diagnosed its own draft's two failure modes: over-Sanskritised register no working
  developer speaks (वैश्विक → ग्लोबल, धारा → स्ट्रीम) and calque (लिपटी हुई कमांड for "wrapped
  command", which means cloth wrapped around something).
- **ko** — the English's long subordinate chains consistently broken into separate Korean sentences
  rather than transliterated in word order.

**The finding that matters for using an agent CLI as a translator:** every single run found at least
one substantive error requiring a native speaker, and three found the *same class* of error — a
mistranslation that structural checks cannot catch and that changes the meaning:

| lang | the phrase | what the agent produced | why it is wrong |
|---|---|---|---|
| ja | "do not diagnose quoting from it" | 「引用符の問題をこれから診断しないでください」 | "do not diagnose the quoting problem **from now on**" — loses "from *this field*" entirely |
| hi | "do not diagnose quoting from it" | कोटिंग | reads as "**coating**" |
| zh-CN | "library" | 「代码库」 | means *codebase/repository*, not a linkable library |
| hi | "not an exception" (the construct) | कोई अपवाद नहीं | reads as "no exception **to the rule**" — opposite emphasis |
| ko | `stdout가` / `stdin가` | wrong particle | 이/가 after consonant-final Latin words; 5 occurrences |

Three of six agents independently mangled the **same sentence** — the `command`-field warning from
`CLAUDE.md` — in three different languages. That sentence is doing subtle work ("it" = this field,
not quoting in general) and it is exactly where an LLM translator drops the referent.

So the honest summary: **the prose is better than machine-translation baseline and reads as native
technical writing, and it is not shippable without a native-speaker pass.** Both halves are the
finding. The structural gates (fences, code blocks, headings) passed 6/6 and caught none of the five
errors above; the anchor gate would have caught a sixth that no prose review found.

---

## 9. Harness errors

Collected because the failure modes repeat, and because in this round they twice came within one
control of producing a confident false finding.

**Mine, in this verification pass:**

1. **Read `output` where I should have read `screen`.** My first `--wait-for-regex` probe printed
   `--screen` rows still containing raw SGR escapes, which briefly looked like a rendering defect. The
   `read --screen` reply carries **both** `output` (raw transcript) and `screen` (rendered grid); I
   printed the wrong one. `ScreenRenderer` was correct all along. This is the repo's own documented
   error shape — reading a display-only field and diagnosing from it.
2. **Synthetic fixture padding drifted.** My first resync reproduction filled the 512 KB suffix by
   integer division and two of six arms landed the window cut in the wrong place (visible as
   `winOK=false`). The defect was real in the aligned arms, but I re-ran with exact byte arithmetic
   and an explicit `winOK` assertion rather than trusting the construction. Two prior runs (ru) made
   the same class of error three separate times on the same fixture.
3. **A literal U+0015 in a shell heredoc** was rejected by tool input validation. Moved the control
   byte into a Ruby source escape.

**Theirs, reported and worth propagating:**

4. **Shared-scratchpad contamination — twice, both nearly fatal.** The `ko` run globbed
   `<scratchpad>/*.json` to audit "every cursor rune issued", picked up 172 files belonging to other
   concurrent agents, and reported *"8 cursors land mid-character"* — a false finding it caught only
   by noticing filenames it had never written. Separately, `ko` read another agent's Kimi session (in
   Chinese) as its own grok session's `clean_output` after a generic `r1.json` filename was
   overwritten between write and read; it would have filed "a spectacular cross-session-leak bug
   against rune that does not exist." **Use a private, uniquely-named subdirectory.**
5. **One session reused across every case of a probe.** The `ja` run's first input-length probe
   shared one `cat` session; the Japanese overflow jammed it (§4.1), so all four later ASCII cases
   came back empty and the table read as *"Japanese input is dropped where ASCII survives."* A fresh
   session per case showed an identical byte boundary in both scripts. The `zh` run made the same
   error with a cumulative `--screen` buffer across four payloads and briefly concluded Arabic
   wrapped at 120 codepoints; re-run per-session, the opposite was true.
6. **Concluding "permanent" without trying the obvious control.** `ja` reported the jammed session
   "permanently mute" after only ever sending it more *text*. One control byte recovered it
   instantly. Corrected before filing.
7. **Sentinel matched the agent's own reasoning trace.** Both `ja` and `zh` had `--wait-for-regex`
   satisfied by the child *restating the instruction* ("User wants… then output `###ZHDONE###`"),
   not by the answer. Describing a sentinel rather than typing it defeats your own echo but not the
   agent's paraphrase. `ja` caught it only by reading the matched text instead of trusting
   `matched: true`.
8. **Sentinel reused across turns** — `hi`, which is what surfaced §5.2. The brief said pick a
   sentinel that cannot appear in your own *prompt*; it appeared in an earlier *reply*.
9. **Gutter width assumed constant.** `zh` stripped a fixed 3-column gutter when reconstructing a
   wrapped prompt from `--screen`; kimi uses 2 on the first row and 4 on continuations, producing a
   419-vs-417 mismatch read as *"rune dropped 2 characters of my input."*
10. **Nearly filing a documented limitation as new.** `hi`, `ru` and `ar` each almost reported
    `clean_output` collapsing inter-word spacing as a script-specific defect; the paired ASCII arm
    showed identical behaviour in every case. This is the cursor-addressed-repaint limitation.
11. **Blaming rune for the harness.** A 120 s Bash tool timeout SIGTERMing the client read as "rune
    hanging" (`ko`); a `ruby -e` fragment clobbering `set -- $pair` positionals produced five empty
    sends and five "rune failures" (`ja`); tool-sandbox refusals read as environment problems with
    rune (`ar`); `head -c 3000` on a `session read` truncating multi-byte output (`ja`), the exact
    mistake the repo's harness-error list already names twice.

The pattern across 4, 5, 9 and 11: **every one is a control the reporter had not run, not a subtlety
of rune.** The two that would have shipped as false findings were both caught by checking ground
truth on disk rather than trusting a returned field.

---

## 10. Housekeeping

All probe sessions started by this pass were stopped (14 created, 0 running at exit); everything
lived under `RUNE_HOME=/tmp/native-verify`. Probe scripts are in the session scratchpad at
`.../scratchpad/nverify/` (`resync2.rb`, `jam.rb`, `regex.rb`, `repaint.rb`, `cursor.rb`,
`input.rb`, `struct.rb`).

The six reporting agents stopped their own sessions and confined their writes to `docs/i18n/`.
`git status` shows the six translations plus the previous round's `RUNE_I18N_DOGFOOD.md` as
untracked, and the two pre-existing `lib`/`spec` modifications noted at the top, which are not mine.

**Recommended follow-ups, in order of how badly they bite:**

1. `ScreenRenderer.resync` — one-line fix (`byteindex` for `index`, or slice by characters), fabricates
   corruption on any >512 KB non-Latin transcript. §5.1
2. `--wait-for-regex` re-arming on repainted scrollback — silently returns "done" mid-turn. §5.2
3. The cooked-mode jam — document it and the U+0015 recovery at minimum; ideally surface the BELs
   rune already receives. §4.1
4. Add the Indic combining-mark ranges to `CharacterWidth::ZERO`. Data-only. §6.2
5. Correct `specs/parsers/parsers.spec.md:222-225`, still wrong in the direction the previous round
   identified, and now also wrong per §6.3.
6. Fix the session-name error message, or accept Unicode letters. §4.4
7. Make anchor resolution a mechanical gate on translated docs. §8.2
