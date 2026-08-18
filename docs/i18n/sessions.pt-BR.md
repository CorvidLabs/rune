> Nota: este arquivo é uma tradução de `docs/sessions.md`; em caso de divergência, a versão em inglês é a fonte de verdade.

# Sessões persistentes (`rune session`)

O `rune run` sobe um comando, guarda tudo em buffer e retorna uma única vez. O `rune watch`
transmite uma sessão ao vivo, mas exige um terminal humano de verdade no stdin. Nenhum dos dois
consegue manter aberto um processo filho no formato de um REPL ao longo de chamadas separadas do
`rune` — ou seja, um agente não tinha como *iniciar o `codex`, mandar um prompt, esperar a resposta
e mandar uma nova pergunta.*

É isso que o `rune session` acrescenta. O processo filho de uma sessão nomeada sobrevive à invocação
do `rune` que a iniciou, e o `send` fica bloqueado até o filho ter de fato respondido.

## Nomes: toda sessão tem um, e você raramente precisa escolher

As sessões têm namespace por **diretório**: um projeto é o basename do diretório de trabalho mais um
hash do seu caminho, então dois git worktrees do mesmo repositório são dois namespaces distintos. O
`start` informa em qual deles a sessão foi registrada, e ler esse campo é a diferença entre um desvio
de cinco minutos e um de uma hora:

```console
$ rune session start --name reviewer -- grok
{"name":"reviewer","project":"myrepo-0a922f34","command":["grok"],"state":"running",...}
```

Um `read` disparado do diretório errado responde *"No such session"*, e o `list` — justamente o que
essa mensagem de erro sugere — mostra um array vazio, o que soa como a confirmação de que a sessão
morreu, e não de que você está parado em outro lugar.

```console
$ rune session start -- grok
{"name":"grok-amber","command":["grok"],"child_pid":68012,"supervisor_pid":67926,"state":"running"}
```

Omita o `--name` e o rune gera um codinome `<tool>-<word>` ainda não utilizado. Isso importa mais do
que parece: "a sessão do grok" deixa de significar alguma coisa no instante em que existem duas, e um
agente que sobe uma delas não deveria precisar inventar identificadores. Passe `--name reviewer`
quando quiser escolher.

Os nomes têm **escopo de projeto** — a working tree do git que envolve o diretório ou, fora de uma,
o próprio diretório. `reviewer` em um checkout e `reviewer` em outro são sessões diferentes, e
nenhuma delas é alcançável a partir do diretório errado:

```console
$ rune session list                  # this project only
$ rune session list --all-projects   # everything, labelled by project
```

## O ciclo

```console
$ rune session start --name grok -- grok
{"name":"grok","command":["grok"],"child_pid":68012,"supervisor_pid":67926,"state":"running"}
```

**O `start` ter dado certo não significa que o filho está rodando.** Se o comando não existe, a
resposta ainda vem com `status: "ok"` e o `rune` ainda sai com 0 — só que com `state: "exited"` e
`exit_code: 127` no corpo. O start em si funcionou; o filho morreu na hora. Confira o `state`, e não
o código de saída do processo.

O `start` retorna imediatamente e o processo `rune` encerra. O `grok` continua rodando, sob um
supervisor desacoplado que é o dono do pty dele.

```console
$ rune session send --name grok --settle-ms 2500 "reply with exactly the word PONG"
```

O `send` escreve o prompt, espera o grok passar 2,5s sem produzir saída e devolve **apenas o que
aquele send gerou**. O estado persiste entre as chamadas, porque é sempre o mesmo processo filho:

Uma flag escrita errado é recusada, em vez de ser digitada no filho. O `send --name grok
--settle_ms 500 'echo HELLO'` (com underscore, não hífen) antes não casava com flag nenhuma, então a
flag, o valor dela e o prompt eram juntados em uma única linha e escritos no agente — `status: ok`,
e um modelo pago respondendo `--settle_ms 500 echo HELLO`. A verificação só olha os tokens que vêm
antes do primeiro operando e antes de qualquer `--`, então `start --name x claude --resume` continua
iniciando um agente com as flags dele próprio, e `send --name x -- --settle_ms` continua digitando
`--settle_ms` como entrada literal.

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

Cada linha mostra há quanto tempo a sessão está calada e a última linha que ela imprimiu — que é a
resposta mais rápida para *esta aqui está trabalhando ou travada, e o que ela está fazendo?* quando
você tem vários agentes rodando ao mesmo tempo. Os mesmos campos (`idle_ms`, `last_line`) estão
disponíveis no `--json`.

## Assumindo o volante — e devolvendo depois

```console
$ rune session attach --name grok-amber
[rune session] attached — Ctrl-] to detach (session keeps running)
```

