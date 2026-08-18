이 문서는 docs/pty_architecture.md의 한국어 번역본이며, 원문인 영어판이 정본입니다.

# Rune Pseudo-TTY (PTY) 및 TTY 아키텍처

> **개발자 및 AI 에이전트를 위한 가이드**
> *`rune`에서 Ruby가 의사 터미널, 대화형 스트림, 프롬프트 자동화를 어떻게 관리하는지 이해합니다.*

---

## 1. 개요: Pseudo-TTY(PTY)란 무엇인가?

프로그램이 일반 서브셸이나 서브프로세스 파이프(예: `IO.pipe` 또는 표준 서브셸 실행)에서 실행되면, OS는 `stdin`, `stdout`, `stderr`에 표준 파이프를 연결합니다. 많은 CLI 프로그램(`git`, `docker`, `python`, `zsh`, `sudo` 등)은 `stdout`이 터미널인지 감지하고(`isatty()` 사용), 터미널이 아니면 색상, 프롬프트 서식, 라인 버퍼링을 비활성화합니다.

**Pseudo-TTY(PTY)**는 커널 수준의 마스터·슬레이브 가상 터미널 장치 쌍입니다:
- **Slave PTY**: 자식 프로세스의 제어 터미널(`tty`)로 연결됩니다. 자식 프로세스는 실제 터미널(iTerm2나 xterm 등) 안에서 실행 중이라고 인식합니다.
- **Master PTY**: `rune`(`PTYRunner`)이 소유합니다. `rune`은 자식 프로세스의 출력을 읽고 키보드 입력을 마스터 디스크립터에 직접 씁니다.

```
+------------------+         Master PTY          Slave PTY         +-------------------+
|  Rune PTYRunner  | <=======================> (Virtual Terminal) <==> |  Child Process    |
| (Agent / Human)  |    (reader / writer IO)                       | (bash, git, etc.) |
+------------------+                                               +-------------------+
```

---

## 2. Ruby에서의 PTY 실행 (`PTY.spawn`)

Ruby 표준 라이브러리는 `require 'pty'`를 제공합니다. `rune`은 `lib/rune/pty_runner.rb` 안에서 `PTY.spawn`을 사용합니다:

```ruby
PTY.spawn(env, command) do |reader, writer, pid|
  # reader: IO object to read output from slave PTY
  # writer: IO object to write stdin into slave PTY
  # pid:    Process ID of child process
end
```

### 논블로킹 청크 읽기 (`readpartial`)

표준 라인 읽기(`reader.each_line`)는 개행(`\n`)이 수신될 때까지 차단됩니다. **대화형 프롬프트**(`Password: `, `Select option [y/N]`, `user@host:~$ ` 등)는 **개행으로 끝나지 않습니다**. `each_line`으로 읽으면 부모 프로세스는 `\n`을 기다리며 차단되고, 자식 프로세스는 사용자 입력을 기다리며 멈춰 있어 **데드락**이 발생합니다.

데드락을 없애기 위해 `rune`은 `readpartial(4096)`으로 청크를 읽습니다:

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

자식 프로세스가 종료되면 슬레이브 PTY가 닫히고, `readpartial`이 `Errno::EIO` 또는 `EOFError`를 발생시키며, `rune`은 이를 잡아 깨끗하게 종료합니다.

---

## 3. ANSI 정제 및 이중 출력 (사람 및 에이전트)

`rune`은 원시 ANSI 터미널 이스케이프 시퀀스(색상, 커서 이동, 화면 지우기)를 캡처합니다.

- **사람용(TTY mode)**: 원시 출력을 `Renderer.render_tty`로 서식화하여 전체 색상과 대화형 서식을 적용합니다.
- **AI 에이전트용(JSON mode)**: 출력은 `Parsers::TextSanitizer.strip_ansi(raw_output)`을 거쳐 ANSI 코드를 제거하며, LLM 토큰 효율을 위한 깨끗한 텍스트를 반환합니다. 이 관계는 `--max-output`이 없을 때에만 무조건 성립합니다. 해당 플래그는 두 필드를 동일한 예산으로 각각 독립적으로 제한하므로, 그때는 실행의 서로 다른 구간을 기술하게 되고 `clean_output`은 `strip_ansi(raw_output)`이 아닙니다:

