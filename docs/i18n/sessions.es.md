> Nota: este archivo es una traducción de `docs/sessions.md`; en caso de discrepancia, la versión en inglés es la fuente de verdad.

# Sesiones persistentes (`rune session`)

`rune run` lanza un comando, almacena todo en búfer y devuelve una vez. `rune watch` transmite una sesión
en vivo pero requiere un terminal humano real en stdin. Ninguno puede mantener abierto un hijo con forma de REPL a través de
llamadas `rune` separadas — así que un agente no tenía forma de *iniciar `codex`, enviar un prompt, esperar la
respuesta, enviar un seguimiento.*

`rune session` añade eso. El proceso hijo de una sesión con nombre sobrevive a la invocación de `rune` que
lo inició, y `send` se bloquea hasta que el hijo haya respondido realmente.

## Nombres: cada sesión tiene uno, rara vez tiene que elegirlo

Las sesiones tienen espacio de nombres por **directorio**: un proyecto es el basename del directorio de trabajo más un hash
de su ruta, así que dos git worktrees del mismo repositorio son dos espacios de nombres separados. `start` informa
aquel en el que se registró, y leer ese campo es la diferencia entre un desvío de cinco minutos y
una hora:

```console
$ rune session start --name reviewer -- grok
{"name":"reviewer","project":"myrepo-0a922f34","command":["grok"],"state":"running",...}
```

`read` desde el directorio incorrecto responde *"No such session"*, y `list` — que es lo que ese error sugiere
— muestra un array vacío, lo que se lee como confirmación de que la sesión murió en lugar de que está
parado en otro lugar.

```console
$ rune session start -- grok
{"name":"grok-amber","command":["grok"],"child_pid":68012,"supervisor_pid":67926,"state":"running"}
```

Omita `--name` y rune genera un nombre en clave `<tool>-<word>` no usado. Eso importa más de lo que
parece: "la sesión grok" deja de significar algo en el momento en que hay dos, y un agente que levanta
una no debería tener que inventar identificadores. Pase `--name reviewer` cuando quiera elegir.

Los nombres están **acotados a un proyecto** — el árbol de trabajo git que lo encierra, o el directorio mismo fuera
de uno. `reviewer` en un checkout y `reviewer` en otro son sesiones distintas, y ninguna es
alcanzable desde el directorio incorrecto:

```console
$ rune session list                  # this project only
$ rune session list --all-projects   # everything, labelled by project
```

## El ciclo

```console
$ rune session start --name grok -- grok
{"name":"grok","command":["grok"],"child_pid":68012,"supervisor_pid":67926,"state":"running"}
```

**Que `start` tenga éxito no significa que el hijo esté en ejecución.** Si el comando no existe, la
respuesta sigue siendo `status: "ok"` y `rune` sigue saliendo con 0 — con `state: "exited"` y
`exit_code: 127` en el cuerpo. El start en sí funcionó; el hijo murió al instante. Compruebe `state`,
no el estado de salida del proceso.

`start` retorna de inmediato y el proceso `rune` termina. `grok` sigue en ejecución, a cargo de un supervisor
desacoplado que posee su pty.

```console
$ rune session send --name grok --settle-ms 2500 "reply with exactly the word PONG"
```

`send` escribe el prompt, espera a que grok deje de producir salida durante 2.5s y devuelve **solo lo que
ese send produjo**. El estado persiste entre llamadas, porque es el mismo hijo cada vez:

Una flag mal escrita se rechaza en lugar de teclearse al hijo. `send --name grok --settle_ms 500
'echo HELLO'` (guion bajo, no guion) antes no coincidía con ninguna flag, así que la flag, su valor y el prompt
se unían en una sola línea y se escribían al agente — `status: ok`, y un modelo de pago respondiendo
`--settle_ms 500 echo HELLO`. La comprobación solo mira los tokens anteriores al primer operando y anteriores a
cualquier `--`, así que `start --name x claude --resume` sigue iniciando un agente con sus propias flags, y
`send --name x -- --settle_ms` sigue tecleando `--settle_ms` como entrada literal.

```console
$ rune session send --name s --settle-ms 300 "MEMORY=persisted"
$ rune session send --name s --settle-ms 300 'echo "value=$MEMORY"'
value=persisted
```

```console
$ rune session list
● grok-amber  running  idle 3s   grok
    Thought for 1s
● worker      running  idle 2m   bash --norc -i
    bash-3.2$

$ rune session stop --name grok-amber
```

Cada fila muestra cuánto tiempo la sesión ha estado en silencio y la última línea que imprimió — que es la
respuesta más rápida a *¿esta está funcionando o atascada, y qué está haciendo?* cuando varios agentes
están en ejecución a la vez. Los mismos campos (`idle_ms`, `last_line`) están en `--json`.

