> Este documento es una traducción al español de [README.md](../../README.md); la versión en inglés es la autoritativa.

# rune

[![CI](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml/badge.svg)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-3.0%20%E2%80%93%204.0-CC342D?logo=ruby&logoColor=white)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)

Una herramienta de línea de comandos y biblioteca en Ruby diseñada desde el principio para tratar a **humanos y agentes de IA como ciudadanos de primera clase**.

`rune` funciona como un ejecutor universal de seudoterminal (PTY) y como un puente de datos estructurados para cualquier comando de CLI o aplicación interactiva de TUI.

Cada comando produce salida de terminal formateada y coloreada para humanos y JSON estructurado para
agentes de IA. `rune watch` además escribe un flujo de eventos NDJSON en vivo mientras la persona conduce la
sesión. Misma herramienta, mismos comandos, interfaz dual.

`rune session` va un paso más allá: mantiene una CLI de agente — `claude`, `grok`, `codex` — abierta
entre invocaciones separadas, de modo que un agente pueda conducir a otro de forma conversacional y una persona pueda conectarse
a la misma sesión y tomar el control.

📖 ¿Nuevo por aquí? Empiece por la **[guía de primeros pasos](getting_started.es.md)**.

---

## Capacidades

1. **Salida dual (TTY para humanos / JSON y NDJSON para agentes)**
   - Modo terminal: salida formateada y coloreada (`rune version`)
   - Modo JSON de agente: `--json` o detección automática de pipe (`rune version | cat`)
   - Modo NDJSON de agente: `--ndjson` para un sobre de resultado coherente (`rune version --ndjson`)
2. **Ejecutor universal de procesos PTY (`rune run`)**
   - Lanza cualquier herramienta de CLI o TUI dentro de una sesión de seudoterminal
   - Elimina automáticamente los códigos de escape ANSI, los movimientos del cursor y las secuencias de control
   - Desactiva los paginadores de terminal (`PAGER=cat`) para que las consultas devuelvan el resultado de inmediato sin quedarse colgadas
   - Mide la duración de ejecución del proceso en milisegundos y detecta las indicaciones interactivas
3. **Analizadores automáticos estructurados (`Rune::Parsers`)**
   - `TableParser`: Analiza tablas de terminal delimitadas por espacios o pipes y las convierte en arrays de hashes
   - `KeyValueParser`: Analiza salida de clave-valor (`key: val`) y la convierte en hashes tipados
   - `TextSanitizer`: Normaliza los finales de línea y limpia los códigos de escape ANSI
4. **DSL de scripts interactivos (`Rune::Script`)**
   - DSL de automatización de scripts TUI paso a paso para conducir indicaciones interactivas de terminal y menús TUI
5. **Paso transparente interactivo en vivo (`rune watch`)**
   - Pone su terminal en modo raw y reenvía las pulsaciones de teclas al proceso hijo en vivo, byte a byte
   - Transmite la salida del proceso hijo a su pantalla a medida que ocurre (a diferencia de `rune run`, que almacena en búfer y
     devuelve todo al final)
   - Simultáneamente registra cada fragmento como un evento NDJSON en un archivo temporal (ruta anunciada una vez, o
     `--log=PATH`) para que un agente de IA pueda seguir la sesión en vivo mientras una persona la conduce
6. **Sesiones persistentes con nombre (`rune session`)**
   - Mantiene un proceso hijo con forma de REPL — `claude`, `grok`, `codex`, un shell — abierto *entre* invocaciones
     separadas de `rune`, lo que ni `run` (almacena en búfer y devuelve una vez) ni `watch` (muere con su proceso hijo)
     pueden hacer
   - **Send-and-settle**: escribe la entrada, espera a que el proceso hijo se quede en silencio, recupera exactamente la salida
     que produjo ese envío, convirtiendo un TTY asíncrono en una llamada síncrona de solicitud/respuesta
   - `--screen` devuelve el *terminal renderizado* en lugar del flujo de bytes en bruto, lo cual importa
     porque un agente a pantalla completa entrelaza su respuesta con sus propios redibujados — una transcripción
     medida pasó de 361KB de tráfico de redibujado a una pantalla de 1.1KB
   - `attach` entrega la sesión en vivo a un terminal humano y **Ctrl-]** la devuelve, aún en ejecución
   - Las sesiones tienen nombre, están acotadas al proyecto y se pueden archivar; las transcripciones están acotadas en disco y en
     memoria, de modo que una sesión que se deja en ejecución durante un día no crece sin límite

---

## Instalación

El nombre no cualificado de la gema `rune` ya está ocupado en el registro público de RubyGems.org por un
paquete no relacionado, así que `gem install rune` allí instala lo incorrecto. Instale la fórmula mantenida,
fijada por checksum, del tap de Homebrew de CorvidLabs:

```sh
brew install corvidlabs/tap/rune
rune version --json
```

Actualice las versiones posteriores a través del mismo canal:

```sh
brew upgrade corvidlabs/tap/rune
```

Para el desarrollo desde el código fuente:

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

---

## Ejemplos de uso

### 0. Descubra la CLI

```sh
rune --help              # every command, plus the global flags
rune run --help          # one command's usage and its own flags
rune help watch          # same thing, spelled the other way
```

La ayuda también está estructurada, de modo que un agente pueda descubrir la superficie sin extraer texto:

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

> **Use `--` antes del comando encapsulado.** Toda flag de rune — `--json`, `--ndjson`, `--help`,
> `--timeout`, `--log` — se reconoce *solo* antes del primer `--`. Eso es lo que permite que
> `rune run -- gh pr list --json number` pase `--json` a `gh` en lugar de consumirlo. Sin el
> separador, rune toma la flag para sí y el comando encapsulado silenciosamente nunca la ve.

