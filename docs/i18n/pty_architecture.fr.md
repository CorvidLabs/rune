*Ceci est une traduction de `docs/pty_architecture.md`. La version anglaise fait autorité en cas de divergence.*

# Architecture Pseudo-TTY (PTY) & TTY de Rune

> **Guide pour les développeurs et les agents IA**  
> *Comprendre comment Ruby gère les pseudo-terminaux, les flux interactifs et l'automatisation des invites dans `rune`.*

---

## 1. Vue d'ensemble : qu'est-ce qu'un Pseudo-TTY (PTY) ?

Lorsqu'un programme s'exécute dans un sous-shell normal ou un tube (pipe) de sous-processus (par ex. `IO.pipe` ou l'exécution standard d'un sous-shell), le système d'exploitation attache des tubes standard pour `stdin`, `stdout` et `stderr`. De nombreux programmes CLI (comme `git`, `docker`, `python`, `zsh`, `sudo`) détectent si `stdout` est un terminal (en utilisant `isatty()`) et désactivent les couleurs, le formatage de l'invite ou la mise en tampon ligne par ligne si ce n'est pas le cas.

Un **Pseudo-TTY (PTY)** est une paire de périphériques de terminal virtuel — maître et esclave — au niveau du noyau :
- **PTY esclave** : attaché au processus enfant comme terminal de contrôle (`tty`). Le processus enfant croit s'exécuter dans un véritable terminal (comme iTerm2 ou xterm).
- **PTY maître** : détenu par `rune` (`PTYRunner`). `rune` lit la sortie du processus enfant et écrit les entrées clavier directement dans le descripteur maître.

```
+------------------+         Master PTY          Slave PTY         +-------------------+
|  Rune PTYRunner  | <=======================> (Virtual Terminal) <==> |  Child Process    |
| (Agent / Human)  |    (reader / writer IO)                       | (bash, git, etc.) |
+------------------+                                               +-------------------+
```

---

## 2. Exécution d'un PTY en Ruby (`PTY.spawn`)

La bibliothèque standard de Ruby fournit `require 'pty'`. `rune` utilise `PTY.spawn` dans `lib/rune/pty_runner.rb` :

```ruby
PTY.spawn(env, command) do |reader, writer, pid|
  # reader: IO object to read output from slave PTY
  # writer: IO object to write stdin into slave PTY
  # pid:    Process ID of child process
end
```

### Lecture par morceaux non bloquante (`readpartial`)

La lecture standard ligne par ligne (`reader.each_line`) bloque jusqu'à la réception d'un saut de ligne (`\n`). **Les invites interactives** (telles que `Password: `, `Select option [y/N]`, ou `user@host:~$ `) **ne se terminent pas par un saut de ligne**. Si vous lisez avec `each_line`, le processus parent bloque en attendant `\n`, pendant que le processus enfant attend une entrée utilisateur — ce qui provoque un **interblocage (deadlock)**.

Pour éliminer les interblocages, `rune` lit des morceaux (chunks) avec `readpartial(4096)` :

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

Lorsque le processus enfant se termine, le PTY esclave se ferme, et `readpartial` lève `Errno::EIO` ou `EOFError`, que `rune` intercepte pour terminer proprement.

---

## 3. Assainissement ANSI et double sortie (humain et agent)

`rune` capture les séquences d'échappement ANSI brutes du terminal (couleurs, déplacements de curseur, effacements d'écran).

- **Pour les humains (mode TTY)** : la sortie brute est formatée avec `Renderer.render_tty`, avec couleurs complètes et formatage interactif.
- **Pour les agents IA (mode JSON)** : la sortie est traitée via `Parsers::TextSanitizer.strip_ansi(raw_output)` pour supprimer les codes ANSI et renvoyer du texte propre, économe en tokens pour les LLM. Cela n'est vrai sans réserve qu'en l'absence de `--max-output` : ce drapeau borne les deux champs indépendamment selon le même budget, de sorte qu'ils décrivent alors des fenêtres différentes de l'exécution et que `clean_output` n'est plus `strip_ansi(raw_output)` :