## Tomar el volante, y devolverlo

```console
$ rune session attach --name grok-amber
[rune session] attached — Ctrl-] to detach (session keeps running)
```

`attach` conecta su terminal real a una sesión en ejecución: la salida se transmite a su pantalla, sus
pulsaciones van al agente, la pantalla actual se reproduce al conectar para que no se quede mirando una
en blanco, y **el hijo se redimensiona a su terminal** (y lo sigue cuando redimensiona) para que un agente
a pantalla completa se disponga para su ventana en lugar del valor predeterminado headless. Al desconectar, el hijo vuelve
a ese valor predeterminado, así que los `send`s programáticos se renderizan igual tanto si se conectó como si no. **Ctrl-]** desconecta y deja todo en ejecución — esa es toda la diferencia respecto a
`rune watch`, que posee el hijo que lanzó. Ctrl-C deliberadamente *no* es la tecla de desconexión: tiene
que seguir llegando al hijo para que pueda interrumpir un agente descontrolado.

## Archivado

Una sesión detenida mantiene su nombre reservado y satura `list`. Archívela:

```console
$ rune session stop --name reviewer
$ rune session archive --name reviewer
$ rune session list --archived
```

Archivar libera el nombre y guarda la transcripción en el archivo del proyecto. Una sesión archivada está fuera del
alcance de `read` — `read --name` sobre ella informa que no existe tal sesión — así que extraiga lo que aún quiera
*antes* de archivar. Una sesión archivada
nunca puede confundirse con una en vivo, y reutilizar el nombre empieza genuinamente desde cero — `start` reinicia
la transcripción de modo que los cursores de `send` y los offsets de `read` siempre describen el mismo ciclo de vida.

## Saber cuándo el otro agente ha terminado

Esta es la parte difícil, y rune le da tres herramientas en orden de preferencia.

**`--settle-ms N` (predeterminado 800)** — devuelve una vez que el hijo ha estado en silencio durante N ms. Esta es la
señal principal. El reloj de settle solo empieza cuando llega salida que no es el eco del pty de su
propia entrada, así que un agente que hace eco de su prompt y luego piensa antes de responder devuelve la respuesta
en lugar de sus palabras de vuelta.

> **Un prompt que nunca se envía se ve exactamente igual, y es un bug distinto.** rune escribe el
> texto de un send y luego su carriage return como una escritura *separada* un momento después, porque una TUI que
> los lee juntos trata el return como parte del texto y nunca lo envía. Ese retraso es una carrera
> que nada puede observar: medido contra Kimi, los antiguos 0.05s perdieron 3 de 3 sends — el prompt se quedó en el
> campo de composición, `send` devolvió `settled: true` solo con el eco, y el hijo esperó una pulsación
> que ya había sido escrita. Ahora son 0.25s, y Claude Code, grok y Kimi todos envían. Si
> se encuentra una TUI aún más lenta, la señal es que `read --screen` muestra su texto parado en la caja de entrada:
> envíe una cadena vacía para entregar un carriage return solo, y se irá.

> **Limitación conocida, y la más aguda de rune hoy: un hijo que *redibuja* su entrada aún
> puede hacer settle sobre ella.** La regla anterior se cumple cuando el eco llega una sola vez. Un editor de
> línea que repinta la línea al enviar manda su entrada una segunda vez, y esa segunda copia
> cuenta como si el hijo hubiera hablado. Medido con `--settle-ms 800`: `irb` y `python3 -q` devuelven
> `settled: true` en aproximadamente un segundo solo con el eco, 3 de 3 veces cada uno, mientras que la respuesta
> real llega segundos después y cae en lo que capture la *siguiente* llamada. El `bash -i` puro no se
> ve afectado, incluidas las entradas que superan el ancho del terminal.
>
> **Nada en la respuesta distingue esto de una respuesta real** — `settled: true`,
> `busy_at_send: false`, y el eco es legítimamente parte de una respuesta correcta también. Hasta que se
> corrija, conduzca un REPL que se redibuja con `--wait-for-regex`, que no se ve afectado, o compruebe que la
> respuesta contiene algo más allá de lo que envió.

**`--wait-for-regex RE`** — devuelve tan pronto como la salida coincida. Determinista, y la opción correcta
siempre que sepa lo que el llamado imprime cuando termina:

```console
$ rune session send --name s --wait-for-regex '\$ $' "ls"
```