O `attach` liga o seu terminal de verdade a uma sessão em andamento: a saída aparece na sua tela, o
que você digita vai para o agente, a tela atual é reexibida na conexão para você não ficar encarando
uma tela em branco, e **o filho é redimensionado para o tamanho do seu terminal** (e acompanha as
mudanças conforme você redimensiona), de modo que um agente de tela cheia se ajuste à sua janela em
vez do padrão headless. Quando você desconecta, o filho volta a esse padrão, então os `send`
programáticos são renderizados igual, tendo você feito attach ou não. O **Ctrl-]** desconecta e
deixa tudo rodando — é justamente aí que está a diferença para o `rune watch`, que é dono do filho
que ele mesmo criou. O Ctrl-C deliberadamente *não* é a tecla de desconexão: ele precisa continuar
chegando ao filho para você conseguir interromper um agente fora de controle.

## Arquivamento

Uma sessão parada continua com o nome reservado e ainda polui o `list`. Arquive-a:

```console
$ rune session stop --name reviewer
$ rune session archive --name reviewer
$ rune session list --archived
```

Arquivar libera o nome e guarda o transcript no arquivo morto do projeto. Uma sessão arquivada fica
fora do alcance do `read` — um `read --name` nela informa que a sessão não existe —, então tire dela
tudo o que você ainda quiser *antes* de arquivar. Uma sessão arquivada nunca pode ser confundida com
uma viva, e reutilizar o nome começa realmente do zero: o `start` zera o transcript, de modo que os
cursores do `send` e os offsets do `read` sempre descrevem um mesmo ciclo de vida.

## Saber quando o outro agente terminou

Essa é a parte difícil, e o rune te dá três ferramentas, em ordem de preferência.

**`--settle-ms N` (padrão 800)** — retorna assim que o filho ficar N ms em silêncio. Esse é o sinal
principal. O relógio do settle só começa a correr quando chega alguma saída que não seja o eco, feito
pelo pty, da sua própria entrada; assim, um agente que ecoa o seu prompt e só então pensa antes de
responder devolve a resposta, e não as suas palavras de volta.

> **Um prompt que nunca é submetido tem exatamente essa mesma cara, e é outro bug.** O rune escreve o
> texto de um send e, um instante depois, escreve o carriage return em uma operação *separada*,
> porque uma TUI que lê os dois juntos trata o return como parte do texto e nunca submete. Esse
> atraso é uma corrida que nada consegue observar: medido contra o Kimi, os antigos 0,05s perderam
> 3 de 3 sends — o prompt ficava parado no campo de composição, o `send` retornava `settled: true`
> só com o eco, e o filho esperava por uma tecla que já tinha sido escrita. Hoje são 0,25s, e Claude
> Code, grok e Kimi submetem todos. Se você topar com uma TUI ainda mais lenta, o sinal é o
> `read --screen` mostrando o seu texto parado na caixa de entrada: mande uma string vazia para
> entregar um carriage return sozinho, que ele vai.

> **Limitação conhecida, e a mais afiada do rune hoje: um filho que *redesenha* a sua entrada ainda
> pode dar settle em cima dela.** A regra acima vale quando o eco chega uma única vez. Um editor de
> linha que repinta a linha ao submeter manda a sua entrada uma segunda vez, e essa segunda cópia
> conta como se o filho tivesse falado. Medido com `--settle-ms 800`: `irb` e `python3 -q` retornam
> `settled: true` em cerca de um segundo apenas com o eco, 3 vezes em 3 cada um, enquanto a resposta
> de verdade chega segundos depois e cai no que a *próxima* chamada capturar. O `bash -i` puro não é
> afetado, nem mesmo com entradas que passam da largura do terminal.
>
> **Nada na resposta distingue isso de uma resposta de verdade** — `settled: true`,
> `busy_at_send: false`, e o eco também faz parte, legitimamente, de uma resposta correta. Enquanto
> isso não for corrigido, conduza um REPL que repinta com `--wait-for-regex`, que não é afetado, ou
> verifique se a resposta traz algo além do que você mandou.

**`--wait-for-regex RE`** — retorna assim que a saída casar com o padrão. É determinístico e é a
escolha certa sempre que você souber o que o programa do outro lado imprime ao terminar:

```console
$ rune session send --name s --wait-for-regex '\$ $' "ls"
```

