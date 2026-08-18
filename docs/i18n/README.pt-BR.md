*Esta é uma tradução do README.md. A versão em inglês é a autoritativa.*

# rune

[![CI](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml/badge.svg)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-3.0%20%E2%80%93%204.0-CC342D?logo=ruby&logoColor=white)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)

Uma ferramenta de linha de comando e biblioteca em Ruby projetada desde o início para tratar **humanos e agentes de IA como cidadãos de primeira classe**.

O `rune` funciona como um executor universal de pseudo-terminal (PTY) e como uma ponte de dados estruturados para qualquer comando de CLI ou aplicação interativa de TUI.

Todo comando produz saída de terminal formatada e colorida para humanos e JSON estruturado para
agentes de IA. O `rune watch` ainda escreve um fluxo de eventos NDJSON ao vivo enquanto a pessoa conduz a
sessão. Mesma ferramenta, mesmos comandos, interface dupla.

O `rune session` vai um passo além: ele mantém uma CLI de agente — `claude`, `grok`, `codex` — aberta
entre invocações separadas, de modo que um agente possa conduzir outro conversacionalmente e uma pessoa possa se conectar
à mesma sessão e assumir o controle.

📖 Novo por aqui? Comece pelo **[guia de primeiros passos](docs/getting_started.md)**.

---

## Recursos

1. **Saída dupla (TTY para humanos / JSON e NDJSON para agentes)**
   - Modo terminal: saída formatada e colorida (`rune version`)
   - Modo JSON para agentes: `--json` ou detecção automática de pipe (`rune version | cat`)
   - Modo NDJSON para agentes: `--ndjson` para um envelope de resultado consistente (`rune version --ndjson`)
2. **Executor universal de processos em PTY (`rune run`)**
   - Inicia qualquer ferramenta de CLI ou TUI dentro de uma sessão de pseudo-terminal
   - Remove automaticamente códigos de escape ANSI, movimentos de cursor e sequências de controle
   - Desativa paginadores de terminal (`PAGER=cat`) para que as consultas retornem imediatamente sem travar
   - Mede a duração da execução do processo em milissegundos e detecta prompts interativos
3. **Parsers automáticos estruturados (`Rune::Parsers`)**
   - `TableParser`: converte tabelas de terminal delimitadas por espaços ou por barras verticais em arrays de hashes
   - `KeyValueParser`: converte saída de chave-valor (`key: val`) em hashes tipados
   - `TextSanitizer`: normaliza finais de linha e limpa códigos de escape ANSI
4. **DSL de scripts interativos (`Rune::Script`)**
   - DSL de automação de scripts de TUI passo a passo para conduzir prompts interativos de terminal e menus de TUI
5. **Passagem interativa ao vivo (`rune watch`)**
   - Coloca seu terminal em modo raw e encaminha as teclas ao processo filho ao vivo, byte a byte
   - Transmite a saída do processo filho para a sua tela conforme ela acontece (diferentemente do `rune run`, que
     armazena tudo em buffer e devolve ao final)
   - Ao mesmo tempo, registra cada bloco como um evento NDJSON em um arquivo temporário (caminho anunciado uma vez, ou
     `--log=PATH`), para que um agente de IA possa acompanhar a sessão ao vivo enquanto uma pessoa a conduz
6. **Sessões nomeadas persistentes (`rune session`)**
   - Mantém um processo filho em formato de REPL — `claude`, `grok`, `codex`, um shell — aberto *entre* invocações
     separadas do `rune`, algo que nem o `run` (que armazena em buffer e retorna uma única vez) nem o `watch` (que
     morre junto com seu processo filho) conseguem fazer
   - **Send-and-settle**: escreve a entrada, espera o processo filho ficar quieto e devolve exatamente a saída
     que aquele envio produziu, transformando um TTY assíncrono em uma chamada síncrona de requisição/resposta
   - `--screen` devolve o *terminal renderizado* em vez do fluxo bruto de bytes, o que importa
     porque um agente em tela cheia intercala sua resposta com os próprios repintes — uma transcrição
     medida passou de 361KB de tráfego de repinte para uma tela de 1,1KB
   - `attach` entrega a sessão ao vivo a um terminal humano e **Ctrl-]** a devolve, ainda em execução
   - As sessões são nomeadas, com escopo de projeto e arquiváveis; as transcrições são limitadas em disco e em
     memória, de modo que uma sessão deixada rodando por um dia não cresce sem limite

