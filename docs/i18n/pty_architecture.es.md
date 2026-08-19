> Esta es una traducción de `docs/pty_architecture.md`. El inglés es la versión autorizada cuando haya discrepancias.

# Arquitectura de Pseudo-TTY (PTY) y TTY de Rune

> **Guía para desarrolladores y agentes de IA**  
> *Cómo Ruby gestiona los seudoterminales, los flujos interactivos y la automatización de prompts en `rune`.*

---

## 1. Visión general: ¿qué es un Pseudo-TTY (PTY)?

Cuando un programa se ejecuta en un subshell o pipe de subproceso normal (p. ej. `IO.pipe` o la ejecución estándar en un subshell), el SO conecta pipes estándar para `stdin`, `stdout` y `stderr`. Muchos programas CLI (como `git`, `docker`, `python`, `zsh`, `sudo`) detectan si `stdout` es una terminal (usando `isatty()`) y desactivan los colores, el formato del prompt o el buffering por línea si no lo es.

Un **Pseudo-TTY (PTY)** es un par de dispositivos de terminal virtual, maestro y esclavo, a nivel del kernel:
- **Slave PTY**: conectado al proceso hijo como su terminal de control (`tty`). El proceso hijo cree que se está ejecutando dentro de una terminal real (como iTerm2 o xterm).
- **Master PTY**: pertenece a `rune` (`PTYRunner`). `rune` lee la salida del proceso hijo y escribe la entrada del teclado directamente en el descriptor maestro.

```
+------------------+         Master PTY          Slave PTY         +-------------------+
|  Rune PTYRunner  | <=======================> (Virtual Terminal) <==> |  Child Process    |
| (Agent / Human)  |    (reader / writer IO)                       | (bash, git, etc.) |
+------------------+                                               +-------------------+
```

---

## 2. Ejecución de PTY en Ruby (`PTY.spawn`)

La biblioteca estándar de Ruby proporciona `require 'pty'`. `rune` usa `PTY.spawn` dentro de `lib/rune/pty_runner.rb`:

```ruby
PTY.spawn(env, command) do |reader, writer, pid|
  # reader: IO object to read output from slave PTY
  # writer: IO object to write stdin into slave PTY
  # pid:    Process ID of child process
end
```

### Lectura de chunks sin bloqueo (`readpartial`)

La lectura estándar por línea (`reader.each_line`) se bloquea hasta que se recibe un salto de línea (`\n`). Los **prompts interactivos** (como `Password: `, `Select option [y/N]` o `user@host:~$ `) **no terminan con un salto de línea**. Si se lee con `each_line`, el proceso padre se bloquea esperando `\n`, mientras el proceso hijo espera la entrada del usuario, lo que provoca un **deadlock**.

Para eliminar deadlocks, `rune` lee chunks usando `readpartial(4096)`:

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

Cuando el proceso hijo termina, el slave PTY se cierra y `readpartial` lanza `Errno::EIO` o `EOFError`, que `rune` captura para finalizar de forma limpia.

---

## 3. Sanitización ANSI y salida dual (humano y agente)

`rune` captura las secuencias de escape ANSI crudas del terminal (colores, movimientos del cursor, limpiezas de pantalla).

- **Para humanos (modo TTY)**: la salida cruda se formatea usando `Renderer.render_tty` con color completo y formato interactivo.
- **Para agentes de IA (modo JSON)**: la salida se procesa a través de `Parsers::TextSanitizer.strip_ansi(raw_output)` para eliminar los códigos ANSI y devolver texto limpio, en aras de la eficiencia de tokens del LLM. Esto es válido sin matices solo cuando no se usa `--max-output`: esa flag limita ambos campos de forma independiente al mismo presupuesto, así que a partir de ahí describen ventanas distintas de la ejecución, y `clean_output` deja de ser `strip_ansi(raw_output)`:

```ruby
# Strips SGR ANSI color codes, cursor escape codes, and terminal controls
ANSI_REGEX = /\e\[[0-9;]*[a-zA-Z]/
clean_output = text.gsub(ANSI_REGEX, '')
```

---

## 4. Lógica de detección de prompts (`Parsers::PromptDetector`)

Para distinguir si un comando terminó o está detenido en un prompt interactivo, `Parsers::PromptDetector` analiza los fragmentos de línea del stream:

### Firmas de prompt soportadas:
- Prompts PS1 de shell: `user@host:~$ `, `bash-5.2# `, `➜  rune git:(main)`, `❯ `
- Menús y opciones interactivas: `Select:`, `[y/N]`, `(y/n)?`, `Password: `

Dos firmas que esta lista solía reivindicar **no** se detectan, y se eliminaron en lugar de añadirse, porque el conservadurismo del detector es deliberado: `Select an option: ` (el patrón de pregunta está anclado, así que coincide con `Select:` pero no con una frase que termina en dos puntos) y `(venv) λ ` (`λ` no está en la clase de glifos de prompt, que es `➜ ❯ ›`).

### Rechazo de falsos positivos:
`PromptDetector` ignora las líneas que contienen comparaciones de código (`if x > 5`) o asignaciones de variables de shell (`export PATH=$PATH`). Una cita en bloque de markdown como `> quote` también se rechaza, pero por no coincidir con ningún patrón positivo y no por una exclusión — la exclusión de citas en bloque solo se activa en una línea que también contiene texto entre signos de menor y mayor.

---

## 5. Motor de automatización de scripts (`Rune::Script`)

`rune` permite definir scripts DSL interactivos para automatizar programas PTY de varios pasos:

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