> **O padrão é casado contra a resposta, não contra o eco da sua entrada.** Um pty ecoa o que você
> escreve, então uma implementação ingênua retorna no instante em que as suas próprias palavras
> voltam. O rune localiza o eco em texto *condensado* — escapes e espaços em branco removidos dos
> dois lados, que é o que separa o que você mandou de todo eco transformado que conseguimos capturar
> — e veta um casamento que esteja coberto por uma cópia repintada da entrada. Medido contra o
> `python3 -q`, cujo REPL repinta a cada tecla: antes ele retornava em 0,22s com `matched: true`,
> oito segundos antes de o código rodar, 4 vezes em 4; agora ele espera a saída real, 3 vezes em 3.
>
> A afirmação honesta é *todo formato de eco que conseguimos capturar de um filho real está
> excluído*, não *é impossível acontecer*. Se o seu padrão for um literal que você também mandou, um
> filho que devolve a sua requisição palavra por palavra ainda pode satisfazê-lo. O veto também
> precisa *enxergar* a cópia: uma repintura que uma leitura do pty partiu ao meio — o frame termina
> no meio do redesenho e o resto chega na leitura seguinte — ainda não é reconhecível como cópia, e
> um padrão que só aparece dentro da sua própria entrada pode ser satisfeito por essa metade.
> Reproduzido de forma determinística cortando um frame logo depois do token. Ou seja, um padrão que
> também ocorre no que você mandou continua sendo o formato a evitar.

> **Contra quanta saída o padrão é casado: os 256 KB mais recentes depois do eco, relidos 32768
> caracteres para trás a cada leitura.** É um limite deliberado, com duas consequências.
>
> - **Um casamento único de até 32768 caracteres sempre é encontrado**, por maior que o turno fique,
>   porque cada varredura recomeça essa distância atrás de onde a anterior parou. Qualquer coisa pela
>   qual faça sentido esperar — um marcador, um prompt, uma cerca de fechamento — cabe com folga aí
>   dentro.
> - **Um casamento único que precise abranger mais de 32768 caracteres nunca é encontrado.**
>   `OPEN[\s\S]*CLOSE` ao longo de meio megabyte antes casava e agora não casa mais; em vez disso, o
>   send segue até o `--settle-ms` ou o `--timeout-ms`. Espere por `CLOSE` sozinho e use o `read` se
>   precisar do trecho entre os dois.
>
> O `\A` continua ancorando no início da resposta do filho, e não no início da janela — um padrão
> ancorado não pode ser satisfeito por onde quer que a janela tenha começado. `^`, `$` e `\z` não são
> afetados. **A resposta não é limitada por nada disso:** `output` continua sendo tudo o que o filho
> produziu no turno.
>
> É esse limite que torna uma resposta grande alcançável. Antes, o padrão era casado contra o turno
> inteiro a cada leitura de 4 KB, o que é quadrático no tamanho do turno — e na única thread do
> supervisor, então também matava de fome o dreno do pty. Medido contra um filho que emite N MB e
> depois imprime um marcador, usando esse mesmo marcador como padrão:
>
> | saída | antes | depois |
> | --- | --- | --- |
> | 4 MB | 11,85s, matched | 0,53s, matched |
> | 12 MB | 90,51s, `timed_out: true`, 11,46 MB de 12,00 lidos | 0,98s, matched, 12,15 MB lidos |
> | 48 MB | 112,43s, matched | 3,37s, matched |
>
> Nos 12 MB, o send reportava um timeout enquanto segurava 96% de uma resposta cujo marcador o filho
> já tinha impresso.

**`--timeout-ms N` (padrão 120000)** — um teto rígido. Quando ele expira, você recebe o que foi
capturado mais `settled: false, timed_out: true` — um resultado, não uma falha. Escolha esse valor de
propósito: o padrão é generoso porque agentes são lentos, então uma chamada equivocada custa dois
minutos.

O `--no-wait` escreve e retorna na hora, para quando você não espera resposta nenhuma. A resposta
dele tem outro formato — `{action, name, sent: true, waited: false}`, sem `output`, `cursor` nem
`prompt_detected`, porque nada foi esperado.

O `--no-newline` escreve o texto sem o carriage return final que o submete, útil para montar uma
linha em pedaços ou para conduzir uma TUI que lê teclas soltas.

### Os outros campos de uma resposta

- `settled: true` — **a espera foi atendida, em vez de estourar o tempo.** Três coisas diferentes
  ativam esse campo, e o campo companheiro diz qual delas foi: o filho ficou em silêncio durante a
  janela de settle (sem campo companheiro), o `--wait-for-regex` casou (`matched: true`), ou o filho
  encerrou (`child_exited: true`). Sozinho, ele **não** quer dizer que o filho ficou quieto — um
  casamento de regex o ativa sem nenhum período de silêncio, e é por isso que uma resposta pode vir
  com `settled: true` a 0,45s de uma janela de settle de 60 segundos.

  Nos casos em que ele *de fato* significa silêncio, o silêncio tem três causas, e esse campo não
  consegue distingui-las: o turno acabou, o filho está esperando por um humano, ou **o filho jogou um
  comando longo para segundo plano e parou de imprimir**. É o terceiro caso que morde: um chamador
  que ficava esperando o sumiço de um marcador de ocupado leu um frame sem ele e concluiu que o
  trabalho tinha acabado, 260 segundos antes de acabar de verdade. Se você está decidindo com base na
  *ausência* de alguma coisa, o `settled` sozinho não é evidência suficiente.
