# rune

> 本文档是 README.md 的简体中文翻译，英文原版为准。

[![CI](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml/badge.svg)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-3.0%20%E2%80%93%204.0-CC342D?logo=ruby&logoColor=white)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

一个 Ruby CLI 工具和库，从设计之初就以**人类与 AI 代理同为一等公民**为目标。

`rune` 是通用的伪终端（PTY）运行器和结构化数据桥梁，适用于任何 CLI 命令或交互式 TUI 应用。

每条命令都会为人类生成带格式、带颜色的终端输出，同时为 AI 代理生成结构化 JSON。
`rune watch` 还会在人类操作会话的同时写入实时 NDJSON 事件流。
同一个工具，同一组命令，双重接口。

`rune session` 更进一步：它让代理 CLI——`claude`、`grok`、`codex`——在多次独立调用之间保持
打开状态，这样一个代理就能以对话方式驱动另一个代理，而人类也可以接入同一会话并接管。

📖 初次使用？请从 **[入门指南](docs/getting_started.md)** 开始。

---

## 功能

1. **双重输出（人类 TTY / 代理 JSON 与 NDJSON）**
   - 终端模式：带格式的彩色输出（`rune version`）
   - 代理 JSON 模式：`--json` 或自动检测管道（`rune version | cat`）
   - 代理 NDJSON 模式：`--ndjson` 提供一致的结果封装（`rune version --ndjson`）
2. **通用 PTY 进程运行器（`rune run`）**
   - 在伪终端会话中启动任何 CLI 工具或 TUI
   - 自动剥离 ANSI 转义码、光标移动和控制序列
   - 禁用终端分页器（`PAGER=cat`），让查询立即返回而不挂起
   - 以毫秒为单位测量进程执行时长，并检测交互式提示
3. **结构化自动解析器（`Rune::Parsers`）**
   - `TableParser`：将以空格或竖线分隔的终端表格解析为哈希数组
   - `KeyValueParser`：将键值输出（`key: val`）解析为带类型的哈希
   - `TextSanitizer`：规范化换行符并清理 ANSI 转义码
4. **交互式脚本 DSL（`Rune::Script`）**
   - 用于驱动交互式终端提示和 TUI 菜单的逐步 TUI 脚本自动化 DSL
5. **实时交互透传（`rune watch`）**
   - 将你的终端置于原始模式，把按键逐字节实时转发给子进程
   - 把子进程的输出实时流式输出到你的屏幕（与 `rune run` 不同，后者会缓冲并在结束时一次性
     返回全部内容）
   - 同时将每个数据块作为 NDJSON 事件记录到临时文件（路径会公布一次，或用
     `--log=PATH` 指定），这样当人类在操作会话时，AI 代理可以实时跟踪该会话
6. **持久命名会话（`rune session`）**
   - 让 REPL 形态的子进程——`claude`、`grok`、`codex`、某个 shell——在多次独立的 `rune`
     调用之间保持打开，这是 `run`（缓冲后一次性返回）和 `watch`（随子进程一同退出）都
     做不到的
   - **发送并等待就绪（send-and-settle）**：写入输入，等待子进程安静下来，精确取回这次发送
     所产生的输出，把异步 TTY 变成同步的请求/响应调用
   - `--screen` 返回*渲染后的终端画面*而非原始字节流，这一点很重要，因为全屏代理会把自己的
     回答与它自己的重绘交错在一起——一份实测记录中，重绘流量从 361KB 降到了 1.1KB 的
     屏幕画面
   - `attach` 把活动会话交给人类终端，按 **Ctrl-]** 即可交还，会话仍在运行
   - 会话有名称、按项目划分作用域、可归档；记录文件在磁盘和内存中都有上限，因此会话即使
     运行一整天也不会无限增长

---

## 安装

不带限定名的 `rune` gem 名称在公开的 RubyGems.org 注册表上已被一个无关的包占用，因此在那里
执行 `gem install rune` 会安装错误的东西。请从 CorvidLabs 的 Homebrew tap 安装这个有维护、
带校验和锁定的 formula：

```sh
brew install corvidlabs/tap/rune
rune version --json
```

之后通过同一渠道升级到新版本：

```sh
brew upgrade corvidlabs/tap/rune
```

如需进行源码开发：

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

---

## 使用示例

### 0. 探索 CLI

