# rune

*Этот документ является переводом README.md, и английский оригинал является авторитетным.*

[![CI](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml/badge.svg)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-3.0%20%E2%80%93%204.0-CC342D?logo=ruby&logoColor=white)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)

Инструмент командной строки и библиотека на Ruby, изначально спроектированные так, чтобы быть **первоклассными для людей и AI-агентов**.

`rune` служит универсальным раннером псевдотерминала (PTY) и мостом структурированных данных для любой CLI-команды или интерактивного TUI-приложения.

Каждая команда формирует отформатированный цветной вывод терминала для людей и структурированный JSON для AI
агентов. `rune watch` дополнительно записывает живой поток событий NDJSON, пока человек управляет
сеансом. Тот же инструмент, те же команды, двойной интерфейс.

`rune session` идёт ещё на шаг дальше: он удерживает CLI агента — `claude`, `grok`, `codex` — открытым
между отдельными вызовами, так что один агент может управлять другим в диалоговом режиме, а человек может подключиться
к тому же сеансу и взять управление на себя.

📖 Впервые здесь? Начните с **[Getting Started guide](docs/getting_started.md)**.

---

## Возможности

1. **Двойной вывод (человеческий TTY / агентский JSON и NDJSON)**
   - Режим терминала: отформатированный цветной вывод (`rune version`)
   - Режим агентского JSON: `--json` или автоматическое определение канала (`rune version | cat`)
   - Режим агентского NDJSON: `--ndjson` для единообразного конверта результата (`rune version --ndjson`)
2. **Универсальный раннер процессов PTY (`rune run`)**
   - Запускает любой CLI-инструмент или TUI внутри сеанса псевдотерминала
   - Автоматически удаляет ANSI-коды escape, перемещения курсора и управляющие последовательности
   - Отключает терминальные пейджеры (`PAGER=cat`), чтобы запросы возвращались сразу, без зависания
   - Измеряет длительность выполнения процесса в миллисекундах и обнаруживает интерактивные приглашения
3. **Структурированные автопарсеры (`Rune::Parsers`)**
   - `TableParser`: разбирает разделённые пробелами или вертикальной чертой таблицы терминала в массивы хешей
   - `KeyValueParser`: разбирает вывод ключ-значение (`key: val`) в типизированные хеши
   - `TextSanitizer`: нормализует окончания строк и очищает ANSI-коды escape
4. **Интерактивный DSL сценариев (`Rune::Script`)**
   - Пошаговый DSL автоматизации TUI-сценариев для управления интерактивными приглашениями терминала и меню TUI
5. **Живой интерактивный проброс (`rune watch`)**
   - Переводит ваш терминал в raw-режим и в реальном времени пересылает нажатия клавиш дочернему процессу, байт в байт
   - Транслирует вывод дочернего процесса на экран по мере появления (в отличие от `rune run`, который буферизует и
     возвращает всё в конце)
   - Одновременно записывает каждый фрагмент как событие NDJSON во временный файл (путь объявляется один раз, либо
     `--log=PATH`), чтобы AI-агент мог отслеживать сеанс вживую, пока человек им управляет
6. **Постоянные именованные сеансы (`rune session`)**
   - Удерживает REPL-образный дочерний процесс — `claude`, `grok`, `codex`, оболочку — открытым *между* отдельными вызовами `rune`,
     чего не умеют ни `run` (буферизует и возвращает один раз), ни `watch` (завершается вместе со своим
     дочерним процессом)
   - **Send-and-settle**: записывает ввод, ждёт, пока дочерний процесс затихнет, и возвращает ровно тот вывод,
     который породила эта отправка, превращая асинхронный TTY в синхронный вызов запрос/ответ
   - `--screen` возвращает *отрисованный терминал*, а не сырой поток байтов, что важно,
     потому что полноэкранный агент перемежает свой ответ собственными перерисовками — в одном измеренном
     транскрипте объём упал с 361KB трафика перерисовок до экрана в 1.1KB
   - `attach` передаёт живой сеанс человеческому терминалу, а **Ctrl-]** возвращает его обратно — сеанс продолжает работать
   - Сеансы именованы, привязаны к проекту и могут архивироваться; транскрипты ограничены на диске и в
     памяти, поэтому сеанс, оставленный работающим на день, не растёт без ограничения