El motor de scripts procesa los pasos en una única pasada sin bloqueo, de modo que `send_keys` escribe de inmediato en `writer` sin esperar a chunks posteriores.

---

## 6. Passthrough interactivo en vivo (`PTYWatcher` / `rune watch`)

`PTYRunner` almacena en buffer toda la salida de un comando y retorna cuando este termina: correcto para scripting y captura, pero incorrecto para sentarse realmente al teclado y conducir un programa interactivo mientras algo más observa la sesión. `PTYWatcher` (`lib/rune/pty_watcher.rb`) es una clase separada para ese caso en vivo y bidireccional, no un modo injertado en `PTYRunner` — el modelo de ejecución (modo raw del terminal, un hilo en segundo plano que reenvía la entrada) es lo bastante distinto como para no pertenecer ahí, y el contrato de `PTYRunner` de «ejecutar, capturar, retornar una vez» permanece congelado.

### Modo raw del terminal (`io/console`)

Para que las teclas de flecha y otras entradas de un solo byte o secuencias de escape lleguen al hijo, el terminal de control del propio proceso *padre* tiene que salir del modo cooked, en el que el kernel almacena la entrada en buffer por línea y hace eco local de las pulsaciones hasta que llega un salto de línea. `io/console` (se requiere de forma explícita; `pty` no lo trae implícitamente) añade `IO#raw`, que `PTYWatcher#with_raw_input` envuelve alrededor de toda la sesión de reenvío:

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

La flag `entered` importa: una vez que el modo raw está realmente activado, una excepción no relacionada que venga de lo profundo de la sesión (un sink de salida roto, por ejemplo) debe propagarse con normalidad, no tratarse como «el modo raw no está soportado» y volver a ejecutar en silencio, por segunda vez, toda la sesión ya iniciada.

### Reenvío bidireccional

A diferencia del único bucle de lectura de `PTYRunner`, `PTYWatcher` ejecuta dos cosas a la vez: un hilo en segundo plano reenvía las pulsaciones reales del humano al PTY del hijo según llegan (`forward_input`), mientras el hilo principal consulta la salida del hijo y la transmite a la pantalla de inmediato (`pump_output`), en lugar de acumularla en un buffer que solo se devuelve al final.

Ambos caminos decodifican con `UTF8StreamDecoder`, que retiene un sufijo UTF-8 incompleto entre las llamadas a `readpartial`. Un carácter multibyte válido se preserva, por tanto, incluso cuando el kernel lo parte entre chunks; las secuencias genuinamente inválidas o incompletas al final siguen convirtiéndose en caracteres de reemplazo.

`PTYWatcher` también refleja el tamaño actual en filas y columnas del terminal de control sobre el PTY del hijo. Lo vuelve a comprobar durante el bucle de consulta de la salida, de modo que un terminal redimensionado llega al hijo sin trabajo inseguro dentro de un trap de señal.

```
+------------------+   keystrokes    +------------------+   output    +-------------------+
|  Human terminal  | --------------> |  PTYWatcher       | ----------> |  Real terminal      |
|  (raw mode)      |  (bg thread)    |  (master PTY)     |  (live)     |  screen + NDJSON log |
+------------------+                 +------------------+             +-------------------+
```

### Log de eventos NDJSON

Cada chunk que llega a la pantalla también se escribe como un evento NDJSON en un archivo de log (por defecto un archivo temporal `0600` anunciado y a prueba de colisiones, o `--log=PATH`), de modo que un agente de IA pueda hacer `tail -f` de la sesión en vivo sin que ningún ruido JSON aterrice en el propio terminal del humano:

```json
{"event":"start","command":"...","pid":12345}
{"event":"output","bytes":42,"text":"..."}
{"event":"exit","exit_code":0}
```

Deliberadamente no es stderr por defecto: stderr comparte el terminal del humano con el passthrough en vivo, y el uso real mostró de inmediato que intercalar JSON en una sesión interactiva la volvía ilegible.

Si el sink de salida se cierra con `EPIPE`, `PTYWatcher` mata y recolecta al hijo antes de devolver un fallo estructurado, lo que impide que un proceso interactivo desprendido sobreviva al watcher.

---

## 7. Manejo de errores y códigos de salida

`PTYRunner` y `PTYWatcher` estandarizan los códigos de salida de Unix en los casos límite:

| Condición | Código de salida | Manejo |
| :--- | :--- | :--- |
| Salida normal | `status.exitstatus` | Finalización limpia |
| Comando no encontrado | `127` | Captura `Errno::ENOENT` |
| Permiso denegado | `126` | Captura `Errno::EACCES` |
| Tiempo de espera de ejecución (solo `PTYRunner`) | `124` | Captura `Timeout::Error`, luego envía `SIGKILL` y recolecta al hijo — `Timeout.timeout` solo interrumpe el flujo de control del propio Ruby, no el proceso del SO iniciado |
| Hijo terminado (señal) | `128 + sig` | Señales como `SIGKILL` (137) o `SIGTERM` (143) |

---

## Resumen para desarrolladores

`rune` combina:
1. `PTY.spawn` para emulación real de terminal.
2. `readpartial` para lectura de stream sin deadlocks.
3. `UTF8StreamDecoder` más `TextSanitizer` para un JSON de agente limpio y seguro en los límites de bytes.
4. `PromptDetector` para comprobaciones inteligentes de interactividad.
5. DSL `Script` para entrada automatizada paso a paso.
6. `PTYWatcher` + modo raw de `io/console` para sesiones en vivo, bidireccionales y conducidas por humanos, con un log NDJSON al que un agente puede hacer tail.
