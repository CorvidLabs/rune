*Esta é uma tradução de `docs/getting_started.md`. O inglês é a versão autoritativa em caso de divergência.*

# Primeiros passos com o rune

O `rune` é uma CLI e biblioteca Ruby feita para ser igualmente utilizável por um humano no terminal
e por um agente de IA que a controla programaticamente. Todo comando devolve o mesmo `Result`
estruturado — o que muda é apenas a *renderização*, de acordo com a forma como você o está chamando.

## Instalação

O nome de gem `rune`, sem qualificador, já está ocupado no registro público do RubyGems.org por um
pacote sem relação com este projeto, então `gem install rune` de lá instala a coisa errada. O
caminho de instalação suportado para o usuário final é a fórmula com checksum fixado no tap
Homebrew da CorvidLabs:

```sh
brew install corvidlabs/tap/rune
rune version --json
```

O Homebrew adiciona o tap automaticamente na primeira instalação. Para atualizar o Rune:

```sh
brew upgrade corvidlabs/tap/rune
```

Clone o código-fonte apenas se for desenvolver o próprio Rune:

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

Ou use como plugin do [fledge](https://github.com/CorvidLabs/fledge):

```sh
fledge plugins install CorvidLabs/rune
fledge rune run --json -- git status
```

## Descobrindo o que está disponível

```sh
rune --help              # or -h, or `rune help`
rune run --help          # or `rune help run`, or `rune run -h`
```

A ajuda de cada comando lista as flags próprias dele — `--timeout=SECONDS` no `rune run`,
`--log=PATH` no `rune watch` — junto com as globais. Ela também vem estruturada no modo agente, de
modo que a descoberta não exige interpretar a renderização humana:

```sh
$ rune run --help --json | jq -c '.data.flags'
[{"flag":"--timeout=SECONDS","description":"Kill the wrapped command after N seconds (default 30). Before `--` only."},{"flag":"--max-output=BYTES","description":"Bound clean_output/raw_output to BYTES each, keeping head+tail and marking the join with a `[rune] ==== N bytes omitted by --max-output ====` line. Mutually exclusive with --tail. Before `--` only."},{"flag":"--tail=N","description":"Keep only the last N lines of clean_output/raw_output. Mutually exclusive with --max-output. Before `--` only."},{"flag":"--separate-streams","description":"Adds clean_stdout/clean_stderr (stderr on a pipe, not the pty) alongside the merged view. Before `--` only."}]
```

As flags de ajuda seguem a mesma regra de separador que todo o resto (veja abaixo): `rune run -- mytool --help` repassa o `--help` para o `mytool`.

## Os três modos de saída

O `rune` escolhe o modo de renderização automaticamente com base em como foi invocado, ou você pode
forçar um deles explicitamente com uma flag. Os três modos executam exatamente a mesma lógica de
comando — o que muda é apenas o formato da saída.

### 1. Modo humano em TTY (padrão, terminal interativo)

Quando a stdout é um terminal de verdade e nenhuma flag `--json`/`--ndjson` é passada, o `rune`
imprime uma saída colorida e formatada para humanos:

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

### 2. Modo JSON para agentes (`--json`, ou detecção automática de pipe)

Passe `--json` explicitamente ou simplesmente redirecione a saída do `rune` para um pipe ou arquivo
— uma stdout que não é TTY muda a renderização para JSON automaticamente, sem precisar de flag:

```sh
$ ruby bin/rune run --json -- echo "hello agent"
{"status":"ok","data":{"command":"echo hello\\ agent","exit_code":0,"clean_output":"hello agent\n","raw_output":"hello agent\r\n","prompt_detected":false,"duration_ms":5.27}}
```

```sh
$ ruby bin/rune version | cat
{"status":"ok","data":{"name":"rune","version":"0.7.0","ruby":"4.0.6","ruby_platform":"arm64-darwin25","fledge":true,"specsync":true}}
```

> **`exit_code` é o status de saída do processo encapsulado, não um veredito sobre o trabalho.** Ele
> responde "o processo terminou, e como?", o que numa CLI para agentes é quase sempre `0` — inclusive
> em execuções cuja saída estava errada. Um chamador teve oito despachos consecutivos de `rune run`
> retornando `0`, vários deles produzindo conclusões que ele precisou corrigir depois. Se você
> precisa saber se o *trabalho* deu certo, isso tem que vir da saída, não desse campo. O `124` é a
> exceção que vale conhecer: significa que o rune matou o processo por causa do `--timeout`.

Toda resposta JSON tem o mesmo envelope: `{"status": "ok"|"error", "data": {...}}` (ou
`{"status": "error", "error": "..."}` em caso de falha).

O Rune escreve o envelope final na stdout tanto em caso de sucesso quanto de falha. Isso dá aos
agentes um único canal de resultado parseável, mas também significa que um humano que redireciona a
stdout redireciona junto as mensagens de erro do próprio Rune. A stderr fica reservada para avisos
operacionais e para o passthrough ao vivo do `rune watch`, que não podem corromper a stdout
estruturada.

As flags globais de saída só são reconhecidas antes do primeiro separador `--`. Os tokens depois
dele pertencem ao comando encapsulado e são preservados, então `rune run -- tool --json` repassa o
`--json` para o `tool`.

Uma `--flag` que o rune não conhece, na posição em que ficam as flags do próprio rune, é um erro, e
não algo repassado silenciosamente: `rune run --tiemout=5 -- echo hi` costumava tentar *executar* a
flag escrita errada e responder `status: ok` com `exit_code: 127`. Só os tokens anteriores ao
comando encapsulado são verificados, então `rune run cargo clippy --tests` e
`rune run -- mytool --tiemout=5` ficam intactos — uma vez visto o nome do comando, toda `--flag`
posterior pertence a ele.

### 3. Modo de envelope NDJSON para agentes (`--ndjson`)

A flag `--ndjson` embrulha o mesmo resultado em um envelope `{"event": "result"|"error", ...}` em
vez do formato simples `{"status": ...}` usado pelo `--json` — um formato que alguns harnesses de
agente esperam de maneira uniforme para todos os comandos, `rune run` incluído:

```sh
$ ruby bin/rune run --ndjson -- echo "hello stream"
{"event":"result","status":"ok","data":{"command":"echo hello\\ stream","exit_code":0,"clean_output":"hello stream\n","raw_output":"hello stream\r\n","prompt_detected":false,"duration_ms":11.45}}
```

No caso do `rune run`, isso continua sendo exatamente uma linha, emitida quando o comando termina —
o `PTYRunner` bufferiza a execução inteira e devolve um único `Result`, então aqui o `--ndjson` é
uma escolha de envelope, não streaming incremental. Para um fluxo de eventos ao vivo de verdade,
conforme um comando demorado ou interativo avança, veja o
[`rune watch`](#acompanhando-uma-sessão-ao-vivo-com-o-rune-watch) abaixo, que emite uma linha NDJSON por
bloco de saída, à medida que acontece.

## Executando comandos com o `rune run`

O `rune run` sobe qualquer comando de CLI ou TUI interativa dentro de um PTY de verdade, remove as
sequências de escape ANSI, desativa paginadores e mede o tempo de execução:

```sh
rune run -- git status
rune run --json -- npm test
rune run --ndjson -- fledge lanes run check
```

### Sobrescrevendo o timeout

Toda invocação do `rune run` tem um timeout padrão de 30 segundos. Para mudá-lo, use
`--timeout=SECONDS`, colocado *antes* do separador `--`, para que não seja confundido com uma flag
do comando encapsulado:

```sh
$ ruby bin/rune run --json --timeout=1 -- sleep 3
{"status":"ok","data":{"command":"sleep 3","exit_code":124,"clean_output":"\n[rune] Execution timed out after 1 seconds","raw_output":"\n[rune] Execution timed out after 1 seconds","prompt_detected":false,"duration_ms":1005.32}}
```

Um comando que estourou o tempo retorna o código de saída `124`, com a mensagem
`[rune] Execution timed out after N seconds` anexada à saída capturada — ainda é um `Result`
normal, não uma exceção.

**A saída capturada antes do kill é sempre retornada**, então um processo filho que imprimiu algo e
depois travou mostra o que imprimiu. Se a saída vier *vazia*, é porque o filho realmente não
imprimiu nada, e o rune diz isso junto com o motivo mais comum.

**O `rune run` não repassa a própria stdin para o processo filho.** O tty pertence ao humano —
tomá-lo é trabalho do `rune watch` — e repassar um pipe faria a entrada do próprio chamador ecoar de
volta pelo pty e cair no `clean_output`. Por isso `echo hi | rune run -- cat` estoura o tempo: o
`cat` fica esperando uma entrada que nunca chega. Coloque o redirecionamento dentro do comando, onde
o shell o executa dentro do pty:

```sh
$ rune run -- sh -c 'claude -p --output-format text < prompt.md'
```

Isso funciona, assim como passar um prompt de vários parágrafos como um único argumento — as quebras
de linha atravessam o argv intactas. O campo `command` da resposta é uma reconstrução de
*exibição*, com escape de shell, feita para humanos, e não o que o filho recebeu; não diagnostique
problemas de aspas a partir dele.

### Limitando a saída e separando os streams

Mais três flags, todas antes do separador `--`, todas mudando o *formato* do resultado:

- **`--max-output=BYTES`** limita `clean_output` e `raw_output` a BYTES cada um, mantendo o começo
  e o fim, e adiciona `truncated: true` com `omitted_bytes`. Duas coisas decorrem desse "cada um":
  os campos são limitados *separadamente*, então, sob essa flag, eles descrevem janelas diferentes
  da execução e `clean_output` não é `strip_ansi(raw_output)` — o `omitted_bytes` é a contagem do
  `clean_output`, e o `raw_output` carrega seu próprio marcador com um número diferente. E o
  `omitted_bytes` é medido em offsets no texto original, então bate exatamente em ASCII, mas
  desvia alguns bytes em texto multibyte, onde um corte pode partir um caractere ao meio. As duas
  metades são unidas por uma linha
  `[rune] ==== N bytes omitted by --max-output ====` em vez de emendadas direto, para que o texto
  retornado nunca pareça algo que o comando imprimiu: sem ela, uma transcrição de 201 bytes com
  `--max-output=200` perdeu exatamente o byte que transformava `chsh -s /bin/zsh` em
  `chsh -s bin/zsh`. Esse marcador é uma anotação do rune, não saída do comando, então não é
  descontado de BYTES, e uma resposta pode passar um pouquinho do orçamento.
- **`--tail=N`** mantém apenas as últimas N linhas, adicionando `truncated: true` com
  `omitted_lines`. É mutuamente exclusiva com `--max-output`; passar as duas é um erro, e não uma
  precedência silenciosa.
- **`--separate-streams`** adiciona `clean_stdout` e `clean_stderr` ao lado do `clean_output`
  mesclado, em vez de substituí-lo.

O `--separate-streams` tem um custo real, e é por isso que ele é opcional em vez de padrão: um pty
tem um único stream, então separá-los significa dar à stderr um pipe próprio. O filho então deixa de
enxergar um único terminal de controle para as duas, e um programa que verifica `isatty(2)` vai se
comportar como se seus erros estivessem sendo redirecionados — o que, para muitas CLIs, significa
abrir mão das cores ou mudar de vez para um modo não interativo. Use a flag quando precisar mais da
separação do que de o filho acreditar que está num terminal.

## Acompanhando uma sessão ao vivo com o `rune watch`

O `rune run` bufferiza toda a saída de um comando e só a devolve quando o comando termina — ótimo
para scripts e captura, mas inútil se o que você quer é sentar ao teclado e conduzir um programa
interativo enquanto outra coisa observa a sessão. O `rune watch` foi feito para isso: ele coloca seu
terminal em modo raw, repassa ao vivo cada tecla que você digita para o processo filho — incluindo
sequências de escape cruas, como as setas do teclado, não só linhas inteiras —, transmite a saída do
filho para a sua tela conforme ela acontece (e não no final) e, ao mesmo tempo, registra cada bloco
como um evento NDJSON — assim, um agente de IA pode acompanhar a sessão em tempo real enquanto um
humano a conduz.

```sh
# A small interactive demo program ships with rune specifically to try this against:
rune watch -- ruby examples/humans/demo_tui.rb
```

O log de eventos vai, por padrão, para um arquivo temporário à prova de colisão e acessível somente
ao dono (`0600`), e não para a stderr — misturar os eventos NDJSON no mesmo terminal do passthrough
ao vivo era o design original, e o uso real mostrou de cara que esse padrão estava errado (o JSON
intercalado deixava a sessão ilegível). O caminho é anunciado uma vez, logo no começo:

```
[rune watch] live event log: /tmp/rune-watch-20260728-12345-abcd.ndjson
```

Rode `tail -f` nesse caminho a partir de outro painel (ou deixe um agente acompanhando) para ver a
sessão ao vivo, com o seu terminal continuando limpo. Para apontar para um lugar específico, use
`--log=PATH`:

```sh
rune watch --log=/tmp/session.ndjson -- ruby examples/humans/demo_tui.rb
```

Cada linha do log é um objeto JSON: `{"event":"start","command":"...","pid":...}`, depois um
`{"event":"output","bytes":N,"text":"..."}` por bloco, conforme ele é transmitido, e por fim
`{"event":"exit","exit_code":N}` quando o filho termina.

### O `rune watch` em modo agente

O `rune watch` segue as mesmas regras de modo de saída que todos os outros comandos. Com `--json`,
`--ndjson`, ou sempre que a stdout não for um terminal, o passthrough ao vivo passa para a **stderr**
e a stdout carrega apenas o envelope de resultado — assim, um programa que envolve o rune consegue
parsear a stdout diretamente, enquanto o humano ao teclado continua vendo a sessão dele:

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

Tire o `2>/dev/null` para continuar acompanhando a sessão você mesmo enquanto o JSON é capturado em
outro lugar.

O `rune watch` exige um terminal de verdade (ele se recusa a rodar se a stdin não for um TTY — não
existe um modo não interativo que faça sentido) e não funciona sob a inception de PTY do próprio
`rune run`, então não dá para demonstrá-lo num exemplo com pipe, como é feito no resto deste guia. O
menu principal do `examples/humans/demo_tui.rb` é um seletor de verdade, navegado pelas setas (↑/↓ +
Enter, ou `q` para sair), em vez do clássico digite-um-número-e-aperte-Enter, justamente para
exercitar o repasse de bytes crus e de sequências de escape — o que um menu puramente bufferizado
por linha nunca toca. O comentário no topo do próprio `examples/humans/demo_tui.rb` traz comandos
prontos para copiar e colar, e `spec/rune/pty_watcher_spec.rb` mostra como a mecânica de
repasse/registro por baixo é testada em unidade, incluindo um teste que conduz o menu de setas de
ponta a ponta (um objeto de terminal falso somado a `IO.pipe`s conduz um processo filho interativo
de verdade, sem precisar de um terminal de controle real).


### Limitando um watch

Dois limites independentes, ambos antes do separador `--`, ambos desligados por padrão:

- **`--timeout=SECONDS`** mata a sessão após N segundos de tempo de relógio, por mais ocupada que
  ela esteja.
- **`--idle-timeout=SECONDS`** mata a sessão após N segundos **sem nenhuma saída e nenhuma
  entrada** — é o que você quer para "este agente parou de fazer qualquer coisa", já que um build
  demorado não está ocioso.

Qualquer um dos dois devolve o código de saída `124`, com `timed_out: true` e um `timeout_kind` de
`"timeout"` ou `"idle_timeout"` indicando qual deles disparou.
## Parseando texto estruturado

`Rune::Parsers::TableParser` e `Rune::Parsers::KeyValueParser` transformam a saída não estruturada
do terminal em hashes Ruby:

```ruby
require 'rune'

Rune::Parsers::TableParser.parse(<<~TABLE)
  NAME           STATUS   VERSION
  fledge-plugin  active   1.0.0
TABLE
# => [{ name: 'fledge-plugin', status: 'active', version: '1.0.0' }]
```

O `TableParser.parse` aceita um argumento nomeado `format:` (`:auto` por padrão, ou `:pipe`/`:space`
para forçar um modo de parsing) — veja
[`specs/parsers/parsers.spec.md`](../../specs/parsers/parsers.spec.md) para conhecer as limitações
conhecidas da heurística antes de confiar no `:auto` para uma saída desconhecida.

## Próximos passos

- [`examples/smoke_test.rb`](../../examples/smoke_test.rb) — `ruby examples/smoke_test.rb` ou `fledge run smoke-test`.
  Um passeio autônomo, baseado em asserções, pelo comportamento real (sem precisar de
  bundler/rspec): modos de saída, validação do `--timeout`, parsers, `Script`, repasse de sinais e
  detecção de prompt.
- [`examples/humans/demo_tui.rb`](../../examples/humans/demo_tui.rb) — a demo interativa usada em toda a
  seção sobre `rune watch` acima. [`examples/agents/pty_runner_example.rb`](../../examples/agents/pty_runner_example.rb),
  [`table_parser_example.rb`](../../examples/agents/table_parser_example.rb) e
  [`script_automation_example.rb`](../../examples/agents/script_automation_example.rb) são scripts
  menores, cada um com um único conceito — todos executáveis diretamente
  (`ruby examples/agents/<name>.rb`), sem nenhuma preparação além do
  `require_relative '../lib/rune'`.
- [Guia de arquitetura do PTY](pty_architecture.pt-BR.md) — como funcionam internamente o runner de PTY,
  a leitura dos streams, a detecção de prompt e o passthrough ao vivo do `rune watch`.
- [`specs/`](../../specs/) — contratos de módulo verificados por máquina (`spec-sync`) para `cli`,
  `parsers`, `pty_runner`, `session` e `watch`.
- [`AGENTS.md`](../../AGENTS.md) — convenções para adicionar novos comandos e trabalhar com o
  toolchain de trust.
