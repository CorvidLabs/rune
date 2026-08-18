> 本文译自 docs/getting_started.md；如译文与原文存在出入，以英文原文为准。

# rune 快速上手

`rune` 是一个 Ruby CLI 与程序库，设计上让终端前的人类用户和以编程方式驱动它的 AI 代理
都能同样顺手地使用。每条命令都返回相同的结构化 `Result` —— 唯一随调用方式变化的只是
*渲染*形式。

## 安装

在公开的 RubyGems.org 注册表上，不带限定符的 `rune` 这个 gem 名称已被一个无关的包占用，
因此在那里执行 `gem install rune` 装到的是错误的东西。受支持的最终用户安装途径是
CorvidLabs Homebrew tap 中经过校验和锁定的 formula：

```sh
brew install corvidlabs/tap/rune
rune version --json
```

首次安装时 Homebrew 会自动添加该 tap。升级 rune 请使用：

```sh
brew upgrade corvidlabs/tap/rune
```

只有在开发 rune 本身时才克隆源码：

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

也可以作为 [fledge](https://github.com/CorvidLabs/fledge) 插件使用：

```sh
fledge plugins install CorvidLabs/rune
fledge rune run --json -- git status
```

## 了解有哪些功能可用

```sh
rune --help              # or -h, or `rune help`
rune run --help          # or `rune help run`, or `rune run -h`
```

命令帮助会列出该命令自己的 flag —— 例如 `rune run` 的 `--timeout=SECONDS`、`rune watch` 的
`--log=PATH` —— 同时也会列出全局 flag。帮助信息在代理模式下同样是结构化的，因此做功能
探查时无需解析面向人类的渲染结果：

```sh
$ rune run --help --json | jq -c '.data.flags'
[{"flag":"--timeout=SECONDS","description":"Kill the wrapped command after N seconds (default 30). Before `--` only."},{"flag":"--max-output=BYTES","description":"Bound clean_output/raw_output to BYTES each, keeping head+tail and marking the join with a `[rune] ==== N bytes omitted by --max-output ====` line. Mutually exclusive with --tail. Before `--` only."},{"flag":"--tail=N","description":"Keep only the last N lines of clean_output/raw_output. Mutually exclusive with --max-output. Before `--` only."},{"flag":"--separate-streams","description":"Adds clean_stdout/clean_stderr (stderr on a pipe, not the pty) alongside the merged view. Before `--` only."}]
```

帮助相关的 flag 遵循与其他一切内容相同的分隔符规则（见下文）：`rune run -- mytool --help`
会把 `--help` 传给 `mytool`。

## 三种输出模式

`rune` 会根据调用方式自动选择渲染模式，你也可以用 flag 显式指定一种。三种模式执行的
命令逻辑完全相同 —— 不同的只是输出格式。

### 1. 人类 TTY 模式（默认，交互式终端）

当 stdout 是真实终端且没有给出 `--json`/`--ndjson` flag 时，`rune` 会打印带颜色、面向
人类排版的输出：

```sh
$ rune version
rune v0.9.0
  Ruby 4.0.6 (arm64-darwin25)
  fledge:    ✓ available
  spec-sync: ✓ available
```

```sh
$ rune run -- echo "hello"
✓ echo hello (6.2ms, exit 0)

hello
```

### 2. 代理 JSON 模式（`--json`，或自动检测管道）

显式传入 `--json`，或者直接把 `rune` 的输出通过管道接走/重定向 —— 只要 stdout 不是
TTY，渲染就会自动切换为 JSON，无需任何 flag：

```sh
$ ruby bin/rune run --json -- echo "hello agent"
{"status":"ok","data":{"command":"echo hello\\ agent","exit_code":0,"clean_output":"hello agent\n","raw_output":"hello agent\r\n","prompt_detected":false,"duration_ms":5.27}}
```

```sh
$ ruby bin/rune version | cat
{"status":"ok","data":{"name":"rune","version":"0.7.0","ruby":"4.0.6","ruby_platform":"arm64-darwin25","fledge":true,"specsync":true}}
```

> **`exit_code` 是被包装进程的退出状态，而不是对所做工作的评判。** 它回答的是「进程是否
> 结束了、以何种方式结束」，而对于代理 CLI 来说这几乎总是 `0` —— 包括那些输出本身就
> 是错误的运行。曾有一位调用方连续八次 `rune run` 调用都返回 `0`，其中有几次得出的结论
> 他们后来不得不纠正。如果你需要知道*工作本身*是否成功，那只能从输出内容判断，而不能靠
> 这个字段。`124` 是值得记住的例外：它表示 rune 因 `--timeout` 杀掉了进程。

每个 JSON 响应都有相同的外层信封：`{"status": "ok"|"error", "data": {...}}`（失败时为
`{"status": "error", "error": "..."}`）。

无论成功还是失败，rune 都会把最终的信封写到 stdout。这让代理拥有了一条可解析的结果
通道，但同时也意味着：人类用户重定向 stdout 时，会把 rune 层面的错误信息也一并重定向
走。stderr 被保留给运行时的通告信息，以及绝不能污染结构化 stdout 的 `rune watch` 实时
透传。

全局输出 flag 只在第一个 `--` 分隔符之前被识别。分隔符之后的 token 属于被包装的命令，
会被原样保留，因此 `rune run -- tool --json` 会把 `--json` 传给 `tool`。

在 rune 自身 flag 所在的位置上出现一个 rune 不认识的 `--flag`，会被当作错误，而不是被
悄悄传递下去：`rune run --tiemout=5 -- echo hi` 在过去会真的去*执行*这个拼错的 flag，
并返回 `status: ok` 加 `exit_code: 127`。只有被包装命令之前的 token 会被检查，因此
`rune run cargo clippy --tests` 和 `rune run -- mytool --tiemout=5` 都不受影响 ——
一旦命令名已经出现，之后的每一个 `--flag` 都归属于它。

### 3. 代理 NDJSON 信封模式（`--ndjson`）

`--ndjson` 会把同一个结果包进 `{"event": "result"|"error", ...}` 信封，而不是 `--json` 所用
的普通 `{"status": ...}` 形状 —— 有些代理运行框架（harness）要求每条命令（包括
`rune run`）都统一使用这种格式：

```sh
$ ruby bin/rune run --ndjson -- echo "hello stream"
{"event":"result","status":"ok","data":{"command":"echo hello\\ stream","exit_code":0,"clean_output":"hello stream\n","raw_output":"hello stream\r\n","prompt_detected":false,"duration_ms":11.45}}
```

对 `rune run` 来说，这仍然只有一行，在命令结束时一次性输出 —— `PTYRunner` 会缓冲整个
运行过程并返回单个 `Result`，因此这里的 `--ndjson` 只是信封格式的选择，而不是增量流式
输出。如果你需要在长时间运行或交互式命令推进过程中获得真正实时的事件流，请参见下文的
[`rune watch`](#用-rune-watch-实时观看会话)，它会随着每个输出块的产生逐行
发出 NDJSON。

## 用 `rune run` 运行命令

`rune run` 会在一个真实的 PTY 中启动任意 CLI 命令或交互式 TUI，剥离 ANSI 转义序列、禁用
分页器，并测量执行耗时：

```sh
rune run -- git status
rune run --json -- npm test
rune run --ndjson -- fledge lanes run check
```

### 覆盖超时时间

每次 `rune run` 调用都有 30 秒的默认超时。用 `--timeout=SECONDS` 覆盖它，注意放在 `--`
分隔符*之前*，以免被误认为属于被包装命令的 flag：

```sh
$ ruby bin/rune run --json --timeout=1 -- sleep 3
{"status":"ok","data":{"command":"sleep 3","exit_code":124,"clean_output":"\n[rune] Execution timed out after 1 seconds","raw_output":"\n[rune] Execution timed out after 1 seconds","prompt_detected":false,"duration_ms":1005.32}}
```

超时的命令会返回退出码 `124`，并在捕获到的输出后附上 `[rune] Execution timed out after N
seconds` 消息 —— 它仍然是一个正常的 `Result`，而不是异常。

**在被杀掉之前捕获到的输出总是会被返回**，因此一个先打印了内容然后又卡住的子进程，你仍
能看到它打印了什么。如果输出是*空的*，那说明子进程确实什么都没打印，而 rune 会把这一点
连同最常见的原因一并告诉你。

**`rune run` 不会把它自己的 stdin 转发给子进程。** tty 属于人类用户 —— 接管它是
`rune watch` 的职责 —— 而转发管道会把调用方自己的输入经 pty 回显进 `clean_output`。
所以 `echo hi | rune run -- cat` 会超时：`cat` 在等一份永远不会到来的输入。正确的做法是
把重定向放进命令内部，让 shell 在 pty 里执行它：

```sh
$ rune run -- sh -c 'claude -p --output-format text < prompt.md'
```

这样是可行的，把多段落的提示词作为单个参数传入同样可行 —— 换行符能在 argv 中原样保
留。回复中的 `command` 字段是经过 shell 转义的*展示用*重建串，面向人类阅读，并不是子进
程实际收到的内容；不要拿它来诊断引号问题。

### 限制输出大小，以及拆分输出流

另外还有三个 flag，都位于 `--` 分隔符之前，都改变结果的*形状*：

- **`--max-output=BYTES`** 把 `clean_output` 和 `raw_output` 各自限制在 BYTES 字节以内，
  保留头部和尾部，并附上 `truncated: true` 与 `omitted_bytes`。从「各自」二字可以推出两
  点：这两个字段是*分别*限制的，因此在这个 flag 下它们描述的是同一次运行中不同的窗口，
  `clean_output` 并不等于 `strip_ansi(raw_output)` —— `omitted_bytes` 是 `clean_output`
  自己的计数，`raw_output` 则带着自己的标记和另一个不同的计数。而且 `omitted_bytes` 是
  按原始文本中的偏移量计量的，因此在纯 ASCII 下能精确对齐，但在多字节文本上会漂移几个
  字节 —— 因为截断点可能把一个字符切开。前后两半之间用一行
  `[rune] ==== N bytes omitted by --max-output ====` 连接，而不是直接拼接，这样返回的文
  本绝不会被读成命令自己打印的内容：如果没有这一行，一份 201 字节的会话记录在
  `--max-output=200` 下恰好丢掉的那一个字节，会把 `chsh -s /bin/zsh` 变成
  `chsh -s bin/zsh`。该标记是 rune 加的注解而非命令的输出，所以它不占 BYTES 额度，一次
  回复因此可能略微超出预算。
- **`--tail=N`** 只保留最后 N 行，并附上 `truncated: true` 与 `omitted_lines`。与
  `--max-output` 互斥；两个都传会报错，而不是静默地按某种优先级取其一。
- **`--separate-streams`** 在合并视图 `clean_output` 之外，额外增加 `clean_stdout` 和
  `clean_stderr`，而不是替换掉合并视图。

`--separate-streams` 有真实的代价，这也是它作为可选项而非默认行为的原因：pty 只有一条
流，要拆分它们就得给 stderr 单独配一根管道。这样一来，子进程看到的就不再是两条流共用
同一个控制终端，一个会检查 `isatty(2)` 的程序会表现得好像自己的错误输出被重定向了 ——
对许多 CLI 来说，这意味着丢弃颜色，或者干脆切换到非交互模式。当你对流拆分的需要超过对
「让子进程相信自己在终端上」的需要时，再使用它。

## 用 `rune watch` 实时观看会话

`rune run` 会缓冲命令的全部输出，直到命令结束才返回 —— 这对脚本化和捕获很合适，但如果你
想真正坐在键盘前驱动一个交互式程序、同时让别的东西观察这个会话，它就不行了。`rune watch`
正是为此而生：它把你的终端置于原始模式（raw mode），把你敲下的每一次按键实时转发给子进
程 —— 包括方向键这类原始转义序列，而不仅仅是整行输入 —— 把子进程的输出随产生随显示
到你的屏幕上（而不是等到最后），并同时把每一个输出块记录为一条 NDJSON 事件 —— 这样在
人类驱动会话的同时，AI 代理可以实时跟踪它。

```sh
# A small interactive demo program ships with rune specifically to try this against:
rune watch -- ruby examples/humans/demo_tui.rb
```

事件日志默认写入一个防冲突、仅所有者可读（`0600`）的临时文件，而不是 stderr —— 把
NDJSON 事件混进与实时透传相同的终端里曾是最初的设计，而实际使用立刻证明了那是个错误的
默认值（交错出现的 JSON 让会话根本没法读）。日志路径会在开始时声明一次：

```
[rune watch] live event log: /tmp/rune-watch-20260728-12345-abcd.ndjson
```

在另一个窗格里对该路径执行 `tail -f`（或者让一个代理去跟踪它），就能实时观看会话，而你
自己的终端保持干净。也可以用 `--log=PATH` 把日志指到某个特定位置：

```sh
rune watch --log=/tmp/session.ndjson -- ruby examples/humans/demo_tui.rb
```

日志的每一行都是一个 JSON 对象：先是 `{"event":"start","command":"...","pid":...}`，
然后是随输出流产生的每个块各一条 `{"event":"output","bytes":N,"text":"..."}`，最后是
子进程退出时的 `{"event":"exit","exit_code":N}`。

### 代理模式下的 `rune watch`

`rune watch` 遵循与其他所有命令相同的输出模式规则。在 `--json`、`--ndjson` 下，或者
stdout 不是终端的任何情况下，实时透传会转移到 **stderr**，stdout 只承载结果信封 —— 这
样外层的包装程序可以直接解析 stdout，而键盘前的人类仍然能看到自己的会话：

```sh
rune watch --json -- ruby examples/humans/demo_tui.rb 2>/dev/null | jq .
```

```json
{
  "status": "ok",
  "data": {
    "command": "ruby examples/humans/demo_tui.rb",
    "exit_code": 0,
    "duration_ms": 4820.11,
    "log_path": "/tmp/rune-watch-20260728-12345-abcd.ndjson"
  }
}
```

去掉 `2>/dev/null`，你就可以在 JSON 被捕获到别处的同时继续自己观看会话。

`rune watch` 要求真实的终端（如果 stdin 不是 TTY 它会拒绝运行 —— 不存在有意义的非交
互模式），而且无法在 `rune run` 自己的 PTY 套娃中工作，所以它不能像本指南其余部分那样
用管道示例来演示。`examples/humans/demo_tui.rb` 的顶层菜单是一个真正的方向键选择器（↑/↓
加 Enter，或按 `q` 退出），而不是「输入数字再按回车」那种 —— 这是专门为了检验原始单字
节和转义序列转发而设计的，那是纯行缓冲菜单永远触碰不到的东西。`examples/humans/demo_tui.rb`
文件头部的注释里有可以直接复制粘贴的命令，`spec/rune/pty_watcher_spec.rb` 则展示了底层
转发/记录机制是如何做单元测试的，其中包括一个端到端驱动方向键菜单本身的测试（用一个假
终端对象加 `IO.pipe` 来驱动一个真实的交互式子进程，无需真正的控制终端）。


### 限制 watch 的时长

两个相互独立的限制，都在 `--` 分隔符之前，默认都关闭：

- **`--timeout=SECONDS`** 在墙上时钟走过 N 秒后杀掉会话，无论会话有多忙。
- **`--idle-timeout=SECONDS`** 在**既没有输出也没有输入**持续 N 秒后杀掉会话 —— 这才是
  你想要的「这个代理已经什么都不做了」的判定，因为一场漫长的构建并不算空闲。

两者都会给出退出码 `124`，并附带 `timed_out: true` 和值为 `"timeout"` 或 `"idle_timeout"`
的 `timeout_kind`，表明触发的是哪一个。

## 解析结构化文本

`Rune::Parsers::TableParser` 和 `Rune::Parsers::KeyValueParser` 能把非结构化的终端输出转换
为 Ruby 哈希：

```ruby
require 'rune'

Rune::Parsers::TableParser.parse(<<~TABLE)
  NAME           STATUS   VERSION
  fledge-plugin  active   1.0.0
TABLE
# => [{ name: 'fledge-plugin', status: 'active', version: '1.0.0' }]
```

`TableParser.parse` 接受一个 `format:` 关键字参数（默认为 `:auto`，也可用 `:pipe`/`:space`
强制指定解析模式）—— 在对不熟悉的输出依赖 `:auto` 之前，请先查阅
[`specs/parsers/parsers.spec.md`](../specs/parsers/parsers.spec.md) 中关于该启发式方法已
知局限的说明。

## 下一步

- [`examples/smoke_test.rb`](../examples/smoke_test.rb) —— 运行 `ruby examples/smoke_test.rb`
  或 `fledge run smoke-test`。一场独立的、基于断言的真实行为之旅（无需 bundler/rspec）：
  输出模式、`--timeout` 校验、解析器、`Script`、信号转发、提示符检测。
- [`examples/humans/demo_tui.rb`](../examples/humans/demo_tui.rb) —— 上文 `rune watch`
  一节贯穿使用的交互式演示程序。[`examples/agents/pty_runner_example.rb`](../examples/agents/pty_runner_example.rb)、
  [`table_parser_example.rb`](../examples/agents/table_parser_example.rb) 和
  [`script_automation_example.rb`](../examples/agents/script_automation_example.rb) 是更小
  的单一概念脚本 —— 每个都可以直接运行（`ruby examples/agents/<name>.rb`），除了
  `require_relative '../lib/rune'` 之外无需任何准备。
- [PTY 架构指南](pty_architecture.md) —— PTY 运行器、流读取、提示符检测以及
  `rune watch` 实时透传的内部工作原理。
- [`specs/`](../specs/) —— `cli`、`parsers`、`pty_runner`、`session`、`watch` 各模块的
  机器校验契约（`spec-sync`）。
- [`AGENTS.md`](../AGENTS.md) —— 添加新命令以及配合信任工具链工作的约定。