---

## Установка

Неквалифицированное имя gem `rune` уже занято в публичном реестре RubyGems.org
посторонним пакетом, поэтому `gem install rune` там устанавливает не то. Устанавливайте поддерживаемую
формулу с закреплённой контрольной суммой из Homebrew tap CorvidLabs:

```sh
brew install corvidlabs/tap/rune
rune version --json
```

Обновляйте последующие выпуски через тот же канал:

```sh
brew upgrade corvidlabs/tap/rune
```

Для разработки из исходников:

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

---

## Примеры использования

### 0. Знакомство с CLI

```sh
rune --help              # все команды, плюс глобальные флаги
rune run --help          # справка одной команды и её собственные флаги
rune help watch          # то же самое, записанное иначе
```

Справка тоже структурирована, поэтому агент может исследовать поверхность без разбора текста:

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

> **Ставьте `--` перед оборачиваемой командой.** Каждый флаг rune — `--json`, `--ndjson`, `--help`,
> `--timeout`, `--log` — распознаётся *только* до первого `--`. Именно поэтому
> `rune run -- gh pr list --json number` передаёт `--json` в `gh`, а не забирает его себе. Без
> разделителя rune забирает флаг себе, и оборачиваемая команда молча его никогда не видит.

### 1. Выполнение любой CLI-команды в режиме агентского JSON
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

### 2. Конверт результата NDJSON
```sh
rune run --ndjson -- fledge lanes run check
```
```json
{"event":"result","status":"ok","data":{"command":"fledge lanes run check","exit_code":0,"clean_output":"...","duration_ms":1652.8}}
```

`rune run --ndjson` выдаёт этот единственный конверт, когда команда завершается. Используйте `rune watch` для
живого потока событий вывода.

### 3. Разбор табличного CLI-вывода в хеши
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

### 4. Управление интерактивными приложениями TTY / TUI
```ruby
require 'rune'

# Управляйте интерактивной TUI-программой, подавая нажатия клавиш
runner = Rune::PTYRunner.new("fledge plugins search --interactive", input: "\x03")
result = runner.run
# => Result with exit_code 130, clean_output, duration_ms
```

### 5. Просмотр сеанса вживую (человек управляет, агент отслеживает)
```sh
# Переводит терминал в raw-режим, в реальном времени пересылает ваши нажатия клавиш — включая
# сырые escape-последовательности вроде стрелок, а не только целые строки — и транслирует
# вывод на экран по мере появления. Записывает событие NDJSON на каждый фрагмент во
# временный файл (объявляется один раз, заранее), чтобы агент мог читать его через `tail -f` вживую
# без какого-либо JSON-шума в вашем собственном терминале. Верхнеуровневое меню демо —
# настоящий селектор на стрелках (↑/↓ + Enter, либо q для выхода).
rune watch -- ruby examples/humans/demo_tui.rb

# Или укажите для журнала конкретное место:
rune watch --log=/tmp/session.ndjson -- ruby examples/humans/demo_tui.rb
```

В режиме агента — `--json`, `--ndjson` или всякий раз, когда stdout не является терминалом — живой проброс
переносится на **stderr**, чтобы stdout нёс только конверт результата. Человек сохраняет свой живой
вид; вызывающая программа получает чистый JSON:

```sh
rune watch --json -- ruby examples/humans/demo_tui.rb 2>/dev/null | jq .data.log_path
```

### 6. Управление одним агентским CLI из другого (`rune session`)

`run` буферизует и возвращает один раз; `watch` нуждается в человеке за терминалом и завершается вместе со своим дочерним процессом. Ни одно из них
не может удерживать агентский REPL открытым между вызовами. `session` может:

```sh
# Запустите именованный сеанс. Дочерний процесс переживает эту команду.
rune session start --name reviewer -- grok

# Отправьте запрос и дождитесь ответа. --screen возвращает отрисованный
# терминал — именно там ответ действительно читаем.
rune session send --name reviewer --screen -- "Review lib/rune/session/supervisor.rb for races"

# Вернитесь позже — из другого процесса, другого агента, в другой час.
rune session send --name reviewer --screen -- "Now just the highest-severity one, in one line"

rune session list          # что запущено, насколько простаивает, что печатало последним
rune session stop --name reviewer
```

