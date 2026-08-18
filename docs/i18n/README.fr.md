# rune

*Ce document est une traduction française de README.md ; la version anglaise fait foi.*

[![CI](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml/badge.svg)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-3.0%20%E2%80%93%204.0-CC342D?logo=ruby&logoColor=white)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)

Un outil CLI et une bibliothèque Ruby conçus dès le départ pour être **de première classe pour les humains comme pour les agents IA**.

`rune` sert d'exécuteur de pseudo-terminal (PTY) universel et de pont de données structurées pour toute commande CLI ou application TUI interactive.

Chaque commande produit une sortie terminal formatée et colorée pour les humains et du JSON
structuré pour les agents IA. `rune watch` écrit en plus un flux d'événements NDJSON en direct
pendant que l'humain pilote la session. Même outil, mêmes commandes, double interface.

`rune session` va un cran plus loin : il maintient un CLI d'agent — `claude`, `grok`, `codex` —
ouvert entre des invocations distinctes, de sorte qu'un agent peut en piloter un autre de manière
conversationnelle et qu'un humain peut se rattacher à la même session pour prendre le relais.

📖 Nouveau ici ? Commencez par le **[guide de prise en main](docs/getting_started.md)**.

---

## Fonctionnalités

1. **Double sortie (TTY humain / JSON et NDJSON pour agents)**
   - Mode terminal : sortie formatée et colorée (`rune version`)
   - Mode JSON pour agent : `--json` ou détection automatique de pipe (`rune version | cat`)
   - Mode NDJSON pour agent : `--ndjson` pour une enveloppe de résultat cohérente (`rune version --ndjson`)
2. **Exécuteur universel de processus PTY (`rune run`)**
   - Lance n'importe quel outil CLI ou TUI dans une session pseudo-terminal
   - Supprime automatiquement les codes d'échappement ANSI, les déplacements de curseur et les séquences de contrôle
   - Désactive les pagineurs de terminal (`PAGER=cat`) afin que les requêtes renvoient immédiatement sans se bloquer
   - Mesure la durée d'exécution du processus en millisecondes et détecte les invites interactives
3. **Analyseurs automatiques structurés (`Rune::Parsers`)**
   - `TableParser` : analyse des tableaux de terminal délimités par des espaces ou des pipes en tableaux de hachages
   - `KeyValueParser` : analyse une sortie clé-valeur (`key: val`) en hachages typés
   - `TextSanitizer` : normalise les fins de ligne et nettoie les codes d'échappement ANSI
4. **DSL de script interactif (`Rune::Script`)**
   - DSL d'automatisation de scripts TUI étape par étape pour piloter les invites de terminal interactives et les menus TUI
5. **Passthrough interactif en direct (`rune watch`)**
   - Met votre terminal en mode brut et transmet les frappes au processus enfant en direct, octet par octet
   - Diffuse la sortie du processus enfant sur votre écran au fur et à mesure (contrairement à `rune run`, qui met en mémoire tampon et
     renvoie tout à la fin)
   - Journalise simultanément chaque fragment comme événement NDJSON dans un fichier temporaire (chemin annoncé une fois, ou
     `--log=PATH`) afin qu'un agent IA puisse suivre la session en direct pendant qu'un humain la pilote
6. **Sessions nommées persistantes (`rune session`)**
   - Maintient un processus enfant de type REPL — `claude`, `grok`, `codex`, un shell — ouvert *entre* des invocations `rune`
     distinctes, ce que ni `run` (met en tampon et renvoie une seule fois) ni `watch` (meurt avec son processus enfant)
     ne peuvent faire
   - **Envoi et stabilisation** : écrire une entrée, attendre que le processus enfant se taise, récupérer exactement la sortie
     que cet envoi a produite, transformant un TTY asynchrone en appel requête/réponse synchrone
   - `--screen` renvoie le *terminal rendu* plutôt que le flux d'octets brut, ce qui compte
     parce qu'un agent plein écran entrelace sa réponse avec ses propres rafraîchissements — une transcription
     mesurée est passée de 361 Ko de trafic de rafraîchissement à un écran de 1,1 Ko
   - `attach` transmet la session en direct à un terminal humain et **Ctrl-]** la rend, toujours en cours d'exécution
   - Les sessions sont nommées, limitées au projet et archivables ; les transcriptions sont bornées sur le disque et en
     mémoire, de sorte qu'une session laissée en fonctionnement pendant une journée ne croît pas sans limite