```sh
rune --help              # every command, plus the global flags
rune run --help          # one command's usage and its own flags
rune help watch          # same thing, spelled the other way
```

帮助信息也是结构化的，因此代理无需抓取文本即可了解命令的功能面：

```sh
rune run --help --json | jq '.data | {usage, flags}'
```
```json
{
  "usage": "rune run [--timeout=SECONDS] [--max-output=BYTES] [--tail=N] [--separate-streams] [--] <command...>",
  "flags": [
    {
      "flag": "--timeout=SECONDS",
      "description": "Kill the wrapped command after N seconds (default 30). Before `--` only."
    },
    {
      "flag": "--max-output=BYTES",
      "description": "Bound clean_output/raw_output to BYTES each, keeping head+tail and marking the join with a `[rune] ==== N bytes omitted by --max-output ====` line. Mutually exclusive with --tail. Before `--` only."
    },
    {
      "flag": "--tail=N",
      "description": "Keep only the last N lines of clean_output/raw_output. Mutually exclusive with --max-output. Before `--` only."
    },
    {
      "flag": "--separate-streams",
      "description": "Adds clean_stdout/clean_stderr (stderr on a pipe, not the pty) alongside the merged view. Before `--` only."
    }
  ]
}
```

> **在被包装的命令之前使用 `--`。** 每个 rune 标志——`--json`、`--ndjson`、`--help`、
> `--timeout`、`--log`——只在第一个 `--` 之前被识别。正因如此，
> `rune run -- gh pr list --json number` 才能把 `--json` 传给 `gh` 而不是被 rune 自己消费。
> 没有这个分隔符，rune 会把标志据为己有，而被包装的命令将永远看不到它，且不会报错。

### 1. 在代理 JSON 模式下执行任何 CLI 命令
```sh
rune run --json -- git status
```
```json
{
  "status": "ok",
  "data": {
    "command": "git status",
    "exit_code": 0,
    "clean_output": "On branch main\nnothing to commit, working tree clean\n",
    "raw_output": "On branch main\r\nnothing to commit, working tree clean\r\n",
    "prompt_detected": false,
    "duration_ms": 21.05
  }
}
```

### 2. NDJSON 结果封装
```sh
rune run --ndjson -- fledge lanes run check
```
```json
{"event":"result","status":"ok","data":{"command":"fledge lanes run check","exit_code":0,"clean_output":"...","duration_ms":1652.8}}
```

`rune run --ndjson` 在命令结束时输出这一个封装。如需输出事件的实时流，请使用 `rune watch`。

### 3. 将表格形式的 CLI 输出解析为哈希
```ruby
require 'rune'

text = <<~TABLE
  NAME           STATUS   VERSION
  fledge-plugin  active   1.0.0
  rust-cli       ready    2.1.0
TABLE

parsed = Rune::Parsers::TableParser.parse(text)
# => [{ name: 'fledge-plugin', status: 'active', version: '1.0.0' }, ...]
```

### 4. 驱动交互式 TTY / TUI 应用
```ruby
require 'rune'

# Harness an interactive TUI program with input keystrokes
runner = Rune::PTYRunner.new("fledge plugins search --interactive", input: "\x03")
result = runner.run
# => Result with exit_code 130, clean_output, duration_ms
```

### 5. 实时查看会话（人类操作，代理跟踪）
```sh
# Puts your terminal in raw mode, forwards your keystrokes live — including
# raw escape sequences like arrow keys, not just whole lines — and streams
# output to your screen as it happens. Logs an NDJSON event per chunk to a
# temp file (announced once, up front) so an agent can `tail -f` it live
# without any JSON noise landing in your own terminal. The demo's top-level
# menu is a real arrow-key selector (↑/↓ + Enter, or q to quit).
rune watch -- ruby examples/humans/demo_tui.rb

# Or point the log somewhere specific:
rune watch --log=/tmp/session.ndjson -- ruby examples/humans/demo_tui.rb
```

在代理模式下——`--json`、`--ndjson`，或任何 stdout 不是终端的时候——实时透传会移到
**stderr**，这样 stdout 上只有结果封装。人类保留其实时视图；调用方程序则拿到干净的 JSON：

```sh
rune watch --json -- ruby examples/humans/demo_tui.rb 2>/dev/null | jq .data.log_path
```

### 6. 用一个代理 CLI 驱动另一个（`rune session`）

