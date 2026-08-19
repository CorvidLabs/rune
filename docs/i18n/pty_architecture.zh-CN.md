*本文档翻译自 `docs/pty_architecture.md`;如与英文原文不一致,以英文原文为准。*

# Rune 伪终端(PTY)与 TTY 架构

> **面向开发者与 AI 智能体的指南**  
> *了解 Ruby 如何在 `rune` 中管理伪终端、交互式流与提示符自动化。*

---

## 1. 概述:什么是伪终端(PTY)?

当程序运行在普通的子 shell 或子进程管道中时(例如通过 `IO.pipe`,或标准的子 shell 执行方式),操作系统会为 `stdin`、`stdout` 和 `stderr` 挂接标准管道。许多 CLI 程序(如 `git`、`docker`、`python`、`zsh`、`sudo`)会检测 `stdout` 是否是终端(使用 `isatty()`),如果不是,就会禁用颜色、提示符格式或行缓冲。

**伪终端(PTY)** 是内核层面的一对主、从虚拟终端设备:
- **从 PTY(Slave PTY)**:作为控制终端(`tty`)挂接到子进程上。子进程会认为自己正运行在一个真实终端中(比如 iTerm2 或 xterm)。
- **主 PTY(Master PTY)**:由 `rune`(`PTYRunner`)持有。`rune` 从主端描述符读取子进程的输出,并把键盘输入直接写入其中。

```
+------------------+         Master PTY          Slave PTY         +-------------------+
|  Rune PTYRunner  | <=======================> (Virtual Terminal) <==> |  Child Process    |
| (Agent / Human)  |    (reader / writer IO)                       | (bash, git, etc.) |
+------------------+                                               +-------------------+
```

---

## 2. 在 Ruby 中执行 PTY(`PTY.spawn`)

Ruby 标准库提供了 `require 'pty'`。`rune` 在 `lib/rune/pty_runner.rb` 内部使用 `PTY.spawn`:

```ruby
PTY.spawn(env, command) do |reader, writer, pid|
  # reader: IO object to read output from slave PTY
  # writer: IO object to write stdin into slave PTY
  # pid:    Process ID of child process
end
```

### 非阻塞式分块读取(`readpartial`)

标准的按行读取(`reader.each_line`)会一直阻塞,直到收到换行符(`\n`)为止。**交互式提示符**(例如 `Password: `、`Select option [y/N]`,或 `user@host:~$ `)**并不以换行符结尾**。如果用 `each_line` 读取,父进程会阻塞在等待 `\n` 上,而子进程却在等待用户输入——由此造成**死锁**。

为了消除死锁,`rune` 使用 `readpartial(4096)` 按块读取:

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

当子进程退出时,从 PTY 会关闭,`readpartial` 会抛出 `Errno::EIO` 或 `EOFError`,`rune` 捕获这些异常以干净地收尾。

---

## 3. ANSI 净化与双重输出(人类与智能体)

`rune` 会捕获原始的 ANSI 终端转义序列(颜色、光标移动、清屏等)。

- **面向人类(TTY 模式)**:原始输出通过 `Renderer.render_tty` 格式化,带有完整的颜色与交互式排版。
- **面向 AI 智能体(JSON 模式)**:输出会经过 `Parsers::TextSanitizer.strip_ansi(raw_output)` 处理以剥离 ANSI 码,返回干净文本以节省 LLM 的 token 消耗。这个等价关系只有在不带 `--max-output` 时才无条件成立:该参数会把两个字段各自独立地限制在同一预算内,于是二者描述的就成了这次运行中不同的窗口,`clean_output` 也就不再等于 `strip_ansi(raw_output)`:

```ruby
# Strips SGR ANSI color codes, cursor escape codes, and terminal controls
ANSI_REGEX = /\e\[[0-9;]*[a-zA-Z]/
clean_output = text.gsub(ANSI_REGEX, '')
```

---

## 4. 提示符检测逻辑(`Parsers::PromptDetector`)

为了判断一条命令是已经结束,还是正停在某个交互式提示符上,`Parsers::PromptDetector` 会对流式到来的行片段进行分析:

### 支持的提示符特征:
- Shell PS1 提示符:`user@host:~$ `、`bash-5.2# `、`➜  rune git:(main)`、`❯ `
- 菜单与交互式选择:`Select:`、`[y/N]`、`(y/n)?`、`Password: `

这份列表过去曾声称**不会**被检测到的两个特征,后来是被移除而不是被补进检测器里,
因为检测器的保守是刻意为之:`Select an option: `(该问句模式是锚定的,所以能匹配
`Select:`,却匹配不了一个以冒号结尾的普通句子)以及 `(venv) λ `(`λ` 不属于提示符
字形字符集,该字符集是 `➜ ❯ ›`)。

### 假阳性剔除:
`PromptDetector` 会忽略包含代码比较(`if x > 5`)或 shell 变量赋值(`export PATH=$PATH`)
的行。像 `> quote` 这样的 Markdown 引用块同样会被剔除,但原因是它匹配不到任何正向模式,
而不是被某条排除规则命中——引用块的排除规则只会在一行同时含有尖括号文本时才会触发。

---

## 5. 脚本自动化引擎(`Rune::Script`)

`rune` 允许定义交互式 DSL 脚本,用来自动化多步骤的 PTY 程序:

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

