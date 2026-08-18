이 문서는 README.md의 한국어 번역이며, 영어 원본이 권위 있는 기준입니다.

# rune

[![CI](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml/badge.svg)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-3.0%20%E2%80%93%204.0-CC342D?logo=ruby&logoColor=white)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

처음부터 **인간과 AI 에이전트를 일급으로** 다루도록 설계된 Ruby CLI 도구이자 라이브러리입니다.

`rune`은 모든 CLI 명령이나 대화형 TUI 애플리케이션을 위한 범용 의사 터미널(PTY) 러너이자 구조화 데이터 브리지입니다.

모든 명령은 사람을 위한 서식 있는 컬러 터미널 출력과 AI
에이전트를 위한 구조화된 JSON을 생성합니다. `rune watch`는 추가로, 사람이 세션을
조작하는 동안 실시간 NDJSON 이벤트 스트림을 기록합니다. 같은 도구, 같은 명령, 이중 인터페이스입니다.

`rune session`은 한 걸음 더 나아갑니다. `claude`, `grok`, `codex`와 같은 에이전트 CLI를
서로 다른 호출에 걸쳐 열어 두므로, 한 에이전트가 다른 에이전트를 대화로 구동할 수 있고 사람이 같은 세션에 연결해
이어받을 수 있습니다.

📖 처음이신가요? **[시작 가이드](docs/getting_started.md)**부터 보세요.

---

## 기능

1. **이중 출력 (사람 TTY / 에이전트 JSON & NDJSON)**
   - 터미널 모드: 서식 있는 컬러 출력 (`rune version`)
   - 에이전트 JSON 모드: `--json` 또는 자동 파이프 감지 (`rune version | cat`)
   - 에이전트 NDJSON 모드: 일관된 결과 엔벨로프를 위한 `--ndjson` (`rune version --ndjson`)
2. **범용 PTY 프로세스 러너 (`rune run`)**
   - 모든 CLI 도구나 TUI를 의사 터미널 세션 안에서 실행합니다
   - ANSI 이스케이프 코드, 커서 이동, 제어 시퀀스를 자동으로 제거합니다
   - 터미널 페이저를 비활성화하여 (`PAGER=cat`) 쿼리가 멈추지 않고 즉시 반환되게 합니다
   - 프로세스 실행 시간을 밀리초 단위로 측정하고 대화형 프롬프트를 감지합니다
3. **구조화 자동 파서 (`Rune::Parsers`)**
   - `TableParser`: 공백 또는 파이프로 구분된 터미널 테이블을 해시 배열로 파싱합니다
   - `KeyValueParser`: 키-값 출력(`key: val`)을 타입이 지정된 해시로 파싱합니다
   - `TextSanitizer`: 줄 바꿈을 정규화하고 ANSI 이스케이프 코드를 정리합니다
4. **대화형 스크립트 DSL (`Rune::Script`)**
   - 대화형 터미널 프롬프트와 TUI 메뉴를 구동하기 위한 단계별 TUI 스크립트 자동화 DSL
5. **실시간 대화형 패스스루 (`rune watch`)**
   - 터미널을 raw 모드로 전환하고 키 입력을 자식 프로세스에 실시간으로, 바이트 단위로 전달합니다
   - 자식의 출력을 발생하는 즉시 화면에 스트리밍합니다 (`rune run`처럼 버퍼링한 뒤
     마지막에 모두 반환하지 않음)
   - 동시에 모든 청크를 NDJSON 이벤트로 임시 파일에 기록합니다 (경로는 한 번 안내되거나
     `--log=PATH`). 사람이 세션을 조작하는 동안 AI 에이전트가 실시간으로 tail할 수 있습니다