**Почему `--screen`, а не сырой вывод.** Полноэкранный агент непрерывно перерисовывается, поэтому
поток байтов содержит каждый кадр каждой перерисовки, а ответ разбит по ним. Измерено
на grok: транскрипт в 361KB отрисовался в экран 1.1KB, и ответ, который агент явно
показал, отсутствовал в потоке байтов в 3 из 3 ходов и присутствовал на отрисованном экране в 3 из
3. Если вы сопоставляете по содержимому, сопоставляйте по `screen`.

**Возьмите управление сами**, затем верните его, ничего не останавливая:

```sh
rune session attach --name reviewer   # Ctrl-] отсоединяет; сеанс продолжает работать
```

Сеансы привязаны к охватывающему рабочему дереву git, поэтому `reviewer` в двух рабочих копиях — это два
сеанса. Так задумано, и это же самая частая неожиданность — если `list` ничего не показывает,
проверьте каталог, в котором вы находитесь, и `RUNE_HOME`:

```sh
rune session list --all-projects
```

**Как найти одно в длинном транскрипте.** День работы с управляемым агентом достиг 379KB, и
ни `--since`, ни `--tail` не помогают, когда нужное находится в середине:

```sh
rune session read --name reviewer --grep 'THE BOARD' --context 2
```

📖 Полное руководство, включая настройку settle и известные ограничения:
**[docs/sessions.md](docs/sessions.md)**.
---

## Интеграция с CorvidLabs

`rune` интегрируется с [цепочкой доверия CorvidLabs](https://github.com/CorvidLabs):

- **[fledge](https://github.com/CorvidLabs/fledge)** — Средство запуска задач и жизненный цикл проекта. `rune` — нативный плагин `fledge`, заданный через `plugin.toml`. Устанавливается напрямую так:
  ```sh
  fledge plugins install CorvidLabs/rune
  fledge rune run --json -- git status
  ```
- **[spec-sync](https://github.com/CorvidLabs/spec-sync)** — Обеспечение контрактов (`specs/`)
- **[augur](https://github.com/CorvidLabs/augur)** — Оценка риска изменений

---

## Архитектура и внутреннее устройство

- 📖 **[Getting Started guide](docs/getting_started.md)** — Режимы вывода, использование `rune run`, тайм-ауты и парсеры с реальным выводом команд.
- 📖 **[Persistent sessions guide](docs/sessions.md)** — `rune session`: именованные PTY-сеансы, которые переживают один вызов, и send-and-settle для управления одним агентским CLI из другого.
- 📖 **[Pseudo-TTY (PTY) Architecture Guide](docs/pty_architecture.md)** — Как псевдотерминалы, неблокирующее чтение потоков, санитарная обработка ANSI, обнаружение приглашений, выполнение сценариев и живой двунаправленный проброс `rune watch` работают внутри в Ruby.
- 📖 **[Release guide](docs/releasing.md)** — Синхронизация версий, проверка, provenance, тегирование и публикация пакета.

---

## Разработка и проверка

```sh
fledge run test         # Запустить набор тестов RSpec (405 примеров, 87% покрытия строк)
fledge run lint         # Запустить линтер RuboCop (0 нарушений)
fledge lanes run verify # Полный шлюз CI (lint + тесты + строгий spec-sync со 100%-покрытием)
fledge lanes run release # Проверить, прогнать smoke-test и собрать release gem
fledge run smoke-test   # Запускаемый, основанный на утверждениях обзор реального поведения (examples/smoke_test.rb)
COVERAGE=1 bundle exec rspec  # Тот же набор, плюс HTML-отчёт о покрытии в coverage/index.html
```

`examples/smoke_test.rb` — автономный скрипт без зависимостей (bundler/rspec не требуются), который
проверяет `rune run`, `--timeout`, `TableParser`/`KeyValueParser`, `Script`, пересылку сигналов и
обнаружение приглашений на реальном CLI-бинарнике, с выводом pass/fail и ненулевым кодом выхода при неудаче.
Полезен как быстрая ручная проверка работоспособности или на машине без установленных зависимостей разработки.

---

## Лицензия

MIT
