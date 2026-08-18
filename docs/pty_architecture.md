# Rune Pseudo-TTY (PTY) & TTY Architecture

> **Guide for Developers & AI Agents**  
> *Understanding how Ruby manages pseudo-terminals, interactive streams, and prompt automation in `rune`.*

---

## 1. Overview: What is a Pseudo-TTY (PTY)?

When a program runs in a normal subshell or subprocess pipe (e.g. `IO.pipe` or standard subshell execution), the OS attaches standard pipes for `stdin`, `stdout`, and `stderr`. Many CLI programs (like `git`, `docker`, `python`, `zsh`, `sudo`) detect if `stdout` is a terminal (using `isatty()`) and disable colors, prompt formatting, or line buffering if it is not.

A **Pseudo-TTY (PTY)** is a kernel-level pair of master and slave virtual terminal devices:
- **Slave PTY**: Attached to the child process as its controlling terminal (`tty`). The child process believes it is running inside a real terminal (like iTerm2 or xterm).
- **Master PTY**: Owned by `rune` (`PTYRunner`). `rune` reads the child process output and writes keyboard input directly into the master descriptor.

```
+------------------+         Master PTY          Slave PTY         +-------------------+
|  Rune PTYRunner  | <=======================> (Virtual Terminal) <==> |  Child Process    |
| (Agent / Human)  |    (reader / writer IO)                       | (bash, git, etc.) |
+------------------+                                               +-------------------+
```

---

## 2. PTY Execution in Ruby (`PTY.spawn`)

Ruby's standard library provides `require 'pty'`. `rune` uses `PTY.spawn` inside `lib/rune/pty_runner.rb`:

```ruby
PTY.spawn(env, command) do |reader, writer, pid|
  # reader: IO object to read output from slave PTY
  # writer: IO object to write stdin into slave PTY
  # pid:    Process ID of child process
end
```

### Non-Blocking Chunk Reading (`readpartial`)

Standard line reading (`reader.each_line`) blocks until a newline (`\n`) is received. **Interactive prompts** (such as `Password: `, `Select option [y/N]`, or `user@host:~$ `) **do not end with a newline**. If you read with `each_line`, the parent process blocks waiting for `\n`, while the child process sits waiting for user input—causing a **deadlock**.

To eliminate deadlocks, `rune` reads chunks using `readpartial(4096)`:

```ruby
loop do
  # Bounded wait rather than a bare readpartial, so signals and the timeout
  # are still serviced while the child is quiet.
  next unless reader.wait_readable(0.2)

  chunk = reader.readpartial(4096)
  output_buffer << chunk
  on_output&.call(chunk) # Real-time streaming callback (NDJSON / TTY)
  script_step_index = process_script_steps(script_step_index, output_buffer, writer) if script
end

# prompt_detected is computed once at the end, from the LAST non-blank line
# only — not "did any line ever look like a prompt". A run that printed a
# prompt and then kept going is not waiting for input, so the any-line form
# answered a question nobody was asking.
prompt_detected = detect_prompt?(output_buffer.lines.reverse.find { |line| !line.strip.empty? })
```

When the child process exits, the slave PTY closes, and `readpartial` raises `Errno::EIO` or `EOFError`, which `rune` catches to finish cleanly.

---

## 3. ANSI Sanitization & Dual Output (Human & Agent)

`rune` captures raw ANSI terminal escape sequences (colors, cursor movements, clear screens).

- **For Humans (TTY mode)**: Raw output is formatted using `Renderer.render_tty` with full color and interactive formatting.
- **For AI Agents (JSON mode)**: Output is processed through `Parsers::TextSanitizer.strip_ansi(raw_output)` to strip ANSI codes, returning clean text for LLM token efficiency. This holds unqualified only without `--max-output`: that flag bounds the two fields independently to the same budget, so they then describe different windows of the run and `clean_output` is not `strip_ansi(raw_output)`:

```ruby
# Strips SGR ANSI color codes, cursor escape codes, and terminal controls
ANSI_REGEX = /\e\[[0-9;]*[a-zA-Z]/
clean_output = text.gsub(ANSI_REGEX, '')
```

---

## 4. Prompt Detection Logic (`Parsers::PromptDetector`)

To tell whether a command finished or is sitting at an interactive prompt, `Parsers::PromptDetector` analyzes streaming line fragments:

### Supported Prompt Signatures:
- Shell PS1 prompts: `user@host:~$ `, `bash-5.2# `, `➜  rune git:(main)`, `❯ `
- Menu & interactive choices: `Select:`, `[y/N]`, `(y/n)?`, `Password: `

Two signatures this list used to claim are **not** detected, and were removed rather than added,
because the detector's conservatism is deliberate: `Select an option: ` (the question pattern is
anchored, so it matches `Select:` but not a sentence ending in a colon) and `(venv) λ ` (`λ` is not
in the prompt-glyph class, which is `➜ ❯ ›`).

### False-Positive Rejection:
`PromptDetector` ignores lines containing code comparisons (`if x > 5`) or shell variable
assignments (`export PATH=$PATH`). A markdown blockquote such as `> quote` is also rejected, but by
matching no positive pattern rather than by an exclusion — the blockquote exclusion only fires on a
line that also contains angle-bracketed text.