## Instalação

O nome de gem `rune` sem qualificação já está ocupado no registro público RubyGems.org por um
pacote não relacionado, então `gem install rune` de lá instala a coisa errada. Instale a fórmula
mantida e com checksum fixado a partir do tap Homebrew da CorvidLabs:

```sh
brew install corvidlabs/tap/rune
rune version --json
```

Atualize as versões seguintes pelo mesmo canal:

```sh
brew upgrade corvidlabs/tap/rune
```

Para desenvolvimento a partir do código-fonte:

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

---

## Exemplos de uso

### 0. Descubra a CLI

```sh
rune --help              # todos os comandos, mais as flags globais
rune run --help          # o uso de um comando e suas próprias flags
rune help watch          # a mesma coisa, escrita de outro jeito
```

A ajuda também é estruturada, de modo que um agente pode descobrir a superfície sem raspar texto:

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

> **Use `--` antes do comando encapsulado.** Toda flag do rune — `--json`, `--ndjson`, `--help`,
> `--timeout`, `--log` — é reconhecida *apenas* antes do primeiro `--`. É isso que faz com que
> `rune run -- gh pr list --json number` passe `--json` para o `gh` em vez de consumi-la. Sem o
> separador, o rune toma a flag para si e o comando encapsulado silenciosamente nunca a recebe.

### 1. Execute qualquer comando de CLI em modo JSON para agentes
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

### 2. Envelope de resultado NDJSON
```sh
rune run --ndjson -- fledge lanes run check
```
```json
{"event":"result","status":"ok","data":{"command":"fledge lanes run check","exit_code":0,"clean_output":"...","duration_ms":1652.8}}
```

O `rune run --ndjson` emite esse envelope único quando o comando termina. Use `rune watch` para um
fluxo ao vivo de eventos de saída.

### 3. Converta saída tabular de CLI em hashes
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

### 4. Conduza aplicações interativas de TTY / TUI
```ruby
require 'rune'

# Aciona um programa de TUI interativo com teclas de entrada
runner = Rune::PTYRunner.new("fledge plugins search --interactive", input: "\x03")
result = runner.run
# => Result com exit_code 130, clean_output, duration_ms
```

### 5. Acompanhe uma sessão ao vivo (a pessoa conduz, o agente acompanha)
```sh
# Coloca seu terminal em modo raw, encaminha suas teclas ao vivo — incluindo
# sequências de escape brutas como as setas, não apenas linhas inteiras — e
# transmite a saída para a sua tela conforme ela acontece. Registra um evento
# NDJSON por bloco em um arquivo temporário (anunciado uma vez, no início) para
# que um agente possa fazer `tail -f` ao vivo sem ruído JSON no seu terminal. O
# menu principal da demo é um seletor real de setas (↑/↓ + Enter, ou q para sair).
rune watch -- ruby examples/humans/demo_tui.rb

# Ou aponte o log para um lugar específico:
rune watch --log=/tmp/session.ndjson -- ruby examples/humans/demo_tui.rb
```

Em modo de agente — `--json`, `--ndjson`, ou sempre que a stdout não for um terminal — a passagem ao
vivo migra para a **stderr**, de modo que a stdout não carrega nada além do envelope de resultado. A
pessoa mantém sua visão ao vivo; o programa chamador recebe JSON limpo:

```sh
rune watch --json -- ruby examples/humans/demo_tui.rb 2>/dev/null | jq .data.log_path
```

### 6. Conduza uma CLI de agente a partir de outra (`rune session`)

O `run` armazena em buffer e retorna uma única vez; o `watch` precisa de uma pessoa em um terminal e
termina junto com seu processo filho. Nenhum dos dois consegue manter um REPL de agente aberto entre
chamadas. O `session` consegue:

```sh
# Inicia uma sessão nomeada. O processo filho sobrevive a este comando.
rune session start --name reviewer -- grok

# Envia um prompt e espera pela resposta. --screen devolve o terminal
# renderizado, que é onde a resposta é de fato legível.
rune session send --name reviewer --screen -- "Review lib/rune/session/supervisor.rb for races"

# Volte depois — de outro processo, de outro agente, de outra hora.
rune session send --name reviewer --screen -- "Now just the highest-severity one, in one line"

rune session list          # o que está rodando, há quanto tempo ocioso, o que imprimiu por último
rune session stop --name reviewer
```