6. **지속되는 이름 있는 세션 (`rune session`)**
   - `claude`, `grok`, `codex`, 셸과 같은 REPL 형태의 자식 프로세스를 서로 다른 `rune`
     호출에 *걸쳐* 열어 둡니다. `run`(버퍼링한 뒤 한 번 반환)도 `watch`(자식과 함께 종료)도
     할 수 없는 일입니다
   - **Send-and-settle**: 입력을 쓰고, 자식이 조용해질 때까지 기다린 다음, 그 send가 만들어 낸
     출력만 정확히 돌려받아, 비동기 TTY를 동기 request/response 호출로 바꿉니다
   - `--screen`은 raw 바이트 스트림이 아니라 *렌더링된 터미널*을 반환합니다. 전체 화면 에이전트가
     자신의 답변을 자체 다시 그리기와 섞어 넣기 때문에 중요합니다. 측정된 한 트랜스크립트는
     361KB의 다시 그리기 트래픽에서 1.1KB 화면으로 줄었습니다
   - `attach`는 살아 있는 세션을 사람 터미널에 넘기고, **Ctrl-]**로 돌려줍니다. 세션은 계속 실행 중입니다
   - 세션은 이름이 있고, 프로젝트 범위이며, 아카이브할 수 있습니다. 트랜스크립트는 디스크와
     메모리에서 크기가 제한되므로, 하루 동안 켜 둔 세션이 한없이 커지지 않습니다

---

## 설치

한정되지 않은 `rune` gem 이름은 공개 RubyGems.org 레지스트리에서 관련 없는
패키지가 이미 사용 중이므로, 거기서 `gem install rune`을 실행하면 잘못된 것이 설치됩니다. CorvidLabs Homebrew tap에서 유지 관리되고
체크섬이 고정된 formula를 설치하세요:

```sh
brew install corvidlabs/tap/rune
rune version --json
```

이후 릴리스는 같은 채널로 업그레이드합니다:

```sh
brew upgrade corvidlabs/tap/rune
```

소스 개발용:

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

---

## 사용 예제

### 0. CLI 살펴보기

```sh
rune --help              # every command, plus the global flags
rune run --help          # one command's usage and its own flags
rune help watch          # same thing, spelled the other way
```

도움말도 구조화되어 있으므로, 에이전트가 텍스트를 스크래핑하지 않고도 표면을 파악할 수 있습니다:

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

> **래핑된 명령 앞에 `--`를 쓰세요.** 모든 rune 플래그 — `--json`, `--ndjson`, `--help`,
> `--timeout`, `--log` — 는 첫 번째 `--` *앞에서만* 인식됩니다. 그래서
> `rune run -- gh pr list --json number`가 `--json`을 가로채지 않고 `gh`에 넘길 수 있습니다. 구분자가
> 없으면 rune이 플래그를 스스로 가져가고, 래핑된 명령은 조용히 그 플래그를 보지 못합니다.

### 1. 에이전트 JSON 모드로 모든 CLI 명령 실행
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

### 2. NDJSON 결과 엔벨로프
```sh
rune run --ndjson -- fledge lanes run check
```
```json
{"event":"result","status":"ok","data":{"command":"fledge lanes run check","exit_code":0,"clean_output":"...","duration_ms":1652.8}}
```

`rune run --ndjson`은 명령이 끝나면 그 단일 엔벨로프를 내보냅니다. 출력 이벤트의
실시간 스트림에는 `rune watch`를 쓰세요.

### 3. 표 형식 CLI 출력을 해시로 파싱
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

### 4. 대화형 TTY / TUI 애플리케이션 구동
```ruby
require 'rune'

# Harness an interactive TUI program with input keystrokes
runner = Rune::PTYRunner.new("fledge plugins search --interactive", input: "\x03")
result = runner.run
# => Result with exit_code 130, clean_output, duration_ms
```

### 5. 세션 실시간 보기 (사람은 조작, 에이전트는 tail)
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

에이전트 모드에서는 — `--json`, `--ndjson`, 또는 stdout이 터미널이 아닐 때마다 — 실시간 패스스루가
**stderr**로 옮겨 가서 stdout에는 결과 엔벨로프만 실립니다. 사람은 실시간
화면을 유지하고, 호출하는 프로그램은 깨끗한 JSON을 받습니다:

```sh
rune watch --json -- ruby examples/humans/demo_tui.rb 2>/dev/null | jq .data.log_path
```

### 6. 한 에이전트 CLI로 다른 에이전트를 구동하기 (`rune session`)

`run`은 버퍼링한 뒤 한 번 반환합니다. `watch`는 터미널에 사람이 있어야 하고 자식과 함께 끝납니다. 둘 다
호출에 걸쳐 에이전트 REPL을 열어 둘 수 없습니다. `session`은 할 수 있습니다:

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

