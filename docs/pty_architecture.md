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
  chunk = reader.readpartial(4096)
  output_buffer << chunk
  on_output&.call(chunk) # Real-time streaming callback (NDJSON / TTY)
  
  # Check for prompts and process script automation steps immediately
  chunk.split("\n").each { |line| prompt_found = true if detect_prompt?(line) }
  script_step_index = process_script_steps(script_step_index, output_buffer, writer) if script
end
```

When the child process exits, the slave PTY closes, and `readpartial` raises `Errno::EIO` or `EOFError`, which `rune` catches to finish cleanly.

---

## 3. ANSI Sanitization & Dual Output (Human & Agent)

`rune` captures raw ANSI terminal escape sequences (colors, cursor movements, clear screens).

- **For Humans (TTY mode)**: Raw output is formatted using `Renderer.render_tty` with full color and interactive formatting.
- **For AI Agents (JSON mode)**: Output is processed through `Parsers::TextSanitizer.strip_ansi(raw_output)` to strip ANSI codes, returning clean text for LLM token efficiency:

```ruby
# Strips SGR ANSI color codes, cursor escape codes, and terminal controls
ANSI_REGEX = /\e\[[0-9;]*[a-zA-Z]/
clean_output = text.gsub(ANSI_REGEX, '')
```

---

## 4. Prompt Detection Logic (`Parsers::PromptDetector`)

To tell whether a command finished or is sitting at an interactive prompt, `Parsers::PromptDetector` analyzes streaming line fragments:

### Supported Prompt Signatures:
- Shell PS1 prompts: `user@host:~$ `, `bash-5.2# `, `(venv) λ `, `➜  rune git:(main)`
- Menu & interactive choices: `Select an option: `, `[y/N]`, `(y/n)?`, `Password: `

### False-Positive Rejection:
`PromptDetector` ignores lines containing code comparisons (`if x > 5`), markdown blockquotes (`> quote`), or shell variable assignments (`export PATH=$PATH`) to prevent false positives.

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

## 6. Error Handling & Exit Codes

`PTYRunner` standardizes Unix exit codes across edge cases:

| Condition | Exit Code | Handling |
| :--- | :--- | :--- |
| Normal Exit | `status.exitstatus` | Clean completion |
| Command Not Found | `127` | Rescues `Errno::ENOENT` |
| Permission Denied | `126` | Rescues `Errno::EACCES` |
| Execution Timeout | `124` | Rescues `Timeout::Error` after `timeout_seconds` |
| Child Killed (Signal) | `128 + sig` | Signals like `SIGKILL` (137) or `SIGTERM` (143) |

---

## Summary for Developers

`rune` combines:
1. `PTY.spawn` for real terminal emulation.
2. `readpartial` for zero-deadlock stream reading.
3. `TextSanitizer` for clean agent JSON.
4. `PromptDetector` for smart interactivity checks.
5. `Script` DSL for step-by-step automated input.