> **El patrón se compara contra la respuesta, no contra el eco de su entrada.** Un pty hace eco de
> lo que escribe, así que una implementación ingenua devuelve en el instante en que sus propias palabras
> vuelven. rune localiza el eco en texto *condensado* — escapes y espacios en blanco eliminados de
> ambos lados, que es la diferencia entre lo que envió y todo eco transformado que pudimos capturar —
> y veta una coincidencia cubierta por una copia repintada de la entrada. Medido contra `python3 -q`, cuyo REPL
> repinta por pulsación: antes devolvía en 0.22s con `matched: true`, ocho segundos antes de que
> el código se ejecutara, 4 de 4 veces; ahora espera la salida real, 3 de 3 veces.
>
> La afirmación honesta es *toda forma de eco que pudimos capturar de un hijo real está excluida*, no
> *no puede suceder*. Si su patrón es un literal que también envió, un hijo que cita su petición de vuelta
> palabra por palabra aún puede satisfacerlo. El veto también necesita *ver* la copia: un redibujado que una lectura del pty
> partió por la mitad — el frame termina a mitad del redibujado y el resto llega en la siguiente lectura — aún no es
> reconocible como copia, y un patrón que solo aparece dentro de su propia entrada puede ser satisfecho por
> esa mitad. Reproducido de forma determinista partiendo un frame justo después del token. Así que un
> patrón que también ocurre en lo que envió sigue siendo la forma a evitar.

> **Contra cuánta salida se compara el patrón: los 256 KB más recientes después del eco, releídos
> 32768 caracteres hacia atrás en cada lectura.** Este es un límite deliberado con dos consecuencias.
>
> - **Una coincidencia única de hasta 32768 caracteres siempre se encuentra**, por grande que crezca el turno,
>   porque cada barrido reanuda esa distancia detrás de donde paró el anterior. Cualquier cosa por la que
>   tenga sentido esperar — un marcador, un prompt, una cerca de cierre — queda holgadamente dentro.
> - **Una coincidencia única que tenga que abarcar más de 32768 caracteres nunca se encuentra.**
>   `OPEN[\s\S]*CLOSE` a lo largo de medio megabyte antes coincidía y ahora no; el send continúa hasta
>   `--settle-ms` o `--timeout-ms` en su lugar. Espere `CLOSE` por sí solo y use `read` si necesita
>   el tramo entre ambos.
>
> `\A` sigue anclando al inicio de la respuesta del hijo, no al inicio de la ventana — un
> patrón anclado no puede satisfacerse por dondequiera que la ventana haya comenzado. `^`, `$` y `\z`
> no se ven afectados. **La respuesta no está limitada por nada de esto:** `output` sigue siendo todo lo que el
> hijo produjo en el turno.
>
> Ese límite es lo que hace que una respuesta grande sea alcanzable. Antes, el patrón se comparaba contra
> el turno entero en cada lectura de 4 KB, lo cual es cuadrático en el turno — y en el único hilo del
> supervisor, así que también dejaba hambriento el drenaje del pty. Medido contra un hijo que emite N MB y luego
> imprime un marcador, con el mismo marcador como patrón:
>
> | salida | antes | después |
> | --- | --- | --- |
> | 4 MB | 11.85s, matched | 0.53s, matched |
> | 12 MB | 90.51s, `timed_out: true`, 11.46 MB de 12.00 leídos | 0.98s, matched, 12.15 MB leídos |
> | 48 MB | 112.43s, matched | 3.37s, matched |
>
> En 12 MB el send reportaba un timeout mientras retenía el 96% de una respuesta cuyo marcador el hijo
> ya había impreso.

**`--timeout-ms N` (predeterminado 120000)** — un tope rígido. Al expirar obtiene lo que se capturó más
`settled: false, timed_out: true` — un resultado, no un fallo. Fije este valor deliberadamente: el valor predeterminado es
generoso porque los agentes son lentos, así que una llamada equivocada cuesta dos minutos.

`--no-wait` escribe y devuelve de inmediato, para cuando no espera respuesta alguna. Su respuesta tiene
otra forma — `{action, name, sent: true, waited: false}`, sin `output`, `cursor` ni
`prompt_detected`, porque no se esperó nada.

`--no-newline` escribe el texto sin el carriage return final que lo envía, para componer una
línea en partes o conducir una TUI que lee pulsaciones.

### Los otros campos de una respuesta

- `settled: true` — **la espera fue atendida en lugar de agotar el tiempo.** Tres cosas distintas lo activan,
  y el campo compañero le dice cuál: el hijo se quedó en silencio durante la ventana de settle (sin campo
  compañero), `--wait-for-regex` coincidió (`matched: true`), o el hijo terminó (`child_exited: true`).
  Por sí solo **no** significa que el hijo se quedó en silencio — una coincidencia de regex lo activa sin ningún período de silencio,
  por eso una respuesta puede llevar `settled: true` a 0.45s de una ventana de settle de 60 segundos.

  Donde *sí* significa silencio, el silencio tiene tres causas y esto no puede distinguirlas: el turno
  terminó, el hijo está esperando a un humano, o **el hijo mandó un comando largo a segundo plano y dejó de
  imprimir**. Ese tercer caso es el que muerde: un llamador que sondeaba la desaparición de un
  marcador de ocupado leyó un frame sin él y concluyó que el trabajo había terminado, 260 segundos antes de que así fuera. Si
  está decidiendo sobre la *ausencia* de algo, `settled` no es evidencia suficiente por sí solo.
