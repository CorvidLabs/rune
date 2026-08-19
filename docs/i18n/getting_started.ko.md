이 문서는 docs/getting_started.md의 한국어 번역본이며, 원문인 영어판이 정본입니다.

# rune 시작하기

`rune`은 터미널에서 사람이 쓰든, 에이전트가 프로그램으로 제어하든 똑같이 쓸 수 있게 만든 Ruby CLI이자 라이브러리입니다. 모든 명령은 동일한 구조의 `Result`를 반환하며, 호출 방식에 따라 *렌더링*만 달라집니다.

## 설치

공개 RubyGems.org 레지스트리에는 무관한 패키지가 이미 한정어 없는 `rune` 젬 이름을 선점하고 있어서, 그곳에서 `gem install rune`을 실행하면 잘못된 패키지가 설치됩니다. 지원하는 일반 사용자 설치 경로는 CorvidLabs Homebrew tap의 체크섬이 고정된 포뮬러입니다.

```sh
brew install corvidlabs/tap/rune
rune version --json
```

Homebrew는 처음 설치할 때 tap을 자동으로 추가합니다. Rune을 업그레이드하려면 다음을 실행하세요.

```sh
brew upgrade corvidlabs/tap/rune
```

Rune 자체를 개발할 때만 소스를 클론하세요.

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