### 1. Ejecute cualquier comando de CLI en modo JSON para agentes
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

### 2. Sobre de resultado NDJSON
```sh
rune run --ndjson -- fledge lanes run check
```
```json
{"event":"result","status":"ok","data":{"command":"fledge lanes run check","exit_code":0,"clean_output":"...","duration_ms":1652.8}}
```

`rune run --ndjson` emite ese único sobre cuando el comando termina. Use `rune watch` para un
flujo en vivo de eventos de salida.

### 3. Analice la salida tabular de CLI a hashes
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

### 4. Conduzca aplicaciones TTY / TUI interactivas
```ruby
require 'rune'

# Harness an interactive TUI program with input keystrokes
runner = Rune::PTYRunner.new("fledge plugins search --interactive", input: "\x03")
result = runner.run
# => Result with exit_code 130, clean_output, duration_ms
```

### 5. Vea una sesión en vivo (la persona conduce, el agente hace tail)
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

En modo agente — `--json`, `--ndjson`, o cada vez que stdout no es un terminal — el paso transparente en vivo
se mueve a **stderr** de modo que stdout no lleve nada más que el sobre de resultado. La persona conserva su vista
en vivo; el programa que llama obtiene JSON limpio:

```sh
rune watch --json -- ruby examples/humans/demo_tui.rb 2>/dev/null | jq .data.log_path
```

### 6. Conduzca una CLI de agente desde otra (`rune session`)

`run` almacena en búfer y devuelve una vez; `watch` necesita a una persona en un terminal y termina con su proceso hijo. Ninguno
puede mantener un REPL de agente abierto entre llamadas. `session` sí puede:

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

**Por qué `--screen` en lugar de la salida en bruto.** Un agente a pantalla completa se redibuja continuamente, de modo que el
flujo de bytes contiene cada fotograma de cada redibujado con la respuesta partida entre ellos. Medido
frente a grok: una transcripción de 361KB se renderizó a una pantalla de 1.1KB, y una respuesta que el agente había
mostrado con claridad estaba ausente del flujo de bytes en 3 de 3 turnos y presente en la pantalla renderizada en 3 de
3. Si está buscando coincidencias en el contenido, compare contra `screen`.

**Tome el control usted mismo**, y luego devuélvalo sin detener nada:

```sh
rune session attach --name reviewer   # Ctrl-] detaches; the session keeps running
```

Las sesiones están acotadas al árbol de trabajo git que las encierra, así que `reviewer` en dos checkouts son dos
sesiones. Eso es deliberado, y también es la sorpresa más común — si `list` no muestra nada,
compruebe el directorio en el que está y `RUNE_HOME`:

```sh
rune session list --all-projects
```

**Encontrar una cosa en una transcripción larga.** Un día de trabajo con un agente conducido llegó a 379KB, y
ni `--since` ni `--tail` ayudan cuando lo que busca está en el medio:

```sh
rune session read --name reviewer --grep 'THE BOARD' --context 2
```

📖 Guía completa, incluida la sintonización de settle y las limitaciones conocidas:
**[sessions.es.md](sessions.es.md)**.

---

## Integración con CorvidLabs

`rune` se integra con la [cadena de herramientas de confianza de CorvidLabs](https://github.com/CorvidLabs):

- **[fledge](https://github.com/CorvidLabs/fledge)** — Ejecutor de tareas y ciclo de vida del proyecto. `rune` es un plugin nativo de `fledge` definido mediante `plugin.toml`. Instale directamente con:
  ```sh
  fledge plugins install CorvidLabs/rune
  fledge rune run --json -- git status
  ```
- **[spec-sync](https://github.com/CorvidLabs/spec-sync)** — Aplicación de contratos (`specs/`)
- **[augur](https://github.com/CorvidLabs/augur)** — Puntuación del riesgo de los cambios

---

## Arquitectura e internos

- 📖 **[Guía de primeros pasos](getting_started.es.md)** — Modos de salida, uso de `rune run`, tiempos de espera y analizadores con salida real de comandos.
- 📖 **[Guía de sesiones persistentes](sessions.es.md)** — `rune session`: sesiones PTY con nombre que sobreviven a una sola invocación, y send-and-settle para conducir una CLI de agente desde otra.
- 📖 **[Guía de arquitectura de Pseudo-TTY (PTY)](pty_architecture.es.md)** — Cómo funcionan por debajo, en Ruby, las seudoterminales, la lectura de flujos no bloqueante, la sanitización ANSI, la detección de indicaciones, la ejecución de scripts y el paso transparente bidireccional en vivo de `rune watch`.
- 📖 **[Guía de publicación](../releasing.md)** — Sincronización de versiones, verificación, procedencia, etiquetado y publicación de paquetes.

---

## Desarrollo y verificación

```sh
fledge run test         # Run RSpec test suite (405 examples, 87% line coverage)
fledge run lint         # Run RuboCop linter (0 offenses)
fledge lanes run verify # Full CI gate (lint + tests + strict 100%-coverage spec-sync)
fledge lanes run release # Verify, smoke-test, and build the release gem
fledge run smoke-test   # Runnable, assertion-based tour of real behavior (examples/smoke_test.rb)
COVERAGE=1 bundle exec rspec  # Same suite, plus an HTML coverage report at coverage/index.html
```

`examples/smoke_test.rb` es un script independiente, sin dependencias (no requiere bundler/rspec), que
ejercita `rune run`, `--timeout`, `TableParser`/`KeyValueParser`, `Script`, el reenvío de señales y
la detección de indicaciones contra el binario real de la CLI, con salida de acierto/fallo y un exit distinto de cero si falla.
Resulta útil como comprobación manual rápida, o en una máquina sin las dependencias de desarrollo instaladas.

---

## Licencia

MIT