- `timed_out: true` — `--timeout-ms` se alcanzó primero. Un resultado, no un fallo.
- `matched: true` — `--wait-for-regex` coincidió.
- `child_exited: true` — el hijo terminó mientras el send estaba en curso.
- `busy_at_send: true` — el hijo *aún estaba produciendo salida* cuando este send llegó, así que la respuesta
  puede contener la cola del turno anterior. Vale la pena comprobarlo si una respuesta parece pertenecer a
  la pregunta anterior.
- `regex_timed_out: true` — el patrón de `--wait-for-regex` superó su presupuesto de coincidencia y fue
  abandonado. Casi siempre es un patrón con backtracking catastrófico; simplifíquelo.
- `dropped_bytes` — un recuento de salida anterior que el log ya no guarda: rotada, o perdida
  porque una escritura en la transcripción falló. **No** invalida un cursor de `--since`: los cursores siguen
  siendo absolutos, así que uno de antes de un descarte devuelve todo lo que aún se guarda *después* de él en lugar de un error.
  Un cursor que cae dentro de una región descartada se resuelve a la salida que siguió a la región —
  nunca a salida ya entregada, que llegaría con aspecto de salida nueva del turno actual.
- `transcript_gap_bytes` — solo en `status` y en una respuesta de `send`, y solo mientras aún se debe
  salida que ninguna escritura pudo registrar. Es la única ventana en la que el desfase no está en disco: la siguiente
  escritura exitosa lo registra y `read` lo reporta como `dropped_bytes` en su lugar.