**Por que `--screen` em vez da saída bruta.** Um agente em tela cheia repinta continuamente, então o
fluxo de bytes contém cada quadro de cada repinte, com a resposta dividida entre eles. Medido contra
o grok: uma transcrição de 361KB renderizou para uma tela de 1,1KB, e uma resposta que o agente havia
claramente exibido estava ausente do fluxo de bytes em 3 de 3 turnos e presente na tela renderizada em
3 de 3. Se você está fazendo correspondência por conteúdo, faça-a sobre o `screen`.

**Assuma o volante você mesmo** e depois devolva-o sem parar nada:

```sh
rune session attach --name reviewer   # Ctrl-] desanexa; a sessão continua rodando
```

As sessões têm escopo da árvore de trabalho git que as contém, então `reviewer` em dois checkouts são
duas sessões. Isso é deliberado, e também é a surpresa mais comum — se o `list` não mostrar nada,
verifique o diretório em que você está e o `RUNE_HOME`:

```sh
rune session list --all-projects
```

**Encontrar uma coisa em uma transcrição longa.** Um dia de trabalho com um agente conduzido chegou a
379KB, e nem `--since` nem `--tail` ajudam quando o que você quer está no meio:

```sh
rune session read --name reviewer --grep 'THE BOARD' --context 2
```

📖 Guia completo, incluindo o ajuste do settle e as limitações conhecidas:
**[docs/sessions.md](docs/sessions.md)**.

---

## Integração com a CorvidLabs

O `rune` se integra com a [cadeia de ferramentas de confiança da CorvidLabs](https://github.com/CorvidLabs):

- **[fledge](https://github.com/CorvidLabs/fledge)** — Executor de tarefas e ciclo de vida de projetos. O `rune` é um plugin nativo do `fledge` definido via `plugin.toml`. Instale diretamente com:
  ```sh
  fledge plugins install CorvidLabs/rune
  fledge rune run --json -- git status
  ```
- **[spec-sync](https://github.com/CorvidLabs/spec-sync)** — Aplicação de contratos (`specs/`)
- **[augur](https://github.com/CorvidLabs/augur)** — Pontuação de risco de mudanças

---

## Arquitetura e detalhes internos

- 📖 **[Guia de primeiros passos](docs/getting_started.md)** — Modos de saída, uso do `rune run`, timeouts e parsers com saída real de comandos.
- 📖 **[Guia de sessões persistentes](docs/sessions.md)** — `rune session`: sessões PTY nomeadas que sobrevivem a uma única invocação, e o send-and-settle para conduzir uma CLI de agente a partir de outra.
- 📖 **[Guia de arquitetura de pseudo-TTY (PTY)](docs/pty_architecture.md)** — Como pseudo-terminais, leitura não bloqueante de fluxos, sanitização de ANSI, detecção de prompts, execução de scripts e a passagem bidirecional ao vivo do `rune watch` funcionam por baixo dos panos em Ruby.
- 📖 **[Guia de release](docs/releasing.md)** — Sincronização de versões, verificação, procedência, tagueamento e publicação do pacote.

---

## Desenvolvimento e verificação

```sh
fledge run test         # Executa a suíte de testes RSpec (405 exemplos, 87% de cobertura de linhas)
fledge run lint         # Executa o linter RuboCop (0 ofensas)
fledge lanes run verify # Gate completo de CI (lint + testes + spec-sync estrito com 100% de cobertura)
fledge lanes run release # Verifica, faz smoke-test e constrói a gem de release
fledge run smoke-test   # Tour executável e baseado em asserções do comportamento real (examples/smoke_test.rb)
COVERAGE=1 bundle exec rspec  # Mesma suíte, mais um relatório HTML de cobertura em coverage/index.html
```

O `examples/smoke_test.rb` é um script autônomo e sem dependências (não requer bundler/rspec) que
exercita `rune run`, `--timeout`, `TableParser`/`KeyValueParser`, `Script`, o encaminhamento de sinais
e a detecção de prompts contra o binário real da CLI, com saída de aprovado/reprovado e um código de
saída diferente de zero em caso de falha. Útil como uma checagem manual rápida de sanidade, ou em uma
máquina sem as dependências de desenvolvimento instaladas.

---

## Licença

MIT