`run` 会缓冲并一次性返回；`watch` 需要有人坐在终端前，且随子进程结束而结束。两者都无法
在多次调用之间让一个代理 REPL 保持打开。`session` 可以：

```sh
# Start a named session. The child outlives this command.
rune session start --name reviewer -- grok

# Send a prompt and wait for the answer. --screen returns the rendered
# terminal, which is where the answer is actually legible.
rune session send --name reviewer --screen -- "Review lib/rune/session/supervisor.rb for races"

# Come back later — from another process, another agent, another hour.
rune session send --name reviewer --screen -- "Now just the highest-severity one, in one line"

rune session list          # what is running, how idle, what it last printed
rune session stop --name reviewer
```

**为什么用 `--screen` 而不是原始输出。** 全屏代理会持续重绘，因此字节流包含了每次重绘的
每一帧，回答被拆散在这些帧之间。针对 grok 的实测：一份 361KB 的记录渲染后只剩 1.1KB 的
屏幕画面；代理明确显示过的回答在 3 个回合里全部缺失于字节流，而在渲染画面中 3 个回合
全部存在。如果你要按内容匹配，就对 `screen` 匹配。

**亲自接管方向盘**，之后在不停止任何东西的情况下交还：

```sh
rune session attach --name reviewer   # Ctrl-] detaches; the session keeps running
```

会话以所在的 git 工作树为作用域，所以两个检出目录中的 `reviewer` 是两个会话。这是有意
为之，也是最常见的困惑来源——如果 `list` 什么都没显示，请检查你所在的目录和
`RUNE_HOME`：

```sh
rune session list --all-projects
```

**在长记录中查找某一处。** 驱动代理工作一天后记录可达 379KB，而当你想要的内容在中间时，
`--since` 和 `--tail` 都帮不上忙：

```sh
rune session read --name reviewer --grep 'THE BOARD' --context 2
```

📖 完整指南，包括 settle 调优和已知限制：
**[docs/sessions.md](docs/sessions.md)**。

---

## CorvidLabs 集成

`rune` 与 [CorvidLabs trust toolchain](https://github.com/CorvidLabs) 集成：

- **[fledge](https://github.com/CorvidLabs/fledge)** — 任务运行器与项目生命周期。`rune` 是通过 `plugin.toml` 定义的原生 `fledge` 插件。直接安装：
  ```sh
  fledge plugins install CorvidLabs/rune
  fledge rune run --json -- git status
  ```
- **[spec-sync](https://github.com/CorvidLabs/spec-sync)** — 契约执行（`specs/`）
- **[augur](https://github.com/CorvidLabs/augur)** — 变更风险评分

---

## 架构与内部实现

- 📖 **[入门指南](docs/getting_started.md)** — 输出模式、`rune run` 用法、超时和解析器，附真实命令输出。
- 📖 **[持久会话指南](docs/sessions.md)** — `rune session`：跨越单次调用而存在的命名 PTY 会话，以及用于从一个代理 CLI 驱动另一个的发送并等待就绪（send-and-settle）。
- 📖 **[伪终端（PTY）架构指南](docs/pty_architecture.md)** — 伪终端、非阻塞流读取、ANSI 净化、提示检测、脚本执行以及 `rune watch` 的实时双向透传在 Ruby 底层的实现原理。
- 📖 **[发布指南](docs/releasing.md)** — 版本同步、验证、来源证明、打标签和包发布。

---

## 开发与验证

```sh
fledge run test         # Run RSpec test suite (405 examples, 87% line coverage)
fledge run lint         # Run RuboCop linter (0 offenses)
fledge lanes run verify # Full CI gate (lint + tests + strict 100%-coverage spec-sync)
fledge lanes run release # Verify, smoke-test, and build the release gem
fledge run smoke-test   # Runnable, assertion-based tour of real behavior (examples/smoke_test.rb)
COVERAGE=1 bundle exec rspec  # Same suite, plus an HTML coverage report at coverage/index.html
```

`examples/smoke_test.rb` 是一个独立的、零依赖的脚本（无需 bundler/rspec），它针对真实的 CLI
二进制文件检验 `rune run`、`--timeout`、`TableParser`/`KeyValueParser`、`Script`、信号转发
和提示检测，输出通过/失败结果，并在失败时以非零状态退出。适合作为快速的人工健全性检查，
或在未安装开发依赖的机器上使用。

---

## 许可证

MIT