- `screen_rows`, `screen_cols`, `screen_size_recorded` — solo con `--screen`: la geometría a la que
  se renderizó la pantalla, y si esa geometría es el winsize registrado del hijo o el fallback.
  Véase [Renderiza en el tamaño en el que el hijo está realmente en ejecución](#renderiza-en-el-tamaño-en-el-que-el-hijo-está-realmente-en-ejecución).

### `child_busy` e `idle_ms` están en `read`, no en `send`

Si el hijo ha imprimido algo dentro de la ventana de settle, y cuánto tiempo desde la última vez que lo hizo.
Esta es la forma estructurada de "¿sigue trabajando?": úselo en lugar de hacer grep en la UI del propio llamado
en busca de un marcador de ocupado, que es presentación y cambia sin aviso.

**Son campos de `read` y `list`, no de una respuesta de `send`.** Un `send` ya bloqueó hasta que el
hijo se asentó, así que pregunte después:

```console
$ rune session send --name grok --settle-ms 2500 "run the suite"
$ rune session read --name grok --tail 1 --json     # child_busy, idle_ms
```

Este documento listaba antes ambos entre los campos de una respuesta de `send`, lo cual es incorrecto de la forma que
más importa — un llamador que lee `.child_busy` de un `send` obtiene `nil`, y recae en hacer grep
a la UI, que es exactamente lo que estos campos existen para reemplazar.

Nótese que el nombre dice que el hijo está *imprimiendo*, no que está *trabajando*: un hijo que mandó un
comando a segundo plano y se quedó en silencio reporta `child_busy: false`.

### Encontrar algo en una transcripción larga

`--since` y `--tail` no ayudan cuando lo que busca está en el medio. Un día de trabajo con un agente
conducido llegó a 379KB.

```console
$ rune session read --name grok --grep 'THE BOARD' --context 2
```

Coincide con el texto *limpio* en lugar del stream bruto, porque los frames de redibujado de un agente
a pantalla completa parten palabras a través de secuencias de escape — un patrón que puede ver claramente en pantalla no coincidirá
con los bytes. La respuesta trae `grep_matches`.

**Limpio no es renderizado, y la diferencia muerde justo en los hijos que las sesiones existen para
conducir.** El texto limpio es el stream de redibujado entero con los escapes eliminados, así que: el historial
sobrescrito sigue coincidiendo, y vuelve como una línea limpia e independiente que la pantalla no ha mostrado desde
entonces; un frame pintado a golpes de cursor no tiene saltos de línea en absoluto, así que es una sola línea de grep, `--context` no hace
nada, y una coincidencia devuelve el frame entero bajo un `grep_matches: 1` de apariencia plausible; y un
patrón anclado a lo que puede ver en pantalla puede devolver `grep_matches: 0`, porque la adyacencia en
la pantalla no es adyacencia en el stream. Cuando la pregunta es *qué se muestra ahora mismo*, use
`--screen`. `--grep` sirve para encontrar una línea en una transcripción larga, que es en lo que es bueno.

Un patrón que no compila vuelve como `grep_error` en lugar de una excepción, y **no selecciona
nada**: `output` y `clean_output` están vacíos y `grep_matches` está ausente, que es cómo distingue
"el filtro nunca se ejecutó" de "el filtro no encontró nada". El read en sí sigue teniendo éxito, así que `cursor`,
`prompt_detected` y `child_busy` siguen todos ahí — ninguno depende del patrón, y
necesita el cursor para avanzar. (`send --wait-for-regex` es distinto: ahí el patrón decide
cuándo devolver, así que uno malo se rechaza de plano.)

### `prompt_detected` es solo indicativo

Todo resultado de `send`/`read` trae `prompt_detected`, pero **no condicione nada a él**, y sepa de qué lado falla.

Medido contra salida real: es `false` para texto plano, `false` para un `$ ` solo, **`false` para
`Do you want to proceed?`**, y `true` para `❯ `. Así que para grok es `true` en esencialmente cada lectura,
porque el compositor de grok siempre termina en `❯` — un llamador lo vio `true` 8 de 8 veces y concluyó
que no discriminaba nada. Sí discrimina; simplemente detecta *últimas líneas con forma de prompt*,
que no es la misma pregunta que "¿esto está esperando por mí". Nótese el tercer caso de arriba: es `false`
justamente para el diálogo de permiso que más querría que capturara. Para eso, mire la pantalla. Los patrones de prompt de rune
coinciden con prompts con forma de shell (`user@host:~$`, `[y/N]`, `Password:`) y son deliberadamente
conservadores. Los REPL de agentes en general no se parecen a ninguno de esos, así que justamente en las CLI que quiere conducir
suele ser `false`. Esperar un prompt se colgaría contra la mayoría de los objetivos reales — por eso
el tiempo de settle es la señal principal.

## Leer la transcripción

`read` reproduce la transcripción duradera de la sesión, y funciona igual esté la sesión viva o
ya detenida:

```console
$ rune session read --name grok --tail 50
$ rune session read --name grok --since 41234     # page from a cursor a previous call returned
```

Cada sesión escribe un log de eventos NDJSON en el mismo formato que produce `rune watch`, así que puede
seguir una sesión en vivo desde otro panel:

```console
$ tail -f ~/.rune/projects/<project>/sessions/grok/output.ndjson
```

Los agentes TUI a pantalla completa generan mucho tráfico de redibujado ANSI, así que prefiera `--tail`/`--max-output`
a leer una transcripción entera.

`--max-output=BYTES` conserva un comienzo y un final y marca la unión en el texto mismo:

```
...the last line before the cut
[rune] ==== 41233 bytes omitted by --max-output ====
the first line after it...
```

Sin esa línea la respuesta se lee como salida continua que el hijo nunca imprimió — medido, una
transcripción de 201 bytes con `--max-output=200` descartó el único byte que convertía `chsh -s /bin/zsh` en
`chsh -s bin/zsh`, una ruta distinta y aún plausible. El marcador es una anotación de rune, no
transcripción, así que no se descuenta de BYTES y una respuesta puede pasarse un poco del presupuesto;
`truncated` y `omitted_bytes` siguen siendo la respuesta autoritativa, ya que un hijo puede imprimir cualquier cosa,
incluida una línea que se parece al marcador.

### `--screen`: lo que el terminal muestra, no lo que llegó

Para un agente a pantalla completa este suele ser el campo que quiere. El stream de bytes contiene cada frame de
cada redibujado, con la respuesta partida entre ellos; la pantalla contiene solo lo que se muestra.

```console
$ rune session send --name grok --screen -- "reply with just the branch name"
$ rune session read --name grok --screen
```

Medido contra grok: una transcripción de 361KB se renderizó a una pantalla de 1.1KB, y una respuesta que el agente había
mostrado con claridad estaba **ausente del stream de bytes en 3 de 3 turnos y presente en la pantalla
renderizada en 3 de 3**. Si está buscando coincidencias en el contenido, coincida sobre `screen`.

Tres cosas que no es. Es el *estado final*, así que todo lo que se fue con el scroll desapareció — la transcripción
sigue siendo el registro de lo que ocurrió. Es opt-in porque solo tiene sentido para un hijo que
pinta una pantalla: para un shell en modo cooked el stream de bytes ya es la respuesta. Y **no
está limitado por los filtros de lectura** — `--since`, `--tail`, `--grep` y `--max-output` todos limitan
`output`/`clean_output` y dejan `screen` en paz. Sí está limitado, pero por la geometría: como máximo
`screen_rows x (screen_cols + 1)`, ambos devueltos en la misma respuesta. Una transcripción de 219,941 bytes
se renderiza a unos 2KB. Así que `--max-output=200 --screen` le da una respuesta limitada, limitada por una regla
que no nombró.

### Renderiza en el tamaño en el que el hijo está realmente en ejecución

El hijo de una sesión empieza en 40x120, y `attach` lo redimensiona al terminal que tomó el control — así que
el tamaño no es una constante, y renderizar en uno fijo produce una pantalla que nadie vio. El
supervisor registra el winsize actual del hijo en `meta.json` siempre que lo cambia, y `--screen`
renderiza en ese tamaño y lo informa de vuelta:

```console
$ rune session read --name grok --screen --json | jq '{screen_rows, screen_cols, screen_size_recorded}'
{ "screen_rows": 30, "screen_cols": 100, "screen_size_recorded": true }
```

Medido de extremo a extremo, con pyte 0.8.2 y GNU screen 4.00.03 reproduciendo los mismos bytes como
oráculos independientes (coincidieron exactamente entre sí en cada forma):

| lo que se ejercitó | filas erróneas antes | filas erróneas después |
|---|---|---|
| resize vía control socket a 30x100, el hijo redibuja en WINCH | 36/37 | **0/31** |
| lo mismo en 24x80 | 30/31 | **0/25** |
| lo mismo en 12x40 | 18/19 | **0/13** |
| lo mismo en 50x200 | 50/51 | **0/51** |
| lo mismo en 40x120 (los tamaños coinciden) | 0/41 | 0/41 |
| un `rune session attach` real desde un pty 30x100, el hijo ignora WINCH | 29/30 | **0/30** |

En la fila del attach los oráculos recibieron los bytes que ese terminal recibió de hecho, así que "0 de 30" significa
que la pantalla renderizada por rune coincidió, fila por fila, con lo que el humano estaba mirando.

**`screen_size_recorded` es cómo distingue una geometría real del fallback — no los números.** Una
sesión a la que se hizo attach desde un terminal de 40 filas registra exactamente el mismo 40x120 que usa el fallback, así que el
par por sí solo no puede cargar esa distinción. `screen_size_recorded` es true solo cuando el tamaño reportado
es el que `meta.json` realmente guardaba. Es false en tres casos, todos los cuales reportan 40x120:

- una sesión que nadie ha redimensionado. El supervisor pone el pty en 40x120 y no lo registra, así que el
  fallback aquí no es una conjetura — es el tamaño en el que el hijo está genuinamente en ejecución.
- un directorio de sesión escrito antes de que rune registrara tamaño alguno.
- un tamaño registrado que no es un terminal utilizable, que se descarta o se acota en lugar de asignarse:
  `meta.json` es un archivo en disco y la cuadrícula se construye de forma eager.

Un resize que llega por el control socket se acota a 300x1000 — por encima de cualquier terminal real — y el
acote se aplica tanto al pty como al registro, así que el hijo, el registro y el render siempre
coinciden. Los campos de winsize de un pty son de 16 bits, y un 65535x65535 registrado habría hecho que todo
`--screen` posterior manejara una cuadrícula de ese tamaño: en una transcripción deliberadamente hostil de 683KB, un `read --screen`
cuesta 0.76s en 40x120, 3.41s en el techo y 17.72s sin el acote.

**Un caso de resize sigue sin resolver.** Toda la transcripción retenida se renderiza en el tamaño *actual*
del hijo, así que si la geometría cambió a mitad de camino, la salida pintada antes del cambio se refluye al
nuevo. Para un agente a pantalla completa esto es correcto, y de forma demostrable: una TUI redibuja en SIGWINCH, y
en el attach el supervisor reproduce su backlog en el terminal al tamaño del terminal, que es
exactamente lo que reproduce renderizar toda la transcripción a ese tamaño — la fila de attach de 0 de 30 de arriba
se cumple incluso para un hijo que ignora SIGWINCH por completo. Queda sin resolver para un hijo que pinta una vez
y nunca redibuja *y* cuyo pty se redimensiona después bajo un terminal ya conectado, porque ese
terminal está refluyendo glifos que ya dibujó y no hay respuesta de referencia con la que comparar. Encogido
a mitad de stream de 40x120 a 24x80 en un stream así, GNU screen conservó solo la fila del cursor, pyte no conservó
nada, y los dos discreparon entre sí en una fila de lo poco que retuvieron. rune
conserva el contenido y lo refluye, así que difiere de ambos. Renderizar al antiguo tamaño fijo puntuó
mejor en el recuento crudo de filas ahí (15 erróneas contra 24), pero solo porque una pantalla mayormente en blanco
coincide por casualidad con un oráculo mayormente en blanco — no porque mostrara a nadie algo más verdadero.

**Se renderiza a partir de los últimos 512KB, y para algunos agentes eso tiene un costo visible.** Un censo de
la salida de grok a lo largo de 4.5MB encontró 109,364 movimientos absolutos de cursor, 31,798 corchetes de synchronised-update,
y **cero** borrados de ningún tipo — ningún `\e[K`, ningún `\e[2K`, ningún `\e[2J`, ninguna región de scroll. Un agente
que redibuja puramente posicionando y sobrescribiendo depende de que el terminal recuerde cada celda
que escribió, por antigua que sea. Renderizar desde una ventana parte de una cuadrícula en blanco, así que todo lo
pintado una vez y nunca redibujado — un encabezado, un banner — simplemente está ausente, y rune no puede saber que
falta. Leer `--screen` con más frecuencia no ayuda; la ventana se mide en bytes, no en
tiempo.

El mismo censo explica un punto más sutil. Cuando un agente nunca borra, una línea duplicada en pantalla
puede ser enteramente fiel: si su layout baja una fila y redibuja en la nueva posición, la
copia antigua no tiene nada que la quite, y **un terminal de verdad muestra el duplicado también**. Antes de tratar
una línea repetida como un bug de rune, compruebe si el agente borra algo en absoluto.

### Limitación conocida: un `--screen` en sondeo puede devolver un frame pintado a medias

Reportado a partir de uso real, y **no corregido**. Sondear `--screen` en un agente que se redibuja de vez en cuando
devuelve un frame a mitad de un redibujado — en el caso reportado, una línea duplicada en dos filas adyacentes.

Dos candidatas a corrección se midieron y se rechazaron. Comparar renderizados consecutivos y devolver solo uno
repetido midió **peor** que no hacer nada — 13 frames rasgados de 20 contra 11 — porque
un agente que pinta en ciclo rara vez renderiza el mismo frame dos veces, así que la comprobación agota el tiempo y
devuelve el frame rasgado de todos modos. Redefinir la estabilidad como quiescencia no pudo reproducir el rasgado en
absoluto: el mismo hijo dio 11/20 una vez y 0/20 dos veces, lo que significa que el harness no estaba midiendo
lo que parecía. Una corrección que falla en silencio hacia "parece listo" es peor que una limitación con la que
se puede planificar.

**Qué hacer al respecto.** No trate un solo frame renderizado como autoritativo para una decisión que no puede
deshacer. Si está leyendo un valor, sondee dos veces y exija coincidencia. Si está esperando un marcador,
`--wait-for-regex` es determinista donde `--screen` es una instantánea.

**Puede no ser culpa de rune.** Un censo de la salida de un agente a lo largo de 4.5MB encontró cero borrados de ningún
tipo, y un agente que nunca borra y desplaza su layout deja la copia antigua en pantalla — un terminal
de verdad muestra el duplicado también. El renderizador de rune coincide con un emulador independiente en seis
perfiles construidos a partir de ese censo. Antes de registrar una línea duplicada como un bug de rune, compruebe si el
agente borra algo en absoluto.

### La transcripción está acotada

Tanto el archivo como la memoria del supervisor tienen tope, así que una sesión dejada en ejecución un día no
crece sin límite. El tope del archivo se aplica dos veces: normalmente por rotación, y — cuando la rotación
no puede tener éxito en absoluto, porque el directorio quedó sin permiso de escritura o un disco se quedó lleno — por un
techo rígido al doble del tope, a partir del cual la salida se registra como descartada en lugar de escrita. De un modo u otro
`read` reporta `dropped_bytes` y los cursores siguen absolutos. Cuando la rotación descarta salida más antigua, `read` reporta `dropped_bytes` y los cursores
siguen absolutos — un cursor sigue nombrando la misma posición en el stream, solo que apunta a una salida que ya
no se guarda.

Una escritura de transcripción que falla — un disco lleno, un directorio sin permiso de escritura — descarta la salida del mismo modo,
salvo que en el *medio* de un stream que continúa después. Esos bytes se cargan y se registran
en cuanto la escritura se reanuda, y un cursor se mapea a través de cada región descartada en lugar de pasar un
total acumulado, de modo que la salida anterior a un hueco no se vuelve a entregar como si fuera nueva. Hasta que una escritura
tiene éxito no hay dónde registrar el hueco en disco, que es lo que `transcript_gap_bytes` en
`status` reporta.

## Qué saber antes de conducir un agente de verdad

- **`start` devuelve cuando el *supervisor* está listo, no el hijo.** Una CLI de agente tarda segundos en
  arrancar, y la entrada enviada antes de que esté escuchando simplemente se pierde. Espere un marcador de prontitud — sondee
  `read`, o haga del primer `send` un `--wait-for-regex` — antes de conducir una sesión recién iniciada.
- **Settle es una heurística.** Un hijo que pausa a mitad de respuesta más tiempo que `--settle-ms` devuelve una
  respuesta truncada. Súbalo, o use `--wait-for-regex`.
- **`--wait-for-regex` ve los 256 KB más recientes, no el turno entero.** Cualquier coincidencia única de hasta 32768
  caracteres siempre se encuentra; una coincidencia que tenga que abarcar más que eso nunca. Espere un
  marcador, no un patrón que abrace megabytes.
- **Una sola línea de 1024+ bytes desaparece en un hijo en modo cooked.** Eso es `MAX_CANON`, un
  límite del terminal, no de rune: la disciplina de línea no puede ensamblar una línea canónica más larga y la descarta
  en silencio — 1023 bytes llegan, 1024 no. La mayoría de las CLI de agente ejecutan su terminal en modo raw y
  no se ven afectadas (300KB llegan byte a byte). Un shell interactivo también: `bash --norc -i` usa
  readline, que pone el terminal en modo raw, y admite una línea de 1995 caracteres byte a byte. El
  límite muerde a un hijo que lee en modo *cooked* — un `cat` puro, o un script que lee stdin sin
  readline. Envíelo en trozos, o conduzca un objetivo en modo raw.
- Enter se envía como carriage return, que es lo que envía un terminal de verdad, así que las TUI en modo raw lo
  reciben. Los shells en modo cooked no se ven afectados.
- El pty del hijo recibe un tamaño de ventana explícito, porque una sesión desacoplada no tiene terminal de donde copiar
  uno y un pty sin definir es 0x0 — lo que deja a los agentes a pantalla completa renderizando en la nada. Empieza
  en 40x120, sigue a un terminal con attach mientras haya uno conectado (hasta un techo de
  300x1000), y vuelve a 40x120 cuando el último se va. `--screen` renderiza en el que de esos
  esté vigente.

## Dónde vive el estado

`RUNE_HOME` (predeterminado `~/.rune`), con permisos solo para el dueño:

```
$RUNE_HOME/projects/<project>/
  sessions/<name>/
    meta.json        0600   pid, supervisor pid, command, state, child terminal size
    output.ndjson    0600   full transcript
    supervisor.log   0600   supervisor stderr, for when something goes wrong
    control.sock     0600   the supervisor's control socket
  archive/<stamp>-<name>/   archived sessions, out of the live namespace
```

Defina `RUNE_HOME` para mantener las sesiones aisladas (pruebas, sandboxes, trabajo en paralelo).

`meta.json` se reemplaza por rename, nunca se trunca en el sitio, porque todo otro proceso de rune lo
lee para responder "¿existe esta sesión, y está viva?" sin ningún lock que tomar. Una ventana en la que estaba
corto era una ventana en la que `send` respondía "No such session" y `list` reportaba `state: dead`;
registrar el winsize del hijo lo convirtió en una escritura por resize, y un humano arrastrando el borde de una ventana emite
una por frame. Medido a través de un attach real arrastrado por 250 formas de ventana en 7.5 segundos, con
otro proceso leyendo meta en un bucle apretado: 90 de 294,728 lecturas volvieron ilegibles antes, 0 de
312,582 después.

## Cuánto cuesta ejecutar varias a la vez

Una sesión es un proceso supervisor, y ese aislamiento es deliberado: un agente atascado derriba
su propia sesión y nada más. El precio es un intérprete Ruby por sesión, y vale la pena
saberlo antes de desplegar varias.

Medido, con hijos inactivos:

| sesiones | memoria residente | descriptores |
|----------|-----------------|-------------|
| 24 | 543 MB | 648 |
| 60 | 1361 MB | 1620 |

Eso es **~23 MB y 27 descriptores por sesión**, constante — lo mismo en 60 que en 24, y sin cambio
a lo largo de rondas de sends. Así que el costo es predecible y lineal en lugar de sorprendente, pero está
cargado por adelantado: sesenta agentes cuestan bastante más de un gigabyte antes de que ninguno
haya hecho nada.

La concurrencia en sí se sostuvo en el mismo test: 60 starts simultáneos todos tuvieron éxito, cada send
llegó a la sesión a la que iba dirigido, `list` coincidió con la realidad, y no quedó nada en ejecución
después. Treinta llamadas simultáneas a `start` *sin* `--name` para la misma herramienta produjeron treinta
nombres en clave distintos y ninguna colisión.

## Alcance

rune es un **broker** de sesiones, no un bus de mensajes. Mantiene las sesiones y las direcciona por nombre;
decidir quién habla con quién es trabajo del agente que llama — ya tiene los nombres. El enrutamiento entre sesiones,
los perfiles por agente y un log de conversación compartido están deliberadamente fuera de alcance.
