> Esta página traduce [`docs/getting_started.md`](../getting_started.md). En caso de discrepancia, el original en inglés es la fuente de verdad.

# Primeros pasos con rune

`rune` es una CLI y biblioteca de Ruby diseñada para ser igualmente usable por una persona en una terminal y por un agente de IA que la controle de forma programática. Cada comando devuelve el mismo `Result` estructurado — solo el
*renderizado* cambia según cómo lo invoques.

## Instalación

El nombre de gema `rune` sin cualificar ya está ocupado en el registro público de RubyGems.org por un
paquete no relacionado, así que `gem install rune` allí instala el paquete equivocado. La vía de instalación soportada para el usuario final
es la fórmula con checksum fijado del tap de Homebrew de CorvidLabs:

```sh
brew install corvidlabs/tap/rune
rune version --json
```

Homebrew añade el tap automáticamente en la primera instalación. Actualiza Rune con:

```sh
brew upgrade corvidlabs/tap/rune
```

Clona el código fuente solo cuando desarrolles Rune:

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

O como plugin de [fledge](https://github.com/CorvidLabs/fledge):

```sh
fledge plugins install CorvidLabs/rune
fledge rune run --json -- git status
```

## Descubrir qué hay disponible

```sh
rune --help              # or -h, or `rune help`
rune run --help          # or `rune help run`, or `rune run -h`
```

La ayuda de cada comando lista las banderas propias de ese comando — `--timeout=SECONDS` para `rune run`, `--log=PATH` para
`rune watch` — junto con las globales. También está estructurada en modo agente, así que el descubrimiento no
requiere parsear el renderizado humano:

```sh
$ rune run --help --json | jq -c '.data.flags'
[{"flag":"--timeout=SECONDS","description":"Kill the wrapped command after N seconds (default 30). Before `--` only."},{"flag":"--max-output=BYTES","description":"Bound clean_output/raw_output to BYTES each, keeping head+tail and marking the join with a `[rune] ==== N bytes omitted by --max-output ====` line. Mutually exclusive with --tail. Before `--` only."},{"flag":"--tail=N","description":"Keep only the last N lines of clean_output/raw_output. Mutually exclusive with --max-output. Before `--` only."},{"flag":"--separate-streams","description":"Adds clean_stdout/clean_stderr (stderr on a pipe, not the pty) alongside the merged view. Before `--` only."}]
```

Las banderas de ayuda siguen la misma regla del separador que todo lo demás (más abajo): `rune run -- mytool --help`
pasa `--help` a `mytool`.

## Los tres modos de salida

`rune` elige un modo de renderizado automáticamente según cómo se invoque, o puedes forzar uno
explícitamente con una bandera. Los tres modos ejecutan exactamente la misma lógica del comando — solo cambia el formato
de salida.

### 1. Modo TTY humano (predeterminado, terminal interactiva)

Cuando stdout es una terminal real y no se pasa ninguna bandera `--json`/`--ndjson`, `rune` imprime
salida coloreada y formateada para personas:

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

### 2. Modo JSON para agentes (`--json`, o detección automática de tubería)

Pasa `--json` explícitamente, o simplemente canaliza o redirige la salida de `rune` — un stdout que no es TTY cambia
el renderizado a JSON automáticamente, sin necesidad de bandera:

```sh
$ ruby bin/rune run --json -- echo "hello agent"
{"status":"ok","data":{"command":"echo hello\\ agent","exit_code":0,"clean_output":"hello agent\n","raw_output":"hello agent\r\n","prompt_detected":false,"duration_ms":5.27}}
```

```sh
$ ruby bin/rune version | cat
{"status":"ok","data":{"name":"rune","version":"0.7.0","ruby":"4.0.6","ruby_platform":"arm64-darwin25","fledge":true,"specsync":true}}
```

> **`exit_code` es el estado de salida del proceso envuelto, no un veredicto sobre el trabajo.** Responde a "¿terminó
> el proceso, y de qué manera?", que para una CLI de agente es casi siempre `0` — incluso en ejecuciones cuya
> salida era incorrecta. Un invocador tuvo ocho llamadas consecutivas a `rune run` que devolvieron `0`, varias de
> las cuales produjeron conclusiones que después tuvo que corregir. Si necesitas saber si el *trabajo*
> tuvo éxito, eso debe obtenerse de la salida, no de este campo. `124` es la excepción que conviene
> conocer: significa que rune mató el proceso por `--timeout`.

Todas las respuestas JSON tienen el mismo envoltorio: `{"status": "ok"|"error", "data": {...}}` (o
`{"status": "error", "error": "..."}` en caso de error).

Rune escribe el envoltorio final en stdout tanto en caso de éxito como de error. Eso da a los agentes un
único canal de resultado analizable, pero también significa que una persona que redirige stdout redirige también los mensajes
de error a nivel de Rune. Stderr queda reservado para avisos operativos y para el paso directo en vivo de `rune watch`
que no debe corromper el stdout estructurado.

Las banderas globales de salida solo se reconocen antes del primer separador `--`. Los tokens posteriores pertenecen al
comando envuelto y se conservan, así que `rune run -- tool --json` pasa `--json` a `tool`.

Una `--flag` que rune no conoce, en la posición donde van las banderas propias de rune, es un error y no
algo que se pase en silencio: `rune run --tiemout=5 -- echo hi` antes intentaba *ejecutar* la
bandera mal escrita y respondía `status: ok` con `exit_code: 127`. Solo se comprueban los tokens anteriores al comando
envuelto, así que `rune run cargo clippy --tests` y `rune run -- mytool --tiemout=5` quedan
intactos — una vez visto el nombre del comando, toda `--flag` posterior le pertenece.

### 3. Modo de envoltorio NDJSON para agentes (`--ndjson`)

`--ndjson` envuelve el mismo resultado en un envoltorio `{"event": "result"|"error", ...}` en lugar de la
forma simple `{"status": ...}` que usa `--json` — un formato que algunos harnesses de agentes esperan de manera uniforme para
cada comando, incluido `rune run`:

```sh
$ ruby bin/rune run --ndjson -- echo "hello stream"
{"event":"result","status":"ok","data":{"command":"echo hello\\ stream","exit_code":0,"clean_output":"hello stream\n","raw_output":"hello stream\r\n","prompt_detected":false,"duration_ms":11.45}}
```

Para `rune run`, sigue siendo exactamente una línea, emitida cuando el comando termina — `PTYRunner`
almacena en búfer toda la ejecución y devuelve un único `Result`, así que `--ndjson` aquí es una elección de envoltorio, no
un flujo incremental. Para un flujo de eventos en vivo de verdad, a medida que avanza un comando de larga duración o interactivo,
consulta [`rune watch`](#observar-una-sesión-en-vivo-con-rune-watch) más abajo, que emite una
línea NDJSON por cada fragmento de salida en el momento en que ocurre.

## Ejecutar comandos con `rune run`

`rune run` lanza cualquier comando CLI o TUI interactiva dentro de un PTY real, elimina las secuencias de escape
ANSI, desactiva los paginadores y mide el tiempo de ejecución:

```sh
rune run -- git status
rune run --json -- npm test
rune run --ndjson -- fledge lanes run check
```

### Modificar el tiempo de espera

Cada invocación de `rune run` tiene un tiempo de espera predeterminado de 30 segundos. Modifícalo con `--timeout=SECONDS`,
colocado *antes* del separador `--` para que no se confunda con una bandera del comando
envuelto:

```sh
$ ruby bin/rune run --json --timeout=1 -- sleep 3
{"status":"ok","data":{"command":"sleep 3","exit_code":124,"clean_output":"\n[rune] Execution timed out after 1 seconds","raw_output":"\n[rune] Execution timed out after 1 seconds","prompt_detected":false,"duration_ms":1005.32}}
```

Un comando que agota el tiempo de espera devuelve el código de salida `124` con un mensaje
`[rune] Execution timed out after N seconds` añadido a la salida capturada — sigue siendo un `Result` normal, no una excepción.

**La salida capturada antes de matar el proceso siempre se devuelve**, así que un hijo que imprimió y luego se quedó colgado muestra
lo que imprimió. Si la salida está *vacía*, el hijo realmente no imprimió nada, y rune lo indica
junto con la razón más común.

**`rune run` no reenvía su propio stdin al hijo.** Un tty pertenece a la persona — tomarlo
es el trabajo de `rune watch` — y reenviar una tubería devolvería la propia entrada del invocador a través del pty
y hacia `clean_output`. Así que `echo hi | rune run -- cat` agota el tiempo de espera: `cat` está esperando una entrada que
nunca llega. Pon la redirección dentro del comando, donde el shell la realiza en el pty:

```sh
$ rune run -- sh -c 'claude -p --output-format text < prompt.md'
```

Eso funciona, y también pasar un prompt de varios párrafos como un único argumento — los saltos de línea sobreviven
intactos en argv. El campo `command` de la respuesta es una reconstrucción de *visualización*, con el
entrecomillado del shell ya aplicado, pensada para personas — no es lo que recibió el hijo; no diagnostiques
problemas de comillas a partir de él.

### Limitar la salida y separar los flujos

Tres banderas más, todas antes del separador `--`, y todas cambian la *forma* del resultado:

- **`--max-output=BYTES`** limita `clean_output` y `raw_output` a BYTES cada uno, conservando el principio
  y el final, y añade `truncated: true` con `omitted_bytes`. De "cada uno" se siguen dos cosas:
  los campos se limitan *por separado*, así que con esta bandera describen ventanas distintas de la
  ejecución y `clean_output` no es `strip_ansi(raw_output)` — `omitted_bytes` es el recuento de `clean_output`
  y `raw_output` lleva su propio marcador con uno distinto. Y `omitted_bytes` se
  mide en desplazamientos sobre el original, así que cuadra exactamente en ASCII pero se desvía unos
  bytes en texto multibyte, donde un corte puede partir un carácter. Las dos mitades se unen con una
  línea `[rune] ==== N bytes omitted by --max-output ====` en lugar de empalmarse, de modo que el texto devuelto
  nunca se lee como algo que el comando imprimió: sin ella, una transcripción de 201 bytes con
  `--max-output=200` eliminaba exactamente el byte que convertía `chsh -s /bin/zsh` en
  `chsh -s bin/zsh`. Ese marcador es una anotación de rune, no la salida del comando, así que no
  se descuenta de BYTES y una respuesta puede pasarse un poco del presupuesto.
- **`--tail=N`** conserva solo las últimas N líneas, y añade `truncated: true` con `omitted_lines`.
  Es mutuamente excluyente con `--max-output`; pasar ambas es un error, no una precedencia silenciosa.
- **`--separate-streams`** añade `clean_stdout` y `clean_stderr` junto a la
  `clean_output` fusionada, en lugar de reemplazarla.

`--separate-streams` tiene un costo real, por eso hay que activarlo explícitamente y no es el valor predeterminado: un pty tiene
un solo flujo, así que separarlos implica darle a stderr su propia tubería. El hijo entonces ya no ve una
única terminal de control para ambos, y un programa que comprueba `isatty(2)` se comportará como si
sus errores se estuvieran redirigiendo — lo que en muchas CLIs significa perder el color, o pasar
por completo a un modo no interactivo. Úsalo cuando necesites la separación más de lo que necesitas que el hijo
crea que está en una terminal.

## Observar una sesión en vivo con `rune watch`

`rune run` almacena en búfer toda la salida de un comando y solo la devuelve cuando el comando termina — ideal
para scripts y captura, pero no sirve si realmente quieres sentarte al teclado y controlar un
programa interactivo mientras algo más observa la sesión. `rune watch` está pensado para eso: pone
tu terminal en modo raw, reenvía en vivo cada pulsación que escribes al hijo — incluidas
secuencias de escape en bruto como las teclas de flecha, no solo líneas enteras — transmite la salida del hijo a tu
pantalla a medida que ocurre (no al final), y al mismo tiempo registra cada fragmento como un evento NDJSON — para que
un agente de IA pueda seguir la sesión en tiempo real mientras una persona la controla.

```sh
# A small interactive demo program ships with rune specifically to try this against:
rune watch -- ruby examples/humans/demo_tui.rb
```

El registro de eventos usa por defecto un archivo temporal a prueba de colisiones, solo para el propietario (`0600`), no stderr — mezclar
eventos NDJSON en la misma terminal que el paso directo en vivo era el diseño original, y el uso
real mostró de inmediato que era el valor predeterminado equivocado (el JSON intercalado hacía la sesión
ilegible). La ruta se anuncia una sola vez, al principio:

```
[rune watch] live event log: /tmp/rune-watch-20260728-12345-abcd.ndjson
```

Haz `tail -f` de esa ruta desde otro panel (o que un agente la siga) para observar la sesión en vivo, con
tu propia terminal limpia. Dirígelo a una ruta concreta con `--log=PATH`:

```sh
rune watch --log=/tmp/session.ndjson -- ruby examples/humans/demo_tui.rb
```

Cada línea del registro es un objeto JSON: `{"event":"start","command":"...","pid":...}`, luego un
`{"event":"output","bytes":N,"text":"..."}` por cada fragmento a medida que llega, y después
`{"event":"exit","exit_code":N}` cuando el hijo termina.

### `rune watch` en modo agente

`rune watch` sigue las mismas reglas de modo de salida que cualquier otro comando. Con `--json`, `--ndjson`,
o siempre que stdout no sea una terminal, el paso directo en vivo se mueve a **stderr** y stdout lleva
solo el envoltorio del resultado — así un programa envolvente puede parsear stdout directamente mientras la persona al
teclado sigue viendo su sesión:

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

Quita el `2>/dev/null` para seguir observando la sesión tú mismo mientras el JSON se captura en otro sitio.

`rune watch` requiere una terminal real (se niega a ejecutarse si stdin no es un TTY — no hay
un modo no interactivo con sentido) y no funciona sobre la propia inception de PTY de `rune run`, así que no puede
demostrarse en un ejemplo canalizado como el resto de esta guía. El menú de nivel superior de `examples/humans/demo_tui.rb`
es un selector real con teclas de flecha (↑/↓ + Enter, o `q` para salir) en lugar de escribir-un-número-y-pulsar-
Enter, precisamente para ejercitar el reenvío de bytes sueltos y de secuencias de escape en bruto — lo que un menú
puramente con búfer de línea nunca toca. El comentario de cabecera de `examples/humans/demo_tui.rb` tiene comandos
listos para copiar y pegar, y `spec/rune/pty_watcher_spec.rb` muestra cómo se prueban unitariamente los mecanismos
subyacentes de reenvío y registro, incluido un test que conduce el propio menú de flechas de punta a punta (un objeto de terminal
falsa más `IO.pipe`s conduce un proceso hijo interactivo real sin necesidad de una terminal de control
real).

### Limitar un watch

Dos límites independientes, ambos antes del separador `--`, ambos desactivados por defecto:

- **`--timeout=SECONDS`** mata la sesión después de N segundos de reloj, por muy ocupada que esté.
- **`--idle-timeout=SECONDS`** la mata después de N segundos **sin salida y sin entrada** — el que
  quieres para "este agente ha dejado de hacer nada", ya que una compilación larga no está inactiva.

Cualquiera de los dos da el código de salida `124`, con `timed_out: true` y un `timeout_kind` de `"timeout"` o
`"idle_timeout"` que indica cuál se disparó.

## Parsear texto estructurado

`Rune::Parsers::TableParser` y `Rune::Parsers::KeyValueParser` convierten la salida no estructurada de la terminal
en hashes de Ruby:

```ruby
require 'rune'

Rune::Parsers::TableParser.parse(<<~TABLE)
  NAME           STATUS   VERSION
  fledge-plugin  active   1.0.0
TABLE
# => [{ name: 'fledge-plugin', status: 'active', version: '1.0.0' }]
```

`TableParser.parse` acepta una palabra clave `format:` (`:auto` por defecto, o `:pipe`/`:space` para forzar
un modo de análisis) — consulta [`specs/parsers/parsers.spec.md`](../../specs/parsers/parsers.spec.md) para las
limitaciones conocidas de la heurística antes de confiar en `:auto` con una salida desconocida.

## Siguientes pasos

- [`examples/smoke_test.rb`](../../examples/smoke_test.rb) — `ruby examples/smoke_test.rb` o `fledge
  run smoke-test`. Un recorrido independiente, basado en aserciones, del comportamiento real (no requiere bundler/rspec):
  modos de salida, validación de `--timeout`, parsers, `Script`, reenvío de señales, detección de prompts.
- [`examples/humans/demo_tui.rb`](../../examples/humans/demo_tui.rb) — la demo interactiva usada a lo largo de la
  sección de `rune watch` de más arriba. [`examples/agents/pty_runner_example.rb`](../../examples/agents/pty_runner_example.rb),
  [`table_parser_example.rb`](../../examples/agents/table_parser_example.rb) y
  [`script_automation_example.rb`](../../examples/agents/script_automation_example.rb) son scripts más pequeños,
  de un solo concepto — cada uno se puede ejecutar directamente (`ruby examples/agents/<name>.rb`) sin más preparación que
  `require_relative '../lib/rune'`.
- [Guía de arquitectura PTY](pty_architecture.es.md) — cómo funcionan internamente el PTY runner, la lectura de flujos, la
  detección de prompts y el paso directo en vivo de `rune watch`.
- [`specs/`](../../specs/) — contratos de módulo comprobados por máquina (`spec-sync`) para `cli`, `parsers`,
  `pty_runner`, `session` y `watch`.
- [`AGENTS.md`](../../AGENTS.md) — convenciones para añadir comandos nuevos y trabajar con la cadena de
  herramientas de confianza.
