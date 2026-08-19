> Cette page traduit [`docs/getting_started.md`](../getting_started.md). En cas de divergence, la version anglaise fait foi.

# Bien démarrer avec rune

`rune` est une CLI et une bibliothèque Ruby conçue pour être tout aussi utilisable par un humain
dans un terminal que par un agent IA qui la pilote programmatiquement. Chaque commande renvoie le
même `Result` structuré — seul le *rendu* change selon la façon dont vous l'appelez.

## Installation

Le nom de gem non qualifié `rune` est déjà pris sur le registre public RubyGems.org par un paquet
sans rapport, donc `gem install rune` y installe la mauvaise chose. La voie d'installation prise en
charge pour l'utilisateur final est la formule épinglée par somme de contrôle dans le tap Homebrew
CorvidLabs :

```sh
brew install corvidlabs/tap/rune
rune version --json
```

Homebrew ajoute automatiquement le tap lors de la première installation. Mettez Rune à jour avec :

```sh
brew upgrade corvidlabs/tap/rune
```

Ne clonez les sources que pour développer Rune lui-même :

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

Ou en tant que plugin [fledge](https://github.com/CorvidLabs/fledge) :

```sh
fledge plugins install CorvidLabs/rune
fledge rune run --json -- git status
```

## Découvrir ce qui est disponible

```sh
rune --help              # or -h, or `rune help`
rune run --help          # or `rune help run`, or `rune run -h`
```

L'aide d'une commande liste les indicateurs propres à cette commande — `--timeout=SECONDS` pour
`rune run`, `--log=PATH` pour `rune watch` — aux côtés des indicateurs globaux. Elle est aussi
structurée en mode agent, de sorte que la découverte n'exige pas d'analyser le rendu humain :

```sh
$ rune run --help --json | jq -c '.data.flags'
[{"flag":"--timeout=SECONDS","description":"Kill the wrapped command after N seconds (default 30). Before `--` only."},{"flag":"--max-output=BYTES","description":"Bound clean_output/raw_output to BYTES each, keeping head+tail and marking the join with a `[rune] ==== N bytes omitted by --max-output ====` line. Mutually exclusive with --tail. Before `--` only."},{"flag":"--tail=N","description":"Keep only the last N lines of clean_output/raw_output. Mutually exclusive with --max-output. Before `--` only."},{"flag":"--separate-streams","description":"Adds clean_stdout/clean_stderr (stderr on a pipe, not the pty) alongside the merged view. Before `--` only."}]
```

Les indicateurs d'aide suivent la même règle de séparateur que tout le reste (voir ci-dessous) :
`rune run -- mytool --help` passe `--help` à `mytool`.

## Les trois modes de sortie

`rune` choisit automatiquement un mode de rendu selon la façon dont il est invoqué, ou vous pouvez
en forcer un explicitement avec un indicateur. Les trois modes exécutent exactement la même
logique de commande — seul le format de sortie diffère.

### 1. Mode TTY humain (par défaut, terminal interactif)

Quand stdout est un vrai terminal et qu'aucun indicateur `--json`/`--ndjson` n'est fourni, `rune`
affiche une sortie colorisée et formatée pour un humain :

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

### 2. Mode agent JSON (`--json`, ou détection automatique de tube)

Passez `--json` explicitement, ou redirigez simplement la sortie de `rune` vers un tube ou un
fichier — un stdout qui n'est pas un TTY bascule automatiquement le rendu en JSON, sans aucun
indicateur :

```sh
$ ruby bin/rune run --json -- echo "hello agent"
{"status":"ok","data":{"command":"echo hello\\ agent","exit_code":0,"clean_output":"hello agent\n","raw_output":"hello agent\r\n","prompt_detected":false,"duration_ms":5.27}}
```

```sh
$ ruby bin/rune version | cat
{"status":"ok","data":{"name":"rune","version":"0.7.0","ruby":"4.0.6","ruby_platform":"arm64-darwin25","fledge":true,"specsync":true}}
```

> **`exit_code` est le code de sortie du processus enveloppé, pas un verdict sur le travail.** Il
> répond à la question « le processus s'est-il terminé, et comment », ce qui, pour une CLI d'agent,
> vaut presque toujours `0` — y compris pour des exécutions dont la sortie était erronée. Un
> utilisateur a vu huit appels `rune run` consécutifs renvoyer `0`, dont plusieurs avaient
> produit des conclusions qu'il a dû corriger ensuite. Si vous devez savoir si le *travail* a
> réussi, cela doit venir de la sortie, pas de ce champ. `124` est l'exception à connaître : elle
> signifie que rune a tué le processus au terme du `--timeout`.

Chaque réponse JSON a la même enveloppe : `{"status": "ok"|"error", "data": {...}}` (ou
`{"status": "error", "error": "..."}` en cas d'échec).

Rune écrit l'enveloppe finale sur stdout en cas de succès comme d'échec. Cela offre aux agents un
canal de résultat unique et analysable, mais cela signifie aussi qu'un humain qui redirige stdout
redirige également les messages d'erreur au niveau de Rune. Stderr est réservé aux annonces
opérationnelles et au passage en direct de `rune watch`, qui ne doivent pas corrompre le stdout
structuré.

Les indicateurs de sortie globaux ne sont reconnus qu'avant le premier séparateur `--`. Les jetons
qui le suivent appartiennent à la commande enveloppée et sont préservés, donc
`rune run -- tool --json` passe `--json` à `tool`.

Un `--flag` que rune ne connaît pas, placé à l'endroit où vont les indicateurs propres à rune, est
une erreur plutôt que quelque chose de silencieusement transmis : `rune run --tiemout=5 -- echo hi`
essayait autrefois d'*exécuter* l'indicateur mal orthographié et répondait `status: ok` avec
`exit_code: 127`. Seuls les jetons précédant la commande enveloppée sont vérifiés, donc
`rune run cargo clippy --tests` et `rune run -- mytool --tiemout=5` ne sont pas concernés — une
fois le nom de la commande rencontré, chaque `--flag` ultérieur lui appartient.

### 3. Mode agent à enveloppe NDJSON (`--ndjson`)

`--ndjson` enveloppe le même résultat dans une enveloppe `{"event": "result"|"error", ...}` au lieu
de la forme simple `{"status": ...}` utilisée par `--json` — un format que certains harnais
d'agents attendent de façon uniforme pour chaque commande, `rune run` compris :

```sh
$ ruby bin/rune run --ndjson -- echo "hello stream"
{"event":"result","status":"ok","data":{"command":"echo hello\\ stream","exit_code":0,"clean_output":"hello stream\n","raw_output":"hello stream\r\n","prompt_detected":false,"duration_ms":11.45}}
```

Pour `rune run`, il s'agit toujours d'exactement une ligne, émise une fois la commande terminée —
`PTYRunner` met en tampon toute l'exécution et renvoie un unique `Result`, donc `--ndjson` est ici
un choix d'enveloppe, pas un flux incrémental. Pour un véritable flux d'événements en direct au fil
de l'avancement d'une commande longue ou interactive, voir
[`rune watch`](#observer-une-session-en-direct-avec-rune-watch) ci-dessous, qui émet une ligne NDJSON par
fragment de sortie au moment où il survient.

## Exécuter des commandes avec `rune run`

`rune run` lance n'importe quelle commande CLI ou TUI interactive dans un vrai PTY, supprime les
séquences d'échappement ANSI, désactive les pagineurs et mesure le temps d'exécution :

```sh
rune run -- git status
rune run --json -- npm test
rune run --ndjson -- fledge lanes run check
```

### Redéfinir le délai d'expiration

Chaque invocation de `rune run` a un délai d'expiration de 30 secondes par défaut. Redéfinissez-le
avec `--timeout=SECONDS`, placé *avant* le séparateur `--` pour qu'il ne soit pas pris pour un
indicateur appartenant à la commande enveloppée :

```sh
$ ruby bin/rune run --json --timeout=1 -- sleep 3
{"status":"ok","data":{"command":"sleep 3","exit_code":124,"clean_output":"\n[rune] Execution timed out after 1 seconds","raw_output":"\n[rune] Execution timed out after 1 seconds","prompt_detected":false,"duration_ms":1005.32}}
```

Une commande arrivée à expiration renvoie le code de sortie `124` avec un message
`[rune] Execution timed out after N seconds` ajouté à la sortie capturée — cela reste un `Result`
normal, pas une exception.

**La sortie capturée avant l'arrêt forcé est toujours renvoyée**, donc un processus enfant qui a
affiché quelque chose puis s'est bloqué montre ce qu'il a affiché. Si la sortie est *vide*,
l'enfant n'a réellement rien affiché, et rune le signale en indiquant la raison la plus courante.

**`rune run` ne transmet pas son propre stdin à l'enfant.** Un tty appartient à l'humain — s'en
emparer est le rôle de `rune watch` — et transmettre un tube renverrait en écho l'entrée de
l'appelant à travers le pty jusque dans `clean_output`. Ainsi `echo hi | rune run -- cat` expire :
`cat` attend une entrée qui n'arrive jamais. Placez plutôt la redirection à l'intérieur de la
commande, où le shell l'exécute dans le pty :

```sh
$ rune run -- sh -c 'claude -p --output-format text < prompt.md'
```

Cela fonctionne, tout comme passer une invite de plusieurs paragraphes en un seul argument — les
sauts de ligne traversent argv intacts. Le champ `command` de la réponse est une reconstruction
*d'affichage* échappée pour le shell, destinée aux humains, et non ce que l'enfant a reçu ; ne
diagnostiquez pas le quotage à partir de ce champ.

### Borner la sortie et séparer les flux

Trois autres indicateurs, tous placés avant le séparateur `--`, modifient tous la *forme* du
résultat :

- **`--max-output=BYTES`** borne `clean_output` et `raw_output` à BYTES chacun, en conservant le
  début et la fin, et ajoute `truncated: true` avec `omitted_bytes`. Deux choses découlent de ce
  « chacun » : les champs sont bornés *séparément*, donc sous cet indicateur ils décrivent des
  fenêtres différentes de l'exécution et `clean_output` n'est pas `strip_ansi(raw_output)` —
  `omitted_bytes` est le décompte de `clean_output` et `raw_output` porte son propre marqueur avec
  une valeur différente. Et `omitted_bytes` est mesuré en positions dans l'original, donc il
  correspond exactement en ASCII mais dérive de quelques octets sur du texte multi-octets, où une
  coupure peut scinder un caractère. Les deux moitiés sont jointes par une ligne
  `[rune] ==== N bytes omitted by --max-output ====` plutôt que raboutées, de sorte que le texte
  renvoyé ne se lise jamais comme quelque chose que la commande aurait affiché : sans cela, une
  transcription de 201 octets à `--max-output=200` perdait exactement l'octet qui transformait
  `chsh -s /bin/zsh` en `chsh -s bin/zsh`. Ce marqueur est une annotation de rune et non la sortie
  de la commande, il n'est donc pas imputé sur les BYTES et une réponse peut légèrement dépasser
  le budget.
- **`--tail=N`** ne conserve que les N dernières lignes, en ajoutant `truncated: true` avec
  `omitted_lines`. Mutuellement exclusif avec `--max-output` ; passer les deux est une erreur
  plutôt qu'une précédence silencieuse.
- **`--separate-streams`** ajoute `clean_stdout` et `clean_stderr` aux côtés du `clean_output`
  fusionné, plutôt qu'en remplacement.

`--separate-streams` a un coût réel, c'est pourquoi il est optionnel plutôt que par défaut : un
pty n'a qu'un seul flux, donc les séparer signifie donner à stderr son propre tube. L'enfant ne
voit alors plus un unique terminal de contrôle pour les deux, et un programme qui teste
`isatty(2)` se comportera comme si ses erreurs étaient redirigées — ce qui, pour beaucoup de CLI,
signifie perdre la couleur, voire basculer entièrement en mode non interactif. Utilisez-le quand la
séparation vous importe plus que le fait que l'enfant se croie sur un terminal.

## Observer une session en direct avec `rune watch`

`rune run` met en tampon toute la sortie d'une commande et ne la renvoie qu'une fois la commande
terminée — parfait pour les scripts et la capture, mais inutilisable si vous voulez réellement
vous installer au clavier et piloter un programme interactif pendant qu'autre chose observe la
session. `rune watch` est fait pour cela : il place votre terminal en mode brut, transmet chaque
touche que vous tapez à l'enfant en direct — y compris les séquences d'échappement brutes comme
les flèches, pas seulement des lignes entières — diffuse la sortie de l'enfant sur votre écran au
fur et à mesure (pas à la fin), et consigne simultanément chaque fragment comme un événement
NDJSON — ainsi un agent IA peut suivre la session en temps réel pendant qu'un humain la pilote.

```sh
# A small interactive demo program ships with rune specifically to try this against:
rune watch -- ruby examples/humans/demo_tui.rb
```

Le journal d'événements est par défaut un fichier temporaire protégé contre les collisions et
accessible au seul propriétaire (`0600`), pas stderr — mélanger les événements NDJSON dans le même
terminal que le passage en direct était la conception initiale, et l'usage réel a immédiatement
montré que c'était un mauvais choix par défaut (le JSON entrelacé rendait la session illisible). Le chemin
est annoncé une fois, dès le départ :

```
[rune watch] live event log: /tmp/rune-watch-20260728-12345-abcd.ndjson
```

Faites un `tail -f` sur ce chemin depuis un autre panneau (ou faites-le suivre par un agent) pour
observer la session en direct, votre propre terminal restant propre. Orientez-le plutôt vers un
endroit précis avec `--log=PATH` :

```sh
rune watch --log=/tmp/session.ndjson -- ruby examples/humans/demo_tui.rb
```

Chaque ligne du journal est un objet JSON : `{"event":"start","command":"...","pid":...}`, puis un
`{"event":"output","bytes":N,"text":"..."}` par fragment au fil du flux, puis
`{"event":"exit","exit_code":N}` quand l'enfant se termine.

### `rune watch` en mode agent

`rune watch` suit les mêmes règles de mode de sortie que toute autre commande. Sous `--json`,
`--ndjson`, ou dès que stdout n'est pas un terminal, le passage en direct bascule sur **stderr** et
stdout ne porte que l'enveloppe de résultat — ainsi un programme enveloppant peut analyser stdout
directement pendant que l'humain au clavier voit toujours sa session :

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

Omettez le `2>/dev/null` pour continuer à observer la session vous-même pendant que le JSON est
capturé ailleurs.

`rune watch` exige un vrai terminal (il refuse de s'exécuter si stdin n'est pas un TTY — il n'existe
pas de mode non interactif pertinent) et ne fonctionnera pas par-dessus la propre imbrication de
PTY de `rune run`, donc il ne peut pas être démontré dans un exemple redirigé comme le reste de ce
guide. Le menu de premier niveau d'`examples/humans/demo_tui.rb` est un vrai sélecteur à flèches
(↑/↓ + Entrée, ou `q` pour quitter) plutôt qu'un « tapez un numéro et appuyez sur Entrée », précisément
pour exercer le transfert brut d'octets uniques et de séquences d'échappement — ce qu'un menu
purement mis en tampon par lignes ne touche jamais. Le commentaire d'en-tête
d'`examples/humans/demo_tui.rb` contient des commandes prêtes à copier-coller, et
`spec/rune/pty_watcher_spec.rb` montre comment les mécaniques sous-jacentes de transfert et de
journalisation sont testées unitairement, y compris un test qui pilote le menu à flèches lui-même
de bout en bout (un faux objet terminal plus des `IO.pipe` pilotent un vrai processus enfant
interactif sans avoir besoin d'un véritable terminal de contrôle).


### Borner un watch

Deux limites indépendantes, toutes deux avant le séparateur `--`, toutes deux désactivées par
défaut :

- **`--timeout=SECONDS`** tue la session après N secondes d'horloge réelle, quelle que soit son
  activité.
- **`--idle-timeout=SECONDS`** la tue après N secondes **sans sortie ni entrée** — celle qu'il vous
  faut pour « cet agent a cessé de faire quoi que ce soit », puisqu'une longue compilation n'est
  pas de l'inactivité.

L'une comme l'autre donne le code de sortie `124`, avec `timed_out: true` et un `timeout_kind` valant
`"timeout"` ou `"idle_timeout"` indiquant laquelle s'est déclenchée.

## Analyser du texte structuré

`Rune::Parsers::TableParser` et `Rune::Parsers::KeyValueParser` transforment une sortie de terminal
non structurée en tables de hachage Ruby :

```ruby
require 'rune'

Rune::Parsers::TableParser.parse(<<~TABLE)
  NAME           STATUS   VERSION
  fledge-plugin  active   1.0.0
TABLE
# => [{ name: 'fledge-plugin', status: 'active', version: '1.0.0' }]
```

`TableParser.parse` accepte un mot-clé `format:` (`:auto` par défaut, ou `:pipe`/`:space` pour
forcer un mode d'analyse) — voir [`specs/parsers/parsers.spec.md`](../../specs/parsers/parsers.spec.md)
pour les limitations connues de l'heuristique avant de compter sur `:auto` face à une sortie peu
familière.

## Prochaines étapes

- [`examples/smoke_test.rb`](../../examples/smoke_test.rb) — `ruby examples/smoke_test.rb` ou `fledge
  run smoke-test`. Un parcours autonome, fondé sur des assertions, du comportement réel (sans
  bundler ni rspec requis) : modes de sortie, validation de `--timeout`, analyseurs, `Script`,
  transfert des signaux, détection d'invite.
- [`examples/humans/demo_tui.rb`](../../examples/humans/demo_tui.rb) — la démo interactive utilisée dans
  toute la section `rune watch` ci-dessus. [`examples/agents/pty_runner_example.rb`](../../examples/agents/pty_runner_example.rb),
  [`table_parser_example.rb`](../../examples/agents/table_parser_example.rb) et
  [`script_automation_example.rb`](../../examples/agents/script_automation_example.rb) sont des scripts
  plus petits, chacun dédié à un seul concept — chacun exécutable directement (`ruby examples/agents/<name>.rb`)
  sans autre préparation que `require_relative '../lib/rune'`.
- [Guide d'architecture PTY](pty_architecture.fr.md) — le fonctionnement interne de l'exécuteur PTY,
  de la lecture des flux, de la détection d'invite et du passage en direct de `rune watch`.
- [`specs/`](../../specs/) — les contrats de modules vérifiés par machine (`spec-sync`) pour `cli`,
  `parsers`, `pty_runner`, `session` et `watch`.
- [`AGENTS.md`](../../AGENTS.md) — les conventions pour ajouter de nouvelles commandes et travailler
  avec la chaîne d'outils de confiance.