---

## Installation

Le nom de gem `rune` non qualifié est déjà pris sur le registre public RubyGems.org par un
paquet sans rapport, de sorte que `gem install rune` y installe la mauvaise chose. Installez la
formule maintenue et épinglée par somme de contrôle depuis le tap Homebrew CorvidLabs :

```sh
brew install corvidlabs/tap/rune
rune version --json
```

Mettez à jour les versions ultérieures via le même canal :

```sh
brew upgrade corvidlabs/tap/rune
```

Pour le développement depuis les sources :

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

---

## Exemples d'utilisation

### 0. Découvrir le CLI

```sh
rune --help              # every command, plus the global flags
rune run --help          # one command's usage and its own flags
rune help watch          # same thing, spelled the other way
```

L'aide est elle aussi structurée, de sorte qu'un agent peut découvrir la surface sans extraire du texte :

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

> **Utilisez `--` avant la commande encapsulée.** Chaque drapeau rune — `--json`, `--ndjson`, `--help`,
> `--timeout`, `--log` — n'est reconnu *que* avant le premier `--`. C'est ce qui permet à
> `rune run -- gh pr list --json number` de transmettre `--json` à `gh` au lieu de le consommer. Sans le
> séparateur, rune prend le drapeau pour lui-même et la commande encapsulée ne le voit jamais, en silence.

### 1. Exécuter n'importe quelle commande CLI en mode JSON pour agent
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

### 2. Enveloppe de résultat NDJSON
```sh
rune run --ndjson -- fledge lanes run check
```
```json
{"event":"result","status":"ok","data":{"command":"fledge lanes run check","exit_code":0,"clean_output":"...","duration_ms":1652.8}}
```

`rune run --ndjson` émet cette enveloppe unique lorsque la commande se termine. Utilisez `rune watch` pour un
flux d'événements de sortie en direct.

### 3. Analyser une sortie CLI tabulaire en hachages
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

### 4. Piloter des applications TTY / TUI interactives
```ruby
require 'rune'

# Harness an interactive TUI program with input keystrokes
runner = Rune::PTYRunner.new("fledge plugins search --interactive", input: "\x03")
result = runner.run
# => Result with exit_code 130, clean_output, duration_ms
```

### 5. Surveiller une session en direct (l'humain pilote, l'agent suit)
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

En mode agent — `--json`, `--ndjson`, ou chaque fois que stdout n'est pas un terminal — le passthrough en direct
bascule vers **stderr** afin que stdout ne transporte que l'enveloppe de résultat. L'humain conserve sa vue
en direct ; le programme appelant obtient du JSON propre :

```sh
rune watch --json -- ruby examples/humans/demo_tui.rb 2>/dev/null | jq .data.log_path
```

### 6. Piloter un CLI d'agent depuis un autre (`rune session`)

`run` met en tampon et renvoie une seule fois ; `watch` exige un humain devant un terminal et se termine avec
son processus enfant. Aucun des deux ne peut maintenir un REPL d'agent ouvert entre les appels. `session` le peut :

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

**Pourquoi `--screen` plutôt que la sortie brute.** Un agent plein écran se redessine en continu, de sorte que le
flux d'octets contient chaque image de chaque rafraîchissement, avec la réponse éclatée entre elles. Mesuré
avec grok : une transcription de 361 Ko s'est réduite à un écran de 1,1 Ko, et une réponse que l'agent avait
clairement affichée était absente du flux d'octets dans 3 tours sur 3 et présente dans l'écran rendu dans 3
tours sur 3. Si vous faites une recherche sur le contenu, recherchez dans `screen`.