- `timed_out: true` — o `--timeout-ms` foi atingido primeiro. Um resultado, não uma falha.
- `matched: true` — o `--wait-for-regex` casou.
- `child_exited: true` — o filho terminou enquanto o send estava em andamento.
- `busy_at_send: true` — o filho *ainda estava produzindo saída* quando este send chegou, então a
  resposta pode conter o rabo do turno anterior. Vale conferir quando uma resposta parece pertencer à
  pergunta anterior.
- `regex_timed_out: true` — o padrão do `--wait-for-regex` estourou o orçamento de casamento e foi
  abandonado. Quase sempre é um padrão com backtracking catastrófico; simplifique-o.
- `dropped_bytes` — a contagem de saída antiga que o log não guarda mais: rotacionada ou perdida
  porque uma escrita no transcript falhou. Isso **não** invalida um cursor de `--since`: os cursores
  continuam absolutos, então um cursor anterior a um descarte devolve tudo o que ainda está guardado
  *depois* dele, em vez de um erro. Um cursor que cai dentro de uma região descartada resolve para a
  saída que veio depois dessa região — nunca para saída já entregue, que chegaria com cara de saída
  nova do turno atual.
- `transcript_gap_bytes` — aparece só no `status` e na resposta de um `send`, e apenas enquanto ainda
  houver saída devida que nenhuma escrita conseguiu registrar. É a única janela em que a defasagem
  não está em disco: a próxima escrita bem-sucedida a registra, e o `read` passa a reportá-la como
  `dropped_bytes`.
