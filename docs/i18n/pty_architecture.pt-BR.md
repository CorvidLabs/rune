*Esta é uma tradução de `docs/pty_architecture.md`. A versão em inglês é a autoritativa em caso de divergência.*

# Arquitetura de Pseudo-TTY (PTY) e TTY do Rune

> **Guia para Desenvolvedores e Agentes de IA**  
> *Entenda como o Ruby gerencia pseudoterminais, streams interativos e automação de prompts no `rune`.*

---

## 1. Visão geral: o que é um Pseudo-TTY (PTY)?

Quando um programa roda em um subshell ou pipe de subprocesso comum (por exemplo, `IO.pipe` ou execução padrão em subshell), o SO conecta pipes padrão para `stdin`, `stdout` e `stderr`. Muitos programas de linha de comando (como `git`, `docker`, `python`, `zsh`, `sudo`) detectam se `stdout` é um terminal (usando `isatty()`) e desativam cores, formatação de prompt ou o buffering por linha caso não seja.

Um **Pseudo-TTY (PTY)** é um par de dispositivos de terminal virtual, mestre e escravo, mantido no nível do kernel:
- **PTY escravo**: conectado ao processo filho como seu terminal controlador (`tty`). O processo filho acredita estar rodando dentro de um terminal real (como o iTerm2 ou o xterm).
- **PTY mestre**: pertence ao `rune` (`PTYRunner`). O `rune` lê a saída do processo filho e escreve a entrada de teclado diretamente no descritor mestre.

```
+------------------+         Master PTY          Slave PTY         +-------------------+
|  Rune PTYRunner  | <=======================> (Virtual Terminal) <==> |  Child Process    |
| (Agent / Human)  |    (reader / writer IO)                       | (bash, git, etc.) |
+------------------+                                               +-------------------+
```

---

## 2. Execução de PTY em Ruby (`PTY.spawn`)

A biblioteca padrão do Ruby fornece `require 'pty'`. O `rune` usa `PTY.spawn` dentro de `lib/rune/pty_runner.rb`:

```ruby
PTY.spawn(env, command) do |reader, writer, pid|
  # reader: IO object to read output from slave PTY
  # writer: IO object to write stdin into slave PTY
  # pid:    Process ID of child process
end
```

### Leitura de blocos sem bloqueio (`readpartial`)

A leitura padrão por linha (`reader.each_line`) bloqueia até que uma quebra de linha (`\n`) seja recebida. **Prompts interativos** (como `Password: `, `Select option [y/N]` ou `user@host:~$ `) **não terminam com uma quebra de linha**. Se você ler com `each_line`, o processo pai bloqueia esperando por `\n`, enquanto o processo filho fica parado esperando pela entrada do usuário — causando um **deadlock**.

Para eliminar deadlocks, o `rune` lê blocos usando `readpartial(4096)`:

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

Quando o processo filho termina, o PTY escravo é fechado e `readpartial` levanta `Errno::EIO` ou `EOFError`, que o `rune` captura para encerrar de forma limpa.

---

## 3. Sanitização ANSI e saída dupla (humano e agente)

O `rune` captura sequências de escape ANSI brutas do terminal (cores, movimentos de cursor, limpezas de tela).

- **Para humanos (modo TTY)**: a saída bruta é formatada com `Renderer.render_tty`, com cores completas e formatação interativa.
- **Para agentes de IA (modo JSON)**: a saída passa por `Parsers::TextSanitizer.strip_ansi(raw_output)` para remover os códigos ANSI, devolvendo texto limpo em prol da eficiência de tokens do LLM. Isso vale sem ressalvas apenas sem `--max-output`: essa flag limita os dois campos de forma independente ao mesmo orçamento, de modo que eles passam então a descrever janelas diferentes da execução e `clean_output` não é `strip_ansi(raw_output)`:

```ruby
# Strips SGR ANSI color codes, cursor escape codes, and terminal controls
ANSI_REGEX = /\e\[[0-9;]*[a-zA-Z]/
clean_output = text.gsub(ANSI_REGEX, '')
```

---

## 4. Lógica de detecção de prompt (`Parsers::PromptDetector`)

Para saber se um comando terminou ou está parado em um prompt interativo, `Parsers::PromptDetector` analisa os fragmentos de linha do stream:

### Assinaturas de prompt suportadas:
- Prompts PS1 de shell: `user@host:~$ `, `bash-5.2# `, `➜  rune git:(main)`, `❯ `
- Menus e escolhas interativas: `Select:`, `[y/N]`, `(y/n)?`, `Password: `

Duas assinaturas que esta lista costumava alegar **não** são detectadas, e foram removidas em vez de adicionadas, porque o conservadorismo do detector é deliberado: `Select an option: ` (o padrão de pergunta é ancorado, então casa com `Select:` mas não com uma frase terminada em dois-pontos) e `(venv) λ ` (`λ` não está na classe de glifos de prompt, que é `➜ ❯ ›`).

### Rejeição de falsos positivos:
`PromptDetector` ignora linhas que contêm comparações de código (`if x > 5`) ou atribuições de variáveis de shell (`export PATH=$PATH`). Uma citação em bloco de markdown como `> quote` também é rejeitada, mas por não casar com nenhum padrão positivo, e não por uma exclusão — a exclusão de citação em bloco só dispara em uma linha que também contenha texto entre sinais de menor/maior.

---

## 5. Motor de automação de scripts (`Rune::Script`)

O `rune` permite definir scripts DSL interativos para automatizar programas PTY de várias etapas:

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