**Prenez vous-même le volant**, puis rendez-le sans rien arrêter :

```sh
rune session attach --name reviewer   # Ctrl-] detaches; the session keeps running
```

Les sessions sont limitées à l'arborescence de travail git qui les contient, de sorte que `reviewer` dans deux
checkouts correspond à deux sessions. C'est délibéré, et c'est aussi la surprise la plus fréquente — si `list`
n'affiche rien, vérifiez le répertoire où vous vous trouvez ainsi que `RUNE_HOME` :

```sh
rune session list --all-projects
```

**Retrouver une chose dans une longue transcription.** Une journée de travail avec un agent piloté a atteint
379 Ko, et ni `--since` ni `--tail` n'aident lorsque ce que vous cherchez se trouve au milieu :

```sh
rune session read --name reviewer --grep 'THE BOARD' --context 2
```

📖 Guide complet, y compris le réglage de la stabilisation et les limitations connues :
**[docs/sessions.md](docs/sessions.md)**.

---

## Intégration CorvidLabs

`rune` s'intègre à la [chaîne d'outils de confiance CorvidLabs](https://github.com/CorvidLabs) :

- **[fledge](https://github.com/CorvidLabs/fledge)** — Exécuteur de tâches et cycle de vie du projet. `rune` est un plugin `fledge` natif défini via `plugin.toml`. Installez directement via :
  ```sh
  fledge plugins install CorvidLabs/rune
  fledge rune run --json -- git status
  ```
- **[spec-sync](https://github.com/CorvidLabs/spec-sync)** — Application des contrats (`specs/`)
- **[augur](https://github.com/CorvidLabs/augur)** — Évaluation du risque des changements

---

## Architecture et mécanismes internes

- 📖 **[Guide de prise en main](docs/getting_started.md)** — Modes de sortie, utilisation de `rune run`, délais d'expiration et analyseurs avec des sorties de commandes réelles.
- 📖 **[Guide des sessions persistantes](docs/sessions.md)** — `rune session` : sessions PTY nommées qui survivent à une invocation unique, et envoi-et-stabilisation pour piloter un CLI d'agent depuis un autre.
- 📖 **[Guide d'architecture du pseudo-TTY (PTY)](docs/pty_architecture.md)** — Comment fonctionnent en coulisses, en Ruby, les pseudo-terminaux, la lecture non bloquante des flux, l'assainissement ANSI, la détection d'invites, l'exécution de scripts et le passthrough bidirectionnel en direct de `rune watch`.
- 📖 **[Guide de publication](docs/releasing.md)** — Synchronisation des versions, vérification, provenance, étiquetage et publication des paquets.

---

## Développement et vérification

```sh
fledge run test         # Run RSpec test suite (405 examples, 87% line coverage)
fledge run lint         # Run RuboCop linter (0 offenses)
fledge lanes run verify # Full CI gate (lint + tests + strict 100%-coverage spec-sync)
fledge lanes run release # Verify, smoke-test, and build the release gem
fledge run smoke-test   # Runnable, assertion-based tour of real behavior (examples/smoke_test.rb)
COVERAGE=1 bundle exec rspec  # Same suite, plus an HTML coverage report at coverage/index.html
```

`examples/smoke_test.rb` est un script autonome et sans dépendances (ni bundler ni rspec requis) qui
exerce `rune run`, `--timeout`, `TableParser`/`KeyValueParser`, `Script`, le transfert de signaux et la
détection d'invites contre le binaire CLI réel, avec une sortie réussite/échec et un code de sortie non nul
en cas d'échec. Utile comme vérification manuelle rapide de bon fonctionnement, ou sur une machine sans les
dépendances de développement installées.

---

## Licence

MIT