```ruby
# Strips SGR ANSI color codes, cursor escape codes, and terminal controls
ANSI_REGEX = /\e\[[0-9;]*[a-zA-Z]/
clean_output = text.gsub(ANSI_REGEX, '')
```

---

## 4. 프롬프트 감지 로직 (`Parsers::PromptDetector`)

명령이 끝났는지, 대화형 프롬프트에서 대기 중인지 구분하기 위해 `Parsers::PromptDetector`는 스트리밍되는 라인 조각을 분석합니다:

### 지원하는 프롬프트 시그니처:
- 셸 PS1 프롬프트: `user@host:~$ `, `bash-5.2# `, `➜  rune git:(main)`, `❯ `
- 메뉴 및 대화형 선택: `Select:`, `[y/N]`, `(y/n)?`, `Password: `

이 목록이 예전에 포함한다고 주장했던 시그니처 두 가지는 **감지되지 않으며**, 추가하는 대신 제거되었습니다. 감지기의 보수성은 의도적이기 때문입니다. `Select an option: `(질문 패턴이 앵커되어 있어 `Select:`에는 맞지만 콜론으로 끝나는 문장에는 맞지 않음)와 `(venv) λ `(`λ`는 프롬프트 글리프 클래스에 없으며, 해당 클래스는 `➜ ❯ ›`입니다).

### 오탐 거부:
`PromptDetector`는 코드 비교(`if x > 5`)나 셸 변수 할당(`export PATH=$PATH`)이 포함된 라인을 무시합니다. `> quote`와 같은 마크다운 인용문도 거부되지만, 제외 규칙이 아니라 긍정 패턴에 맞지 않기 때문입니다. 인용문 제외 규칙은 꺾쇠 괄호로 감싼 텍스트가 함께 있는 라인에서만 발동합니다.

---

## 5. 스크립트 자동화 엔진 (`Rune::Script`)

`rune`은 다단계 PTY 프로그램을 자동화하는 대화형 DSL 스크립트를 정의할 수 있습니다:

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

스크립트 엔진은 단계를 단 한 번의 논블로킹 패스로 처리하므로, `send_keys`는 이후 청크를 기다리지 않고 `writer`에 즉시 씁니다.

---

## 6. 실시간 대화형 패스스루 (`PTYWatcher` / `rune watch`)

`PTYRunner`는 명령의 전체 출력을 버퍼링하고 종료되면 반환합니다. 스크립팅과 캡처에는 맞지만, 실제로 키보드 앞에 앉아 대화형 프로그램을 조작하면서 다른 무언가가 세션을 관찰하는 경우에는 맞지 않습니다. `PTYWatcher`(`lib/rune/pty_watcher.rb`)는 그 실시간 양방향 경우를 위한 별도 클래스이며, `PTYRunner`에 덧붙인 모드가 아닙니다. 실행 모델(raw 터미널 모드, 백그라운드 입력 전달 스레드)이 그곳에 두기에는 충분히 다르고, `PTYRunner`의 "실행, 캡처, 한 번 반환" 계약은 그대로 고정됩니다.

### Raw 터미널 모드 (`io/console`)

화살표 키와 기타 단일 바이트/이스케이프 시퀀스 입력이 자식에 도달하려면, *부모* 프로세스 자신의 제어 터미널이 cooked 모드를 벗어나야 합니다. cooked 모드에서는 커널이 입력을 라인 버퍼링하고 개행이 올 때까지 키 입력을 로컬에서 에코합니다. `io/console`(`pty`가 암시적으로 끌어오는 것이 아니라 명시적으로 require됨)은 `IO#raw`를 추가하며, `PTYWatcher#with_raw_input`이 전체 전달 세션을 그것으로 감쌉니다:

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

`entered` 플래그가 중요합니다. raw 모드가 실제로 진입된 뒤에는, 세션 깊은 곳에서 발생한 무관한 예외(예: 깨진 출력 싱크)는 정상적으로 전파되어야 하며, "raw 모드가 지원되지 않음"으로 취급되어 이미 생성된 세션 전체를 조용히 한 번 더 다시 실행해서는 안 됩니다.

### 양방향 전달