O motor de scripts processa as etapas em uma única passagem sem bloqueio, de modo que `send_keys` escreve imediatamente em `writer` sem esperar pelos blocos seguintes.

---

## 6. Passthrough interativo ao vivo (`PTYWatcher` / `rune watch`)

`PTYRunner` armazena em buffer toda a saída de um comando e retorna assim que ele termina: correto para scripting e captura, mas errado para de fato sentar ao teclado e conduzir um programa interativo enquanto algo mais observa a sessão. `PTYWatcher` (`lib/rune/pty_watcher.rb`) é uma classe separada para esse caso ao vivo e bidirecional, em vez de um modo enxertado em `PTYRunner` — o modelo de execução (modo bruto de terminal, uma thread em segundo plano encaminhando a entrada) é diferente o bastante para não pertencer ali, e o contrato de `PTYRunner`, "executar, capturar, retornar uma vez", permanece congelado.

### Modo bruto de terminal (`io/console`)

Para que as teclas de seta e outras entradas de byte único ou sequências de escape cheguem ao filho, o terminal controlador do próprio processo *pai* precisa sair do modo cozido, no qual o kernel armazena a entrada em buffer por linha e ecoa localmente as teclas até que chegue uma quebra de linha. `io/console` (requerido explicitamente, não trazido implicitamente por `pty`) adiciona `IO#raw`, que `PTYWatcher#with_raw_input` envolve em torno de toda a sessão de encaminhamento:

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

A flag `entered` importa: uma vez que o modo bruto esteja de fato ativado, uma exceção não relacionada vinda das profundezas da sessão (um sink de saída quebrado, digamos) precisa se propagar normalmente, e não ser tratada como "modo bruto não é suportado" e silenciosamente reexecutar uma segunda vez toda a sessão já iniciada.

### Encaminhamento bidirecional

Diferente do laço de leitura único do `PTYRunner`, o `PTYWatcher` executa duas coisas ao mesmo tempo: uma thread em segundo plano encaminha as teclas reais do humano para o PTY do filho conforme elas chegam (`forward_input`), enquanto a thread principal consulta a saída do filho e a transmite imediatamente para a tela (`pump_output`), em vez de acumulá-la em um buffer devolvido apenas no fim.

Os dois caminhos decodificam com `UTF8StreamDecoder`, que retém um sufixo UTF-8 incompleto entre as chamadas de
`readpartial`. Um caractere multibyte válido é, portanto, preservado mesmo quando o kernel o divide entre blocos;
sequências genuinamente inválidas ou incompletas no fim continuam virando caracteres de substituição.

O `PTYWatcher` também espelha no PTY do filho o tamanho atual em linhas e colunas do terminal controlador.
Ele reconfere durante o laço de consulta da saída, de modo que um terminal redimensionado alcança o filho sem
trabalho inseguro dentro de um trap de sinal.

```
+------------------+   keystrokes    +------------------+   output    +-------------------+
|  Human terminal  | --------------> |  PTYWatcher       | ----------> |  Real terminal      |
|  (raw mode)      |  (bg thread)    |  (master PTY)     |  (live)     |  screen + NDJSON log |
+------------------+                 +------------------+             +-------------------+
```

### Log de eventos NDJSON

Todo bloco que chega à tela também é escrito como um evento NDJSON em um arquivo de log (por padrão, um arquivo
temporário `0600` anunciado e à prova de colisões, ou `--log=PATH`), de modo que um agente de IA possa acompanhar a
sessão ao vivo com `tail -f` sem que nenhum ruído JSON caia no terminal do próprio humano:

```json
{"event":"start","command":"...","pid":12345}
{"event":"output","bytes":42,"text":"..."}
{"event":"exit","exit_code":0}
```

Deliberadamente não é stderr por padrão: o stderr compartilha o terminal do humano com o passthrough ao vivo, e o uso
real mostrou de imediato que intercalar JSON em uma sessão interativa a tornava ilegível.

Se o sink de saída fechar com `EPIPE`, o `PTYWatcher` mata e recolhe o processo filho antes de devolver uma falha
estruturada, impedindo que um processo interativo desacoplado sobreviva ao watcher.

---

## 7. Tratamento de erros e códigos de saída

Tanto o `PTYRunner` quanto o `PTYWatcher` padronizam os códigos de saída Unix nos casos de borda:

| Condição | Código de saída | Tratamento |
| :--- | :--- | :--- |
| Saída normal | `status.exitstatus` | Conclusão limpa |
| Comando não encontrado | `127` | Captura `Errno::ENOENT` |
| Permissão negada | `126` | Captura `Errno::EACCES` |
| Tempo limite de execução (apenas `PTYRunner`) | `124` | Captura `Timeout::Error`, depois envia `SIGKILL` e recolhe o filho — `Timeout.timeout` interrompe apenas o fluxo de controle do próprio Ruby, não o processo do SO iniciado |
| Filho morto (sinal) | `128 + sig` | Sinais como `SIGKILL` (137) ou `SIGTERM` (143) |

---

## Resumo para desenvolvedores

O `rune` combina:
1. `PTY.spawn` para emulação real de terminal.
2. `readpartial` para leitura de stream sem deadlock.
3. `UTF8StreamDecoder` mais `TextSanitizer` para um JSON de agente limpo e seguro nas fronteiras de bytes.
4. `PromptDetector` para verificações inteligentes de interatividade.
5. DSL `Script` para entrada automatizada passo a passo.
6. `PTYWatcher` + modo bruto do `io/console` para sessões ao vivo, bidirecionais e conduzidas por humanos, com um log NDJSON que o agente pode acompanhar.