```ruby
# Strips SGR ANSI color codes, cursor escape codes, and terminal controls
ANSI_REGEX = /\e\[[0-9;]*[a-zA-Z]/
clean_output = text.gsub(ANSI_REGEX, '')
```

---

## 4. Logique de détection des invites (`Parsers::PromptDetector`)

Pour déterminer si une commande est terminée ou si elle attend sur une invite interactive, `Parsers::PromptDetector` analyse les fragments de lignes au fil de l'eau :

### Signatures d'invites prises en charge :
- Invites shell PS1 : `user@host:~$ `, `bash-5.2# `, `➜  rune git:(main)`, `❯ `
- Menus et choix interactifs : `Select:`, `[y/N]`, `(y/n)?`, `Password: `

Deux signatures que cette liste prétendait autrefois couvrir ne sont **pas** détectées, et ont été retirées de la liste plutôt qu'ajoutées au détecteur, car le conservatisme de celui-ci est délibéré : `Select an option: ` (le motif d'interrogation est ancré, il correspond donc à `Select:` mais pas à une phrase se terminant par deux-points) et `(venv) λ ` (`λ` ne fait pas partie de la classe des glyphes d'invite, qui est `➜ ❯ ›`).

### Rejet des faux positifs :
`PromptDetector` ignore les lignes contenant des comparaisons de code (`if x > 5`) ou des affectations de variables shell (`export PATH=$PATH`). Une citation Markdown telle que `> quote` est également rejetée, mais parce qu'elle ne correspond à aucun motif positif, et non par une exclusion — l'exclusion des citations ne se déclenche que sur une ligne contenant aussi du texte entre chevrons.

---

## 5. Moteur d'automatisation par scripts (`Rune::Script`)

`rune` permet de définir des scripts DSL interactifs pour automatiser des programmes PTY en plusieurs étapes :

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

Le moteur de script traite les étapes en une seule passe non bloquante, de sorte que `send_keys` écrit immédiatement dans `writer` sans attendre les morceaux (chunks) suivants.

---

## 6. Passthrough interactif en direct (`PTYWatcher` / `rune watch`)

`PTYRunner` met en tampon l'intégralité de la sortie d'une commande et ne rend la main qu'à sa fin : c'est le bon comportement pour les scripts et la capture, mais pas pour s'installer réellement au clavier et piloter un programme interactif pendant qu'autre chose observe la session. `PTYWatcher` (`lib/rune/pty_watcher.rb`) est une classe distincte dédiée à ce cas d'usage bidirectionnel et en direct, plutôt qu'un mode greffé sur `PTYRunner` — le modèle d'exécution (mode terminal brut, un thread d'arrière-plan pour le transfert de l'entrée) est suffisamment différent pour ne pas y avoir sa place, et le contrat « exécuter, capturer, retourner une fois » de `PTYRunner` reste gelé.

### Mode terminal brut (`io/console`)

Pour que les touches fléchées et les autres entrées d'un octet ou de séquences d'échappement atteignent le processus enfant, le terminal de contrôle du processus *parent* lui-même doit quitter le mode canonique (cooked), dans lequel le noyau met l'entrée en tampon ligne par ligne et affiche les frappes en écho localement jusqu'à l'arrivée d'un saut de ligne. `io/console` (chargé explicitement, et non tiré implicitement par `pty`) ajoute `IO#raw`, que `PTYWatcher#with_raw_input` enveloppe autour de toute la session de transfert :

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

Le drapeau `entered` compte : une fois le mode brut réellement engagé, une exception sans rapport venant des profondeurs de la session (un réceptacle de sortie défaillant, par exemple) doit se propager normalement, et non être traitée comme « le mode brut n'est pas pris en charge », ce qui relancerait silencieusement une deuxième fois l'intégralité de la session déjà démarrée.

### Transfert bidirectionnel

Contrairement à la boucle de lecture unique de `PTYRunner`, `PTYWatcher` exécute deux choses simultanément : un thread d'arrière-plan transfère les frappes réelles de l'humain vers le PTY de l'enfant à mesure qu'elles arrivent (`forward_input`), tandis que le thread principal scrute la sortie de l'enfant et la diffuse immédiatement à l'écran (`pump_output`), au lieu de l'accumuler dans un tampon qui ne serait rendu qu'à la fin.

Les deux chemins décodent avec `UTF8StreamDecoder`, qui conserve un suffixe UTF-8 incomplet entre les appels à `readpartial`. Un caractère multi-octets valide est donc préservé même lorsque le noyau le répartit sur plusieurs morceaux (chunks) ; les séquences réellement invalides ou définitivement incomplètes deviennent tout de même des caractères de remplacement.

`PTYWatcher` répercute également les dimensions actuelles du terminal de contrôle (lignes/colonnes) sur le PTY de l'enfant. Il les revérifie pendant la boucle de scrutation de la sortie, de sorte qu'un redimensionnement du terminal parvienne à l'enfant sans travail dangereux à l'intérieur d'un piège à signal.

```
+------------------+   keystrokes    +------------------+   output    +-------------------+
|  Human terminal  | --------------> |  PTYWatcher       | ----------> |  Real terminal      |
|  (raw mode)      |  (bg thread)    |  (master PTY)     |  (live)     |  screen + NDJSON log |
+------------------+                 +------------------+             +-------------------+
```

### Journal d'événements NDJSON

Chaque morceau (chunk) qui atteint l'écran est également écrit comme un événement NDJSON dans un fichier journal (par défaut un fichier temporaire annoncé, en `0600` et protégé contre les collisions, ou `--log=PATH`), de sorte qu'un agent IA puisse suivre la session en direct avec `tail -f` sans qu'aucun bruit JSON n'aboutisse dans le terminal de l'humain :

```json
{"event":"start","command":"...","pid":12345}
{"event":"output","bytes":42,"text":"..."}
{"event":"exit","exit_code":0}
```

Délibérément pas stderr par défaut : stderr partage le terminal de l'humain avec le passthrough en direct, et l'usage réel a immédiatement montré qu'entrelacer du JSON dans une session interactive la rendait illisible.

Si le réceptacle de sortie se ferme avec `EPIPE`, `PTYWatcher` tue puis récolte le processus enfant avant de retourner un échec structuré, empêchant un processus interactif détaché de survivre au watcher.

---

## 7. Gestion des erreurs et codes de sortie

`PTYRunner` comme `PTYWatcher` normalisent les codes de sortie Unix à travers les cas limites :

| Condition | Code de sortie | Traitement |
| :--- | :--- | :--- |
| Sortie normale | `status.exitstatus` | Achèvement propre |
| Commande introuvable | `127` | Intercepte `Errno::ENOENT` |
| Permission refusée | `126` | Intercepte `Errno::EACCES` |
| Délai d'exécution dépassé (`PTYRunner` uniquement) | `124` | Intercepte `Timeout::Error`, puis envoie `SIGKILL` à l'enfant et le récolte — `Timeout.timeout` interrompt uniquement le flot de contrôle de Ruby lui-même, pas le processus OS engendré |
| Enfant tué (signal) | `128 + sig` | Signaux comme `SIGKILL` (137) ou `SIGTERM` (143) |

---

## Résumé pour les développeurs

`rune` combine :
1. `PTY.spawn` pour une véritable émulation de terminal.
2. `readpartial` pour une lecture de flux sans aucun interblocage.
3. `UTF8StreamDecoder` plus `TextSanitizer` pour un JSON agent propre et sûr vis-à-vis des frontières de caractères.
4. `PromptDetector` pour des vérifications d'interactivité intelligentes.
5. Le DSL `Script` pour une saisie automatisée pas à pas.
6. `PTYWatcher` + le mode brut `io/console` pour des sessions bidirectionnelles en direct pilotées par l'humain, avec un journal NDJSON qu'un agent peut suivre avec `tail -f`.