`PTYRunner`의 단일 읽기 루프와 달리, `PTYWatcher`는 두 가지를 동시에 실행합니다. 백그라운드 스레드는 사람의 실제 키 입력이 도착하는 대로 자식의 PTY로 전달하고(`forward_input`), 메인 스레드는 자식의 출력을 폴링하여 버퍼에 모아 끝에만 반환하는 대신 화면에 즉시 스트리밍합니다(`pump_output`).

두 경로 모두 `UTF8StreamDecoder`로 디코드하며, 이 디코더는 `readpartial` 호출 사이에 불완전한 UTF-8 접미사를 유지합니다. 따라서 커널이 유효한 멀티바이트 문자를 청크에 걸쳐 나눠도 보존되며, 진짜 유효하지 않거나 마지막에 불완전한 시퀀스는 대체 문자가 됩니다.

`PTYWatcher`는 제어 터미널의 현재 행/열 크기도 자식 PTY에 그대로 반영합니다. 출력 폴링 루프 중에 다시 확인하므로, 크기가 바뀐 터미널이 시그널 트랩 안의 안전하지 않은 작업 없이 자식에 전달됩니다.

```
+------------------+   keystrokes    +------------------+   output    +-------------------+
|  Human terminal  | --------------> |  PTYWatcher       | ----------> |  Real terminal      |
|  (raw mode)      |  (bg thread)    |  (master PTY)     |  (live)     |  screen + NDJSON log |
+------------------+                 +------------------+             +-------------------+
```

### NDJSON 이벤트 로그

화면에 도달하는 모든 청크는 로그 파일에도 NDJSON 이벤트로 기록됩니다(기본적으로 공지되고 충돌에 안전한 `0600` 임시 파일이거나 `--log=PATH`). 따라서 AI 에이전트는 사람의 터미널에 JSON 노이즈가 섞이지 않은 채로 세션을 `tail -f`로 실시간 관찰할 수 있습니다:

```json
{"event":"start","command":"...","pid":12345}
{"event":"output","bytes":42,"text":"..."}
{"event":"exit","exit_code":0}
```

기본적으로 stderr를 쓰지 않는 것은 의도적입니다. stderr는 실시간 패스스루와 사람의 터미널을 공유하며, 실제 사용에서 JSON을 대화형 세션에 끼워 넣으면 읽기 어려워진다는 점이 바로 드러났습니다.

출력 싱크가 `EPIPE`로 닫히면, `PTYWatcher`는 구조화된 실패를 반환하기 전에 자식을 종료하고 reap하여, 분리된 대화형 프로세스가 watcher보다 오래 살아남지 못하게 합니다.

---

## 7. 오류 처리 및 종료 코드

`PTYRunner`와 `PTYWatcher` 모두 예외 상황에서 Unix 종료 코드를 표준화합니다:

| 조건 | 종료 코드 | 처리 |
| :--- | :--- | :--- |
| 정상 종료 | `status.exitstatus` | 정상 완료 |
| 명령을 찾을 수 없음 | `127` | `Errno::ENOENT`를 rescue함 |
| 권한 거부 | `126` | `Errno::EACCES`를 rescue함 |
| 실행 타임아웃 (`PTYRunner`만 해당) | `124` | `Timeout::Error`를 rescue한 뒤, 자식에 `SIGKILL`을 보내고 reap함. `Timeout.timeout`은 Ruby 자신의 제어 흐름만 중단하며, 생성된 OS 프로세스는 중단하지 않음 |
| 자식이 종료됨 (시그널) | `128 + sig` | `SIGKILL`(137) 또는 `SIGTERM`(143) 같은 시그널 |

---

## 개발자를 위한 요약

`rune`은 다음을 결합합니다:
1. 실제 터미널 에뮬레이션을 위한 `PTY.spawn`.
2. 데드락 없는 스트림 읽기를 위한 `readpartial`.
3. 경계에 안전하고 깨끗한 에이전트 JSON을 위한 `UTF8StreamDecoder`와 `TextSanitizer`.
4. 스마트한 대화형 확인을 위한 `PromptDetector`.
5. 단계별 자동 입력을 위한 `Script` DSL.
6. 에이전트가 `tail`할 수 있는 NDJSON 로그와 함께, 사람이 조작하는 실시간 양방향 세션을 위한 `PTYWatcher` + `io/console` raw 모드.