**raw 출력 대신 `--screen`을 쓰는 이유.** 전체 화면 에이전트는 계속 다시 그리므로,
바이트 스트림에는 모든 다시 그리기의 모든 프레임이 들어 있고 답변은 그 사이에 쪼개집니다. grok에 대해
측정한 결과: 361KB 트랜스크립트가 1.1KB 화면으로 렌더링되었고, 에이전트가 분명히
표시한 답변이 바이트 스트림에는 3회 중 3회 없었고 렌더링된 화면에는 3회 중
3회 있었습니다. 내용으로 매칭한다면 `screen`에서 매칭하세요.

**직접 핸들을 잡은 뒤**, 아무것도 멈추지 않고 다시 넘기세요:

```sh
rune session attach --name reviewer   # Ctrl-] detaches; the session keeps running
```

세션은 둘러싼 git 작업 트리 범위이므로, 두 checkout의 `reviewer`는 두
세션입니다. 의도된 동작이며, 가장 흔한 놀라움이기도 합니다. `list`에 아무것도 없다면
현재 디렉터리와 `RUNE_HOME`을 확인하세요:

```sh
rune session list --all-projects
```

**긴 트랜스크립트에서 한 가지를 찾기.** 구동한 에이전트와 하루 일한 결과가 379KB에 이르렀고,
원하는 내용이 가운데 있을 때는 `--since`도 `--tail`도 도움이 되지 않습니다:

```sh
rune session read --name reviewer --grep 'THE BOARD' --context 2
```

📖 전체 가이드(settle 튜닝과 알려진 제한 포함):
**[docs/sessions.md](docs/sessions.md)**.

---

## CorvidLabs 통합

`rune`은 [CorvidLabs 신뢰 툴체인](https://github.com/CorvidLabs)과 통합됩니다:

- **[fledge](https://github.com/CorvidLabs/fledge)** — 태스크 러너 및 프로젝트 라이프사이클. `rune`은 `plugin.toml`로 정의된 네이티브 `fledge` 플러그인입니다. 다음으로 직접 설치하세요:
  ```sh
  fledge plugins install CorvidLabs/rune
  fledge rune run --json -- git status
  ```
- **[spec-sync](https://github.com/CorvidLabs/spec-sync)** — 계약 강제 (`specs/`)
- **[augur](https://github.com/CorvidLabs/augur)** — 변경 위험 점수

---

## 아키텍처 및 내부

- 📖 **[시작 가이드](docs/getting_started.md)** — 출력 모드, `rune run` 사용법, 타임아웃, 실제 명령 출력을 사용한 파서.
- 📖 **[지속 세션 가이드](docs/sessions.md)** — `rune session`: 단일 호출보다 오래 사는 이름 있는 PTY 세션, 그리고 한 에이전트 CLI로 다른 에이전트를 구동하기 위한 send-and-settle.
- 📖 **[의사 TTY (PTY) 아키텍처 가이드](docs/pty_architecture.md)** — Ruby에서 의사 터미널, 비차단 스트림 읽기, ANSI 정리, 프롬프트 감지, 스크립트 실행, `rune watch`의 실시간 양방향 패스스루가 내부에서 어떻게 동작하는지.
- 📖 **[릴리스 가이드](docs/releasing.md)** — 버전 동기화, 검증, provenance, 태깅, 패키지 게시.

---

## 개발 및 검증

```sh
fledge run test         # Run RSpec test suite (405 examples, 87% line coverage)
fledge run lint         # Run RuboCop linter (0 offenses)
fledge lanes run verify # Full CI gate (lint + tests + strict 100%-coverage spec-sync)
fledge lanes run release # Verify, smoke-test, and build the release gem
fledge run smoke-test   # Runnable, assertion-based tour of real behavior (examples/smoke_test.rb)
COVERAGE=1 bundle exec rspec  # Same suite, plus an HTML coverage report at coverage/index.html
```

`examples/smoke_test.rb`는 독립적이고 의존성 없는 스크립트입니다 (bundler/rspec 불필요). 실제 CLI
바이너리에 대해 `rune run`, `--timeout`, `TableParser`/`KeyValueParser`, `Script`, 시그널 전달,
프롬프트 감지를 실행하며, 통과/실패 출력과 실패 시 0이 아닌 exit를 사용합니다.
개발 의존성이 설치되지 않은 머신에서, 또는 빠른 수동 상태 확인으로 유용합니다.

---

## 라이선스

MIT