- `screen_rows`, `screen_cols`, `screen_size_recorded` — só com `--screen`: a geometria em que a tela
  foi renderizada, e se essa geometria é o winsize registrado do filho ou o fallback.
  Veja [Ele renderiza no tamanho em que o filho está realmente rodando](#ele-renderiza-no-tamanho-em-que-o-filho-está-realmente-rodando).

### `child_busy` e `idle_ms` ficam no `read`, não no `send`

Dizem se o filho imprimiu alguma coisa dentro da janela de settle e há quanto tempo ele imprimiu pela
última vez. É a forma estruturada de perguntar "ainda está trabalhando?": use isso em vez de dar grep
na UI do próprio programa atrás de um marcador de ocupado, que é apresentação e muda sem aviso.

**São campos do `read` e do `list`, não da resposta de um `send`.** Um `send` já bloqueou até o filho
assentar, então pergunte depois:

```console
$ rune session send --name grok --settle-ms 2500 "run the suite"
$ rune session read --name grok --tail 1 --json     # child_busy, idle_ms
```

Este documento já listou os dois entre os campos da resposta de um `send`, o que é errado do jeito
que mais importa — quem lê `.child_busy` de um `send` recebe `nil` e acaba caindo no grep da UI, que
é exatamente o que esses campos existem para substituir.

Repare que o nome diz que o filho está *imprimindo*, não que está *trabalhando*: um filho que jogou
um comando para segundo plano e ficou quieto reporta `child_busy: false`.

### Achar alguma coisa em um transcript longo

O `--since` e o `--tail` não ajudam quando o que você quer está no meio. Um dia de trabalho com um
agente conduzido chegou a 379KB.

```console
$ rune session read --name grok --grep 'THE BOARD' --context 2
```

Ele casa contra o texto *limpo*, e não contra o stream bruto, porque os frames de repintura de um
agente de tela cheia quebram palavras no meio de sequências de escape — um padrão que você enxerga
claramente na tela não vai casar com os bytes. A resposta traz `grep_matches`.

**Limpo não é renderizado, e a diferença morde justamente nos filhos que as sessões existem para
conduzir.** O texto limpo é o stream de repintura inteiro com os escapes removidos, então: histórico
sobrescrito continua casando, e volta como uma linha limpa e isolada que a tela não mostra desde
então; um frame pintado a golpes de cursor não tem quebra de linha nenhuma, então ele é uma única
linha para o grep, o `--context` não faz nada, e um único casamento devolve o frame inteiro sob um
`grep_matches: 1` de aparência plausível; e um padrão ancorado no que você vê na tela pode devolver
`grep_matches: 0`, porque adjacência na tela não é adjacência no stream. Quando a pergunta é *o que
está sendo exibido agora*, use `--screen`. O `--grep` serve para achar uma linha em um transcript
longo, e é nisso que ele é bom.

Um padrão que não compila volta como `grep_error`, e não como exceção, e **não seleciona nada**:
`output` e `clean_output` vêm vazios e `grep_matches` não aparece, que é como você diferencia "o
filtro nunca rodou" de "o filtro não achou nada". O read em si continua bem-sucedido, então `cursor`,
`prompt_detected` e `child_busy` seguem todos lá — nenhum deles depende do padrão, e você precisa do
cursor para avançar. (O `send --wait-for-regex` é diferente: lá o padrão decide quando retornar,
então um padrão ruim é recusado de cara.)

### `prompt_detected` é apenas indicativo

Todo resultado de `send`/`read` traz `prompt_detected`, mas **não condicione nada a ele**, e saiba
para que lado ele erra.

Medido contra saída real: ele é `false` para texto comum, `false` para um `$ ` sozinho, **`false`
para `Do you want to proceed?`** e `true` para `❯ `. Ou seja, com o grok ele é `true` em basicamente
toda leitura, porque o compositor do grok sempre termina em `❯` — um chamador o viu `true` 8 vezes em
8 e concluiu que ele não discriminava nada. Ele discrimina, sim; só que o que ele detecta são
*últimas linhas com formato de prompt*, o que não é a mesma pergunta que "isso está esperando por
mim". Repare no terceiro caso acima: ele é `false` justamente para o diálogo de permissão que você
mais gostaria que fosse pego. Para esse caso, olhe a tela. Os padrões de prompt do rune casam com
prompts em formato de shell (`user@host:~$`, `[y/N]`, `Password:`) e são deliberadamente
conservadores. REPLs de agentes em geral não se parecem com nenhum deles, então, justamente nas CLIs
que você quer conduzir, ele costuma ser `false`. Esperar por um prompt travaria contra a maioria dos
alvos reais — é por isso que o tempo de settle é o sinal principal.

## Lendo o transcript

O `read` reproduz o transcript durável da sessão, e funciona igual esteja a sessão viva ou já parada:

```console
$ rune session read --name grok --tail 50
$ rune session read --name grok --since 41234     # page from a cursor a previous call returned
```

Toda sessão escreve um log de eventos em NDJSON no mesmo formato que o `rune watch` produz, então
você pode acompanhar uma sessão ao vivo de outro painel:

```console
$ tail -f ~/.rune/projects/<project>/sessions/grok/output.ndjson
```

Agentes TUI de tela cheia geram um bocado de tráfego de repintura ANSI, então prefira
`--tail`/`--max-output` a ler um transcript inteiro.

O `--max-output=BYTES` guarda um começo e um fim e marca a emenda no próprio texto:

```
...the last line before the cut
[rune] ==== 41233 bytes omitted by --max-output ====
the first line after it...
```

Sem essa linha, a resposta se lê como uma saída contínua que o filho nunca imprimiu — medido: um
transcript de 201 bytes com `--max-output=200` cortou justamente o byte que transformava
`chsh -s /bin/zsh` em `chsh -s bin/zsh`, um caminho diferente e ainda assim plausível. O marcador é
uma anotação do rune, e não transcript, então ele não é debitado do BYTES e uma resposta pode passar
um pouquinho do orçamento; `truncated` e `omitted_bytes` continuam sendo a resposta autoritativa, já
que um filho pode imprimir qualquer coisa, inclusive uma linha parecida com o marcador.

### `--screen`: o que o terminal mostra, não o que chegou

Para um agente de tela cheia, esse costuma ser o campo que você quer. O stream de bytes contém todos
os frames de todas as repinturas, com a resposta picada entre eles; a tela contém apenas o que está
sendo exibido.

```console
$ rune session send --name grok --screen -- "reply with just the branch name"
$ rune session read --name grok --screen
```

Medido contra o grok: um transcript de 361KB renderizou para uma tela de 1,1KB, e uma resposta que o
agente tinha exibido claramente estava **ausente do stream de bytes em 3 de 3 turnos e presente na
tela renderizada em 3 de 3**. Se você casa padrões em cima do conteúdo, case em cima do `screen`.

Três coisas que ele não é. Ele é o *estado final*, então tudo o que subiu com o scroll se foi — o
transcript continua sendo o registro do que aconteceu. Ele é opt-in porque só faz sentido para um
filho que pinta uma tela: para um shell em modo cooked, o stream de bytes já é a resposta. E ele
**não é limitado pelos filtros de leitura** — `--since`, `--tail`, `--grep` e `--max-output` limitam
`output`/`clean_output` e deixam o `screen` em paz. Ele é limitado, sim, mas pela geometria: no
máximo `screen_rows x (screen_cols + 1)`, ambos devolvidos na mesma resposta. Um transcript de
219.941 bytes renderiza para cerca de 2KB. Ou seja, `--max-output=200 --screen` te dá uma resposta
limitada, limitada por uma regra que não foi você quem escolheu.

### Ele renderiza no tamanho em que o filho está realmente rodando

O filho de uma sessão começa em 40x120, e o `attach` o redimensiona para o terminal que assumiu o
controle — ou seja, o tamanho não é uma constante, e renderizar em um tamanho fixo produz uma tela
que ninguém nunca viu. O supervisor registra o winsize atual do filho no `meta.json` sempre que o
altera, e o `--screen` renderiza nesse tamanho e o informa de volta:

```console
$ rune session read --name grok --screen --json | jq '{screen_rows, screen_cols, screen_size_recorded}'
{ "screen_rows": 30, "screen_cols": 100, "screen_size_recorded": true }
```

Medido de ponta a ponta, com o pyte 0.8.2 e o GNU screen 4.00.03 reproduzindo os mesmos bytes como
oráculos independentes (os dois concordaram exatamente entre si em todos os formatos):

| o que foi exercitado | linhas erradas antes | linhas erradas depois |
|---|---|---|
| resize via control socket para 30x100, filho repinta no WINCH | 36/37 | **0/31** |
| o mesmo em 24x80 | 30/31 | **0/25** |
| o mesmo em 12x40 | 18/19 | **0/13** |
| o mesmo em 50x200 | 50/51 | **0/51** |
| o mesmo em 40x120 (os tamanhos coincidem) | 0/41 | 0/41 |
| um `rune session attach` de verdade a partir de um pty 30x100, filho ignora o WINCH | 29/30 | **0/30** |

Na linha do attach, os oráculos receberam os bytes que aquele terminal de fato recebeu, então "0 de
30" quer dizer que a tela renderizada pelo rune bateu, linha por linha, com o que o humano estava
vendo.

**É o `screen_size_recorded` que diferencia uma geometria real do fallback — não os números.** Uma
sessão que recebeu attach de um terminal de 40 linhas registra exatamente os mesmos 40x120 que o
fallback usa, então o par sozinho não consegue carregar essa distinção. O `screen_size_recorded` só é
true quando o tamanho reportado é o que o `meta.json` realmente guardava. Ele é false em três casos,
e todos eles reportam 40x120:

- uma sessão que ninguém redimensionou. O supervisor coloca o pty em 40x120 e não registra isso,
  então aqui o fallback não é um chute — é o tamanho em que o filho está genuinamente rodando.
- um diretório de sessão escrito antes de o rune registrar qualquer tamanho.
- um tamanho registrado que não é um terminal utilizável, e que é descartado ou limitado em vez de
  ser alocado: o `meta.json` é um arquivo em disco, e a grade é construída de forma eager.

Um resize que chega pelo control socket é limitado a 300x1000 — acima de qualquer terminal real — e o
limite é aplicado tanto ao pty quanto ao registro, então filho, registro e renderização sempre
concordam. Os campos de winsize de um pty são de 16 bits, e um 65535x65535 registrado faria todo
`--screen` posterior tocar uma grade desse tamanho: em um transcript deliberadamente hostil de 683KB,
um `read --screen` custa 0,76s em 40x120, 3,41s no teto e 17,72s sem o limite.

**Um caso de resize segue sem solução.** Todo o transcript retido é renderizado no tamanho *atual* do
filho, então, se a geometria mudou no meio do caminho, a saída pintada antes da mudança é refluída no
tamanho novo. Para um agente de tela cheia isso está certo, e dá para provar: uma TUI repinta ao
receber SIGWINCH e, no attach, o supervisor reproduz o backlog dela dentro do terminal, no tamanho do
terminal — que é exatamente o que renderizar o transcript inteiro nesse tamanho reproduz; a linha de
attach com 0 de 30 acima vale até para um filho que ignora completamente o SIGWINCH. O caso sem
solução é o de um filho que pinta uma vez e nunca repinta *e* cujo pty é então redimensionado sob um
terminal que já estava attachado, porque esse terminal está refluindo glifos que ele já desenhou e
não existe resposta de referência com que comparar. Encolhendo no meio do stream de 40x120 para
24x80 em um stream desses, o GNU screen manteve apenas a linha do cursor, o pyte não manteve nada, e
os dois discordaram entre si em uma linha do pouco que retiveram. O rune preserva o conteúdo e o
reflui, então ele difere dos dois. Renderizar no antigo tamanho fixo pontuou melhor na contagem crua
de linhas ali (15 erradas contra 24), mas só porque uma tela quase toda em branco coincidentemente
casa com um oráculo quase todo em branco — não porque tenha mostrado a alguém algo mais verdadeiro.

**Ele é renderizado a partir dos últimos 512KB, e para alguns agentes isso tem um custo visível.** Um
censo da saída do grok ao longo de 4,5MB encontrou 109.364 movimentos absolutos de cursor, 31.798
pares de synchronised update e **zero** apagamentos de qualquer tipo — nenhum `\e[K`, nenhum `\e[2K`,
nenhum `\e[2J`, nenhuma região de scroll. Um agente que repinta puramente posicionando e
sobrescrevendo depende de o terminal lembrar cada célula que ele escreveu, por mais antiga que seja.
Renderizar a partir de uma janela, em vez disso, parte de uma grade em branco, então tudo o que foi
pintado uma vez e nunca repintado — um cabeçalho, um banner — simplesmente não está lá, e o rune não
tem como perceber que está faltando. Ler `--screen` com mais frequência não ajuda; a janela é medida
em bytes, não em tempo.

O mesmo censo explica um ponto mais sutil. Quando um agente nunca apaga nada, uma linha duplicada na
tela pode ser inteiramente fiel: se o layout dele desce uma linha e ele repinta na nova posição, não
há nada que remova a cópia antiga, e **um terminal de verdade mostra a duplicata também**. Antes de
tratar uma linha repetida como bug do rune, verifique se o agente chega a apagar alguma coisa.

### Limitação conhecida: um `--screen` em polling pode devolver um frame pintado pela metade

Reportado a partir de uso real, e **não corrigido**. Fazer polling de `--screen` em um agente que
repinta ocasionalmente devolve um frame no meio de uma repintura — no caso reportado, uma linha
duplicada em duas linhas adjacentes.

Duas candidatas a correção foram medidas e rejeitadas. Comparar renderizações consecutivas e devolver
apenas uma que se repetisse mediu **pior** do que não fazer nada — 13 frames rasgados em 20 contra 11
— porque um agente que pinta em ciclo raramente renderiza o mesmo frame duas vezes, então a
verificação estoura o tempo e devolve o frame rasgado assim mesmo. Redefinir estabilidade como
quiescência não conseguiu reproduzir o rasgo de jeito nenhum: o mesmíssimo filho deu 11/20 uma vez e
0/20 duas vezes, o que significa que o harness não estava medindo aquilo que parecia medir. Uma
correção que falha silenciosamente na direção de "parece pronto" é pior do que uma limitação com a
qual dá para se planejar.

**O que fazer a respeito.** Não trate um único frame renderizado como autoritativo para uma decisão
que você não pode desfazer. Se estiver lendo um valor, consulte duas vezes e exija que as duas
leituras concordem. Se estiver esperando por um marcador, o `--wait-for-regex` é determinístico,
enquanto o `--screen` é um instantâneo.

**A culpa pode não ser do rune.** Um censo da saída de um agente ao longo de 4,5MB encontrou zero
apagamentos de qualquer tipo, e um agente que nunca apaga e desloca o próprio layout deixa a cópia
antiga na tela — um terminal de verdade mostra a duplicata também. O renderizador do rune concorda
com um emulador independente em seis perfis construídos a partir desse censo. Antes de registrar uma
linha duplicada como bug do rune, verifique se o agente chega a apagar alguma coisa.

### O transcript é limitado

Tanto o arquivo quanto a memória do supervisor têm teto, então uma sessão deixada rodando por um dia
não cresce sem limite. O teto do arquivo é aplicado duas vezes: normalmente pela rotação e — quando a
rotação não consegue ter sucesso de jeito nenhum, porque o diretório ficou sem permissão de escrita
ou o disco continuou cheio — por um limite rígido no dobro do teto, a partir do qual a saída é
registrada como descartada em vez de escrita. De um jeito ou de outro, o `read` reporta
`dropped_bytes` e os cursores continuam absolutos. Quando a rotação descarta saída mais antiga, o
`read` reporta `dropped_bytes` e os cursores continuam absolutos — um cursor continua nomeando a
mesma posição no stream, só que aponta para uma saída que não está mais guardada.

Uma escrita de transcript que falha — disco cheio, diretório sem permissão de escrita — descarta
saída do mesmo jeito, só que no *meio* de um stream que continua depois. Esses bytes são carregados e
registrados assim que a escrita volta a funcionar, e um cursor é mapeado através de cada região
descartada, em vez de passar por um único total acumulado, de modo que a saída anterior a um buraco
não é reentregue como se fosse nova. Enquanto uma escrita não der certo, não há onde registrar o
buraco em disco, e é isso que o `transcript_gap_bytes` no `status` reporta.

## O que saber antes de conduzir um agente de verdade

- **O `start` retorna quando o *supervisor* está pronto, não o filho.** Uma CLI de agente leva alguns
  segundos para subir, e a entrada mandada antes de ela estar escutando é simplesmente perdida.
  Espere por um marcador de prontidão — faça polling com `read`, ou faça do primeiro `send` um
  `--wait-for-regex` — antes de conduzir uma sessão recém-iniciada.
- **O settle é uma heurística.** Um filho que dá uma pausa no meio da resposta por mais tempo que o
  `--settle-ms` devolve uma resposta truncada. Aumente o valor, ou use `--wait-for-regex`.
- **O `--wait-for-regex` enxerga os 256 KB mais recentes, não o turno inteiro.** Qualquer casamento
  único de até 32768 caracteres sempre é encontrado; um casamento que precise abranger mais do que
  isso nunca é. Espere por um marcador, e não por um padrão que abrace megabytes.
- **Uma única linha de 1024+ bytes some dentro de um filho em modo cooked.** Isso é o `MAX_CANON`, um
  limite do terminal, não do rune: a disciplina de linha não consegue montar uma linha canônica maior
  e a descarta em silêncio — 1023 bytes chegam, 1024 não. A maioria das CLIs de agente roda o
  terminal em modo raw e não é afetada (300KB chegam byte a byte). Um shell interativo também: o
  `bash --norc -i` usa readline, que coloca o terminal em modo raw, e engole uma linha de 1995
  caracteres byte a byte. O limite morde um filho que lê em modo *cooked* — um `cat` puro, ou um
  script que lê o stdin sem readline. Mande em pedaços, ou conduza um alvo em modo raw.
- O Enter é enviado como carriage return, que é o que um terminal de verdade manda, então TUIs em
  modo raw o recebem. Shells em modo cooked não são afetados.
- O pty do filho recebe um tamanho de janela explícito, porque uma sessão desacoplada não tem
  terminal de onde copiar um, e um pty sem tamanho definido é 0x0 — o que deixa agentes de tela cheia
  renderizando no vazio. Ele começa em 40x120, acompanha um terminal attachado enquanto houver algum
  (até um teto de 300x1000) e volta para 40x120 quando o último sai. O `--screen` renderiza no
  tamanho que estiver valendo no momento.

## Onde o estado mora

Em `RUNE_HOME` (padrão `~/.rune`), com permissões só para o dono:

```
$RUNE_HOME/projects/<project>/
  sessions/<name>/
    meta.json        0600   pid, supervisor pid, command, state, child terminal size
    output.ndjson    0600   full transcript
    supervisor.log   0600   supervisor stderr, for when something goes wrong
    control.sock     0600   the supervisor's control socket
  archive/<stamp>-<name>/   archived sessions, out of the live namespace
```

Defina `RUNE_HOME` para manter as sessões isoladas (testes, sandboxes, trabalho em paralelo).

O `meta.json` é substituído por rename, nunca truncado no lugar, porque todo outro processo do rune o
lê para responder "esta sessão existe, e está viva?" sem ter lock nenhum para pegar. Uma janela em
que ele aparecesse incompleto era uma janela em que o `send` respondia "No such session" e o `list`
reportava `state: dead`; registrar o winsize do filho transformou isso numa escrita por resize, e um
humano arrastando a borda de uma janela emite uma por frame. Medido com um attach real arrastado por
250 formatos de janela em 7,5 segundos, com outro processo lendo o meta em um laço apertado: 90 de
294.728 leituras voltaram ilegíveis antes, 0 de 312.582 depois.

## Quanto custa rodar várias ao mesmo tempo

Uma sessão é um processo supervisor, e esse isolamento é deliberado: um agente travado derruba a
própria sessão e mais nada. O preço é um interpretador Ruby por sessão, e vale saber disso antes de
sair abrindo várias.

Medido, com filhos ociosos:

| sessões | memória residente | descritores |
|----------|-----------------|-------------|
| 24 | 543 MB | 648 |
| 60 | 1361 MB | 1620 |

Isso dá **~23 MB e 27 descritores por sessão**, constante — o mesmo com 60 e com 24, e sem variação
ao longo de rodadas de sends. Ou seja, o custo é previsível e linear, em vez de surpreendente, mas
ele é cobrado adiantado: sessenta agentes custam bem mais de um gigabyte antes de qualquer um deles
ter feito coisa alguma.

A concorrência em si se sustentou no mesmo teste: 60 starts simultâneos deram todos certo, todo send
chegou à sessão para a qual foi endereçado, o `list` concordou com a realidade, e nada ficou rodando
no fim. Trinta chamadas simultâneas de `start` *sem* `--name` para a mesma ferramenta produziram
trinta codinomes distintos e nenhuma colisão.

## Escopo

O rune é um **broker** de sessões, não um barramento de mensagens. Ele guarda as sessões e as
endereça por nome; decidir quem fala com quem é tarefa do agente que chama — ele já tem os nomes.
Roteamento entre sessões, perfis por agente e um log de conversa compartilhado estão deliberadamente
fora do escopo.