또는 [fledge](https://github.com/CorvidLabs/fledge) 플러그인으로 설치할 수도 있습니다.

```sh
fledge plugins install CorvidLabs/rune
fledge rune run --json -- git status
```

## 무엇을 쓸 수 있는지 살펴보기

```sh
rune --help              # or -h, or `rune help`
rune run --help          # or `rune help run`, or `rune run -h`
```

명령 도움말은 `--timeout=SECONDS`(`rune run`), `--log=PATH`(`rune watch`)처럼 해당 명령 고유 플래그를 전역 플래그와 함께 보여 줍니다. 에이전트 모드에서도 구조화된 결과가 나오므로, 사람이 읽는 렌더링을 파싱하지 않아도 기능을 파악할 수 있습니다.

```sh
$ rune run --help --json | jq -c '.data.flags'
[{"flag":"--timeout=SECONDS","description":"Kill the wrapped command after N seconds (default 30). Before `--` only."},{"flag":"--max-output=BYTES","description":"Bound clean_output/raw_output to BYTES each, keeping head+tail and marking the join with a `[rune] ==== N bytes omitted by --max-output ====` line. Mutually exclusive with --tail. Before `--` only."},{"flag":"--tail=N","description":"Keep only the last N lines of clean_output/raw_output. Mutually exclusive with --max-output. Before `--` only."},{"flag":"--separate-streams","description":"Adds clean_stdout/clean_stderr (stderr on a pipe, not the pty) alongside the merged view. Before `--` only."}]
```

도움말 플래그도 아래와 같은 구분자 규칙을 따릅니다. `rune run -- mytool --help`는 `--help`를 `mytool`에 넘깁니다.

## 세 가지 출력 모드

`rune`은 호출 방식에 따라 렌더링 모드를 자동으로 고르며, 플래그로 강제로 지정할 수도 있습니다. 세 모드 모두 똑같은 명령 로직을 실행하고, 달라지는 것은 출력 형식뿐입니다.

### 1. 사람이 읽는 TTY 모드 (기본값, 대화형 터미널)

stdout이 실제 터미널이고 `--json`/`--ndjson` 플래그가 없으면, `rune`은 색이 입혀진 사람용 형식으로 출력합니다.

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

### 2. 에이전트 JSON 모드 (`--json`, 또는 파이프 자동 감지)

`--json`을 명시하거나, `rune`의 출력을 파이프나 리다이렉트하면 됩니다. stdout이 TTY가 아니면 플래그 없이도 렌더링이 자동으로 JSON으로 바뀝니다.

```sh
$ ruby bin/rune run --json -- echo "hello agent"
{"status":"ok","data":{"command":"echo hello\\ agent","exit_code":0,"clean_output":"hello agent\n","raw_output":"hello agent\r\n","prompt_detected":false,"duration_ms":5.27}}
```

```sh
$ ruby bin/rune version | cat
{"status":"ok","data":{"name":"rune","version":"0.7.0","ruby":"4.0.6","ruby_platform":"arm64-darwin25","fledge":true,"specsync":true}}
```

> **`exit_code`는 감싼 프로세스의 종료 상태이지, 작업이 맞았다는 판정이 아닙니다.** 이 값이 답하는 질문은 "프로세스가 끝났는가, 어떻게 끝났는가"입니다. 에이전트 CLI라면 출력이 틀렸던 실행까지 포함해 거의 항상 `0`입니다. 어떤 호출자는 `rune run`을 여덟 번 연속으로 보냈고 모두 `0`을 받았는데, 그중 여럿은 나중에 고쳐야 할 결론을 냈습니다. *작업*이 성공했는지를 알려면 이 필드가 아니라 출력에서 판단해야 합니다. 알아 둘 예외는 `124`입니다. rune이 `--timeout`으로 프로세스를 죽인 경우입니다.

모든 JSON 응답은 같은 봉투를 씁니다. `{"status": "ok"|"error", "data": {...}}`이고, 실패 시에는 `{"status": "error", "error": "..."}`입니다.

성공이든 실패든 Rune은 최종 봉투를 stdout에 씁니다. 에이전트는 파싱 가능한 결과 채널을 하나만 보면 되지만, 사람이 stdout을 리다이렉트하면 Rune 수준의 오류 메시지도 함께 넘어갑니다. stderr는 운영 안내와, 구조화된 stdout을 망치면 안 되는 실시간 `rune watch` 패스스루를 위해 남겨 둡니다.

전역 출력 플래그는 첫 `--` 구분자 앞에서만 인식합니다. 그 뒤 토큰은 감싼 명령에 속하며 그대로 보존되므로, `rune run -- tool --json`은 `--json`을 `tool`에 넘깁니다.

rune 자신의 플래그가 올 자리에 rune이 모르는 `--flag`가 있으면, 조용히 넘기지 않고 오류로 처리합니다. 예전에는 `rune run --tiemout=5 -- echo hi`가 오타 난 플래그를 *실행*하려 들며 `status: ok`와 `exit_code: 127`을 돌려주었습니다. 검사하는 것은 감싼 명령 앞의 토큰뿐이므로, `rune run cargo clippy --tests`와 `rune run -- mytool --tiemout=5`는 손대지 않습니다. 명령 이름을 본 뒤에는 이어지는 `--flag`는 모두 그 명령의 것입니다.

### 3. 에이전트 NDJSON 봉투 모드 (`--ndjson`)

`--ndjson`은 같은 결과를 `--json`이 쓰는 평범한 `{"status": ...}` 형태 대신 `{"event": "result"|"error", ...}` 봉투로 감쌉니다. 일부 에이전트 하네스는 `rune run`을 포함해 모든 명령에 이 형식을 일관되게 기대합니다.

```sh
$ ruby bin/rune run --ndjson -- echo "hello stream"
{"event":"result","status":"ok","data":{"command":"echo hello\\ stream","exit_code":0,"clean_output":"hello stream\n","raw_output":"hello stream\r\n","prompt_detected":false,"duration_ms":11.45}}
```

`rune run`에서는 명령이 끝난 뒤에 한 줄만 나갑니다. `PTYRunner`가 실행 전체를 버퍼링한 뒤 `Result` 하나를 반환하므로, 여기서 `--ndjson`은 증분 스트리밍이 아니라 봉투 선택입니다. 오래 걸리거나 대화형인 명령이 진행되는 동안 실제 실시간 이벤트 스트림이 필요하면, 아래 [`rune watch`](#rune-watch로-세션을-실시간으로-보기)를 보세요. 출력 청크가 나올 때마다 NDJSON 한 줄을 보냅니다.

## `rune run`으로 명령 실행하기

`rune run`은 CLI 명령이나 대화형 TUI를 실제 PTY 안에서 띄우고, ANSI 이스케이프 시퀀스를 걷어 내고, 페이저를 끄고, 실행 시간을 잽니다.

```sh
rune run -- git status
rune run --json -- npm test
rune run --ndjson -- fledge lanes run check
```

### 타임아웃 바꾸기

`rune run`은 호출마다 기본 타임아웃이 30초입니다. `--timeout=SECONDS`로 바꿀 수 있는데, 감싼 명령의 플래그로 오해되지 않도록 `--` 구분자 *앞*에 두세요.

```sh
$ ruby bin/rune run --json --timeout=1 -- sleep 3
{"status":"ok","data":{"command":"sleep 3","exit_code":124,"clean_output":"\n[rune] Execution timed out after 1 seconds","raw_output":"\n[rune] Execution timed out after 1 seconds","prompt_detected":false,"duration_ms":1005.32}}
```

타임아웃이 난 명령은 종료 코드 `124`를 반환하고, 캡처한 출력 끝에 `[rune] Execution timed out after N seconds` 메시지를 붙입니다. 예외가 아니라 평범한 `Result`입니다.

**죽이기 전에 캡처한 출력은 항상 돌려줍니다.** 그래서 출력한 뒤 멈춘 자식은 그때까지 찍은 내용이 보입니다. 출력이 *비어 있으면* 자식이 정말로 아무것도 찍지 않은 것이고, rune은 그 사실과 가장 흔한 이유를 함께 알려 줍니다.

**`rune run`은 자신의 stdin을 자식에게 넘기지 않습니다.** tty는 사람의 것이고, 그것을 가져가는 일은 `rune watch`의 몫입니다. 파이프를 그대로 넘기면 호출자의 입력이 pty를 타고 `clean_output`으로 다시 들어옵니다. 그래서 `echo hi | rune run -- cat`은 타임아웃이 납니다. `cat`이 오지 않는 입력을 기다리기 때문입니다. 리다이렉트는 명령 안에 넣으세요. 그러면 셸이 pty 안에서 처리합니다.

```sh
$ rune run -- sh -c 'claude -p --output-format text < prompt.md'
```

이렇게 하면 되고, 여러 단락짜리 프롬프트를 인자 하나로 넘기는 것도 됩니다. 줄바꿈은 argv에 그대로 남습니다. 응답의 `command` 필드는 사람이 보라고 셸 이스케이프한 *표시용* 재구성이지, 자식이 받은 내용이 아닙니다. 따옴표 문제를 이 필드로 진단하지 마세요.

### 출력 크기 제한과 스트림 분리

`--` 구분자 앞에 두는 플래그가 세 개 더 있고, 모두 결과의 *형태*를 바꿉니다.

- **`--max-output=BYTES`** 는 `clean_output`과 `raw_output`을 각각 BYTES로 제한하고, 앞부분과 뒷부분을 남긴 뒤 `truncated: true`와 `omitted_bytes`를 붙입니다. "각각"에서 두 가지가 따라옵니다. 필드는 *따로* 잘리므로, 이 플래그 아래에서는 실행의 서로 다른 구간을 가리키고 `clean_output`은 `strip_ansi(raw_output)`이 아닙니다. `omitted_bytes`는 `clean_output` 쪽 개수이고, `raw_output`은 다른 개수로 자기 표식을 갖습니다. 그리고 `omitted_bytes`는 원문에서의 오프셋으로 재므로, ASCII에서는 딱 맞고 멀티바이트 텍스트에서는 잘린 자리가 글자를 쪼갤 수 있어 몇 바이트 어긋납니다. 두 조각은 이어 붙이지 않고 `[rune] ==== N bytes omitted by --max-output ====` 한 줄로 잇습니다. 돌려준 텍스트가 명령이 찍은 것처럼 읽히지 않게 하려는 것입니다. 이 표식이 없으면 `--max-output=200`에서 201바이트짜리 기록이 바이트 하나를 잃어 `chsh -s /bin/zsh`가 `chsh -s bin/zsh`로 보였습니다. 그 표식은 명령 출력이 아니라 rune의 주석이므로 BYTES 예산에 넣지 않고, 응답이 예산을 조금 넘을 수 있습니다.
- **`--tail=N`** 은 마지막 N줄만 남기고 `truncated: true`와 `omitted_lines`를 붙입니다. `--max-output`과 함께 쓸 수 없으며, 둘 다 넘기면 한쪽을 조용히 우선하지 않고 오류로 처리합니다.
- **`--separate-streams`** 는 합쳐진 `clean_output`을 대체하지 않고, 옆에 `clean_stdout`과 `clean_stderr`를 더합니다.

`--separate-streams`에는 실제 대가가 있어서 기본값이 아니라 선택 사항입니다. pty는 스트림이 하나이므로, 둘을 나누려면 stderr에 전용 파이프를 줘야 합니다. 그러면 자식은 둘 다에 대해 하나의 제어 터미널을 보지 못하고, `isatty(2)`를 확인하는 프로그램은 오류가 리다이렉트된 것처럼 동작합니다. 많은 CLI는 색을 끄거나 비대화형 모드로 통째로 바꿉니다. 자식이 터미널에 있다고 믿게 하는 것보다 분리가 더 필요할 때만 쓰세요.

## `rune watch`로 세션을 실시간으로 보기

`rune run`은 명령 출력을 전부 버퍼링했다가 끝난 뒤에야 돌려줍니다. 스크립트와 캡처에는 알맞지만, 키보드에 앉아 대화형 프로그램을 직접 다루면서 다른 쪽이 세션을 관찰해야 할 때는 맞지 않습니다. `rune watch`가 그 용도입니다. 터미널을 raw 모드로 두고, 입력한 키를 자식에게 실시간으로 넘깁니다. 줄 단위만이 아니라 화살표 키 같은 raw 이스케이프 시퀀스까지 포함합니다. 자식의 출력은 끝날 때가 아니라 나오는 즉시 화면에 흐르고, 동시에 모든 청크를 NDJSON 이벤트로 기록합니다. 사람이 세션을 다루는 동안 AI 에이전트가 실시간으로 tail할 수 있습니다.

```sh
# A small interactive demo program ships with rune specifically to try this against:
rune watch -- ruby examples/humans/demo_tui.rb
```

이벤트 로그의 기본값은 stderr이 아니라, 충돌을 피하고 소유자만 읽을 수 있는(`0600`) 임시 파일입니다. 원래 설계는 NDJSON 이벤트를 실시간 패스스루와 같은 터미널에 섞는 것이었는데, 실제 사용에서 바로 잘못된 기본값임이 드러났습니다. JSON이 끼어들면 세션을 읽을 수 없었습니다. 경로는 처음에 한 번만 알려 줍니다.

```
[rune watch] live event log: /tmp/rune-watch-20260728-12345-abcd.ndjson
```

다른 창에서 그 경로를 `tail -f`하거나 에이전트에게 tail시키면, 자기 터미널은 깨끗한 채로 세션을 실시간으로 볼 수 있습니다. 위치를 직접 정하려면 `--log=PATH`를 쓰세요.

```sh
rune watch --log=/tmp/session.ndjson -- ruby examples/humans/demo_tui.rb
```

로그의 각 줄은 JSON 객체입니다. `{"event":"start","command":"...","pid":...}`로 시작하고, 스트리밍되는 청크마다 `{"event":"output","bytes":N,"text":"..."}` 한 줄이 오며, 자식이 끝나면 `{"event":"exit","exit_code":N}`입니다.

### 에이전트 모드의 `rune watch`

`rune watch`도 다른 명령과 같은 출력 모드 규칙을 따릅니다. `--json`, `--ndjson`이거나 stdout이 터미널이 아니면, 실시간 패스스루는 **stderr**로 가고 stdout에는 결과 봉투만 실립니다. 감싼 프로그램은 stdout을 바로 파싱하고, 키보드 앞의 사람은 세션을 그대로 볼 수 있습니다.

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

세션을 직접 보면서 JSON은 다른 곳에 받으려면 `2>/dev/null`을 빼면 됩니다.

`rune watch`는 실제 터미널이 필요합니다. stdin이 TTY가 아니면 실행을 거부하며, 의미 있는 비대화형 모드는 없습니다. `rune run`의 PTY 안에서 다시 돌리는 것도 되지 않으므로, 이 가이드의 나머지처럼 파이프 예시로 보여 줄 수 없습니다. `examples/humans/demo_tui.rb`의 최상위 메뉴는 숫자를 치고 Enter를 누르는 방식이 아니라, 화살표 키 선택기(↑/↓ + Enter, 종료는 `q`)입니다. raw 한 바이트와 이스케이프 시퀀스 전달을 시험하려고 그렇게 만든 것이고, 줄 단위로만 버퍼링하는 메뉴는 이 경로를 건드리지 않습니다. `examples/humans/demo_tui.rb`의 헤더 주석에는 복사해 쓸 수 있는 명령이 있고, `spec/rune/pty_watcher_spec.rb`는 전달·기록 메커니즘이 어떻게 단위 테스트되는지 보여 줍니다. 화살표 키 메뉴 자체를 처음부터 끝까지 구동하는 테스트도 있습니다. 가짜 터미널 객체와 `IO.pipe`로 실제 대화형 자식 프로세스를 돌리며, 진짜 제어 터미널은 필요 없습니다.

### watch 제한하기

서로 독립된 제한이 두 가지이고, 둘 다 `--` 구분자 앞에 두며, 기본값은 꺼짐입니다.

- **`--timeout=SECONDS`** 는 얼마나 바쁘든 벽시계 기준 N초가 지나면 세션을 죽입니다.
- **`--idle-timeout=SECONDS`** 는 **출력도 입력도 없는** 상태가 N초 지속되면 죽입니다. 긴 빌드는 idle이 아니므로, "이 에이전트가 아무 것도 안 하게 됐다"를 잡을 때 이쪽을 씁니다.

어느 쪽이든 종료 코드는 `124`이고, `timed_out: true`와 함께 어느 쪽이 발동했는지 `timeout_kind`가 `"timeout"` 또는 `"idle_timeout"`으로 알려 줍니다.

## 구조화된 텍스트 파싱하기

`Rune::Parsers::TableParser`와 `Rune::Parsers::KeyValueParser`는 구조화되지 않은 터미널 출력을 Ruby 해시로 바꿉니다.

```ruby
require 'rune'

Rune::Parsers::TableParser.parse(<<~TABLE)
  NAME           STATUS   VERSION
  fledge-plugin  active   1.0.0
TABLE
# => [{ name: 'fledge-plugin', status: 'active', version: '1.0.0' }]
```

`TableParser.parse`는 `format:` 키워드를 받습니다. 기본값은 `:auto`이고, 파싱 모드를 강제하려면 `:pipe` 또는 `:space`를 씁니다. 낯선 출력에 `:auto`를 기대기 전에, 휴리스틱의 알려진 한계는 [`specs/parsers/parsers.spec.md`](../../specs/parsers/parsers.spec.md)를 보세요.

## 다음 단계

- [`examples/smoke_test.rb`](../../examples/smoke_test.rb) — `ruby examples/smoke_test.rb` 또는 `fledge run smoke-test`. bundler/rspec 없이 실제 동작을 assertion으로 훑는 독립 투어입니다. 출력 모드, `--timeout` 검증, 파서, `Script`, 시그널 전달, 프롬프트 감지를 다룹니다.
- [`examples/humans/demo_tui.rb`](../../examples/humans/demo_tui.rb) — 위에서 `rune watch` 절에 쓴 대화형 데모입니다. [`examples/agents/pty_runner_example.rb`](../../examples/agents/pty_runner_example.rb), [`table_parser_example.rb`](../../examples/agents/table_parser_example.rb), [`script_automation_example.rb`](../../examples/agents/script_automation_example.rb)는 개념 하나씩만 다루는 작은 스크립트입니다. 각각 `require_relative '../lib/rune'` 외에는 준비 없이 (`ruby examples/agents/<name>.rb`)로 바로 실행할 수 있습니다.
- [PTY 아키텍처 가이드](pty_architecture.ko.md) — PTY 러너, 스트림 읽기, 프롬프트 감지, `rune watch`의 실시간 패스스루가 내부에서 어떻게 동작하는지 설명합니다.
- [`specs/`](../../specs/) — `cli`, `parsers`, `pty_runner`, `session`, `watch`에 대한 기계 검증 모듈 계약(`spec-sync`)입니다.
- [`AGENTS.md`](../../AGENTS.md) — 새 명령을 추가하고 trust 툴체인을 다룰 때의 규칙입니다.