脚本引擎在单次非阻塞遍历中处理各个步骤,因此 `send_keys` 会立即写入 `writer`,无需等待后续的数据块。

---

## 6. 实时交互式透传(`PTYWatcher` / `rune watch`)

`PTYRunner` 会缓冲一条命令的全部输出,并在其结束后一次性返回:这对脚本化执行和输出捕获是正确的,但如果你想真正坐在键盘前驱动一个交互式程序、同时又有别的东西在观察这个会话,它就不合适了。`PTYWatcher`(`lib/rune/pty_watcher.rb`)是专门针对这种实时双向场景的独立类,而不是硬塞进 `PTYRunner` 里的一个模式——它的执行模型(raw 终端模式、后台输入转发线程)差异太大,放不进 `PTYRunner` 里,而且 `PTYRunner` “运行、捕获、一次性返回”的约定也需要保持冻结不变。

### Raw 终端模式(`io/console`)

要让方向键以及其他单字节/转义序列的输入能够送达子进程,*父*进程自身的控制终端就必须先离开 cooked 模式——在 cooked 模式下,内核会对输入做行缓冲,并在换行符到来之前本地回显按键。`io/console`(需要显式 `require`,`pty` 不会隐式引入它)提供了 `IO#raw`,`PTYWatcher#with_raw_input` 用它包裹住了整个转发会话:

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

`entered` 这个标志很关键:一旦 raw 模式真正生效,会话深处抛出的、与之无关的异常(比如某个输出汇坏掉了)就必须正常向上传播,而不能被当成“raw 模式不受支持”来处理,进而把整个已经启动的会话悄悄地再跑一遍。

### 双向转发

与 `PTYRunner` 的单一读取循环不同,`PTYWatcher` 会并发运行两件事:一个后台线程把人类的真实按键在到达的同时转发进子进程的 PTY(`forward_input`),而主线程则轮询子进程的输出并立即将其流式传给屏幕(`pump_output`),而不是把它累积到一个只在最后才返回的缓冲区里。

这两条路径都使用 `UTF8StreamDecoder` 来解码,它会在两次 `readpartial` 调用之间保留不完整的
UTF-8 尾部字节。因此,即便内核把一个合法的多字节字符拆到了不同的数据块里,该字符也能被
完整保留;而真正非法、或直到结束仍不完整的字节序列,依然会变成替换字符。

`PTYWatcher` 还会把控制终端当前的行列尺寸镜像到子进程的 PTY 上。它会在输出轮询循环中
重新检查这一尺寸,因此终端的尺寸变化能够送达子进程,而不需要在信号陷阱(signal trap)里
做不安全的操作。

```
+------------------+   keystrokes    +------------------+   output    +-------------------+
|  Human terminal  | --------------> |  PTYWatcher       | ----------> |  Real terminal      |
|  (raw mode)      |  (bg thread)    |  (master PTY)     |  (live)     |  screen + NDJSON log |
+------------------+                 +------------------+             +-------------------+
```

### NDJSON 事件日志

每一块送达屏幕的数据,同时也会作为一条 NDJSON 事件写入日志文件(默认是一个经过宣告、
且防冲突的 `0600` 权限临时文件,也可以用 `--log=PATH` 指定),这样 AI 智能体就可以对会话
执行 `tail -f` 实时跟踪,而不会有任何 JSON 噪声混进人类自己的终端里:

```json
{"event":"start","command":"...","pid":12345}
{"event":"output","bytes":42,"text":"..."}
{"event":"exit","exit_code":0}
```

默认不写入 stderr 是刻意为之:stderr 与实时透传共用人类的终端,而实际使用很快就证明,把 JSON 穿插进一个交互式会话里会让它完全没法读。

如果输出汇以 `EPIPE` 关闭,`PTYWatcher` 会先杀死并回收子进程,再返回一个
结构化的失败结果,防止一个脱离掌控的交互式进程在 watcher 结束后依然存活。

---

## 7. 错误处理与退出码

`PTYRunner` 和 `PTYWatcher` 都会在各种边缘情况下统一 Unix 退出码:

| 情况 | 退出码 | 处理方式 |
| :--- | :--- | :--- |
| 正常退出 | `status.exitstatus` | 干净地结束 |
| 命令未找到 | `127` | 捕获 `Errno::ENOENT` |
| 权限被拒绝 | `126` | 捕获 `Errno::EACCES` |
| 执行超时(仅 `PTYRunner`) | `124` | 捕获 `Timeout::Error`,然后向子进程发送 `SIGKILL` 并回收它——`Timeout.timeout` 只能中断 Ruby 自身的控制流,无法中断已经派生出去的操作系统进程 |
| 子进程被信号杀死 | `128 + sig` | 例如 `SIGKILL`(137)或 `SIGTERM`(143)之类的信号 |

---

## 面向开发者的总结

`rune` 综合运用了以下几点:
1. 用 `PTY.spawn` 实现真实的终端仿真。
2. 用 `readpartial` 实现零死锁的流式读取。
3. 用 `UTF8StreamDecoder` 搭配 `TextSanitizer`,生成边界安全、干净的智能体 JSON。
4. 用 `PromptDetector` 实现智能的交互状态检测。
5. 用 `Script` DSL 实现逐步的自动化输入。
6. 用 `PTYWatcher` 加上 `io/console` 的 raw 模式,实现实时、双向、由人驱动的会话,并附带一份可供智能体 `tail` 的 NDJSON 日志。