---

## 5. Script Automation Engine (`Rune::Script`)

`rune` allows defining interactive DSL scripts to automate multi-step PTY programs:

```ruby
script = Rune::Script.define do
  wait_for(/Select a target environment/)
  send_keys "production\n"
  pause 0.5
  wait_for(/Are you sure\? \[y\/N\]/)
  send_keys "y\n"
end

Rune::PTYRunner.new('deploy-tool', script: script).run
```

The script engine processes steps in a single non-blocking pass so `send_keys` writes immediately to `writer` without waiting for subsequent chunks.

---

## 6. Live Interactive Passthrough (`PTYWatcher` / `rune watch`)

`PTYRunner` buffers a command's entire output and returns once it finishes: correct for scripting and capture, but wrong for actually sitting at the keyboard and driving an interactive program while something else observes the session. `PTYWatcher` (`lib/rune/pty_watcher.rb`) is a separate class for that live, bidirectional case rather than a mode bolted onto `PTYRunner` — the execution model (raw terminal mode, a background input-forwarding thread) is different enough not to belong there, and `PTYRunner`'s "run, capture, return once" contract stays frozen.

### Raw terminal mode (`io/console`)

For arrow keys and other single-byte/escape-sequence input to reach the child at all, the *parent* process's own controlling terminal has to leave cooked mode, where the kernel line-buffers input and locally echoes keystrokes until a newline arrives. `io/console` (required explicitly, not implicitly pulled in by `pty`) adds `IO#raw`, which `PTYWatcher#with_raw_input` wraps around the whole forwarding session:

```ruby
def with_raw_input(&block)
  entered = false
  @input.raw do
    entered = true
    block.call
  end
rescue Errno::ENOTTY, NoMethodError
  raise if entered   # only fall back if raw-mode *entry* itself failed

  block.call
end
```

The `entered` flag matters: once raw mode is genuinely engaged, an unrelated exception from deep inside the session (a broken output sink, say) must propagate normally, not get treated as "raw mode isn't supported" and silently re-run the whole already-spawned session a second time.

### Bidirectional forwarding

Unlike `PTYRunner`'s single read loop, `PTYWatcher` runs two things concurrently: a background thread forwards the human's real keystrokes into the child's PTY as they arrive (`forward_input`), while the main thread polls the child's output and streams it to the screen immediately (`pump_output`), rather than accumulating it into a buffer returned only at the end.

Both paths decode with `UTF8StreamDecoder`, which retains an incomplete UTF-8 suffix between
`readpartial` calls. A valid multi-byte character is therefore preserved even when the kernel
splits it across chunks; genuinely invalid or final incomplete sequences still become replacement
characters.

`PTYWatcher` also mirrors the controlling terminal's current row/column size onto the child PTY.
It rechecks during the output poll loop, so a resized terminal reaches the child without unsafe
work inside a signal trap.

```
+------------------+   keystrokes    +------------------+   output    +-------------------+
|  Human terminal  | --------------> |  PTYWatcher       | ----------> |  Real terminal      |
|  (raw mode)      |  (bg thread)    |  (master PTY)     |  (live)     |  screen + NDJSON log |
+------------------+                 +------------------+             +-------------------+
```

### NDJSON event log

Every chunk that reaches the screen is also written as an NDJSON event to a log file (an announced,
collision-safe `0600` temp file by default, or `--log=PATH`), so an AI agent can `tail -f` the
session live without any JSON noise landing in the human's own terminal:

```json
{"event":"start","command":"...","pid":12345}
{"event":"output","bytes":42,"text":"..."}
{"event":"exit","exit_code":0}
```

Deliberately not stderr by default: stderr shares the human's terminal with the live passthrough, and real usage immediately showed that interleaving JSON into an interactive session made it unreadable.

If the output sink closes with `EPIPE`, `PTYWatcher` kills and reaps the child before returning a
structured failure, preventing a detached interactive process from surviving the watcher.

---

## 7. Error Handling & Exit Codes

Both `PTYRunner` and `PTYWatcher` standardize Unix exit codes across edge cases:

| Condition | Exit Code | Handling |
| :--- | :--- | :--- |
| Normal Exit | `status.exitstatus` | Clean completion |
| Command Not Found | `127` | Rescues `Errno::ENOENT` |
| Permission Denied | `126` | Rescues `Errno::EACCES` |
| Execution Timeout (`PTYRunner` only) | `124` | Rescues `Timeout::Error`, then `SIGKILL`s and reaps the child — `Timeout.timeout` only interrupts Ruby's own control flow, not the spawned OS process |
| Child Killed (Signal) | `128 + sig` | Signals like `SIGKILL` (137) or `SIGTERM` (143) |

---

## Summary for Developers

`rune` combines:
1. `PTY.spawn` for real terminal emulation.
2. `readpartial` for zero-deadlock stream reading.
3. `UTF8StreamDecoder` plus `TextSanitizer` for boundary-safe, clean agent JSON.
4. `PromptDetector` for smart interactivity checks.
5. `Script` DSL for step-by-step automated input.
6. `PTYWatcher` + `io/console` raw mode for live, bidirectional human-driven sessions with an agent-tailable NDJSON log.
