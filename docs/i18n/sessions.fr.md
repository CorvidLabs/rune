> Cette page traduit `docs/sessions.md`. En cas de divergence, la version anglaise fait foi.

# Sessions persistantes (`rune session`)

`rune run` lance une commande, met tout en mémoire tampon et rend la main une seule fois.
`rune watch` diffuse une session en direct, mais exige un véritable terminal humain sur stdin.
Aucun des deux ne peut garder ouvert un processus fils de type REPL entre des appels `rune`
distincts — un agent n'avait donc aucun moyen de *lancer `codex`, envoyer une invite, attendre la
réponse, puis envoyer une question de suivi.*

`rune session` comble ce manque. Le processus fils d'une session nommée survit à l'invocation de
`rune` qui l'a démarrée, et `send` bloque jusqu'à ce que le fils ait réellement répondu.

## Nommage : chaque session en a un, et vous avez rarement à le choisir

Les sessions sont cloisonnées par **répertoire** : un projet, c'est le nom de base du répertoire de
travail plus un hachage de son chemin, de sorte que deux worktrees git d'un même dépôt constituent
deux espaces de noms distincts. `start` indique celui dans lequel il s'est enregistré, et lire ce
champ fait la différence entre un détour de cinq minutes et une heure perdue :

```console
$ rune session start --name reviewer -- grok
{"name":"reviewer","project":"myrepo-0a922f34","command":["grok"],"state":"running",...}
```

Un `read` lancé depuis le mauvais répertoire répond *"No such session"*, et `list` — que cette
erreur suggère — affiche un tableau vide, ce qui se lit comme la confirmation que la session est
morte plutôt que comme le signe que vous vous trouvez ailleurs.

```console
$ rune session start -- grok
{"name":"grok-amber","command":["grok"],"child_pid":68012,"supervisor_pid":67926,"state":"running"}
```

Omettez `--name` et rune génère un nom de code `<tool>-<word>` inutilisé. Cela compte plus qu'il
n'y paraît : « la session grok » cesse de signifier quoi que ce soit dès qu'il y en a deux, et un
agent qui en démarre une ne devrait pas avoir à inventer des identifiants. Passez
`--name reviewer` quand vous voulez choisir.

Les noms sont **limités à un projet** — l'arborescence de travail git qui les contient, ou le
répertoire lui-même en dehors d'une telle arborescence. `reviewer` dans un checkout et `reviewer`
dans un autre sont deux sessions différentes, et aucune n'est accessible depuis le mauvais
répertoire :

```console
$ rune session list                  # this project only
$ rune session list --all-projects   # everything, labelled by project
```

## La boucle

```console
$ rune session start --name grok -- grok
{"name":"grok","command":["grok"],"child_pid":68012,"supervisor_pid":67926,"state":"running"}
```

**La réussite de `start` ne signifie pas que le fils tourne.** Si la commande n'existe pas, la
réponse reste `status: "ok"` et `rune` quitte quand même avec le code 0 — avec `state: "exited"`
et `exit_code: 127` dans le corps. Le démarrage lui-même a fonctionné ; le fils est mort
instantanément. Vérifiez `state`, pas le code de sortie du processus.

`start` rend la main immédiatement et le processus `rune` se termine. `grok` continue de tourner,
sous la responsabilité d'un superviseur détaché qui détient son pty.

```console
$ rune session send --name grok --settle-ms 2500 "reply with exactly the word PONG"
```

`send` écrit l'invite, attend que grok cesse de produire une sortie pendant 2,5 s, et renvoie
**uniquement ce que cet envoi a produit**. L'état persiste entre les appels, car c'est le même
processus fils à chaque fois :

Une option mal orthographiée est refusée au lieu d'être tapée au fils. `send --name grok
--settle_ms 500 'echo HELLO'` (un tiret bas, pas un tiret) ne correspondait autrefois à aucune
option, si bien que l'option, sa valeur et l'invite étaient concaténées en une seule ligne et
écrites à l'agent — `status: ok`, et un modèle payant qui répondait à `--settle_ms 500 echo
HELLO`. La vérification n'examine que les jetons situés avant le premier opérande et avant tout
`--`, donc `start --name x claude --resume` démarre toujours un agent avec ses propres options, et
`send --name x -- --settle_ms` tape toujours `--settle_ms` comme saisie littérale.

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

Chaque ligne indique depuis combien de temps la session est silencieuse et la dernière ligne
qu'elle a affichée — ce qui est la réponse la plus rapide à la question *celle-ci travaille-t-elle
ou est-elle bloquée, et que fait-elle ?* quand plusieurs agents tournent en même temps. Les mêmes
champs (`idle_ms`, `last_line`) sont disponibles dans `--json`.

## Prendre les commandes, puis les rendre

```console
$ rune session attach --name grok-amber
[rune session] attached — Ctrl-] to detach (session keeps running)
```

`attach` connecte votre véritable terminal à une session en cours : la sortie s'affiche sur votre
écran, vos frappes vont à l'agent, l'écran courant est rejoué à la connexion pour que vous ne
restiez pas devant un écran vide, et **le fils est redimensionné à la taille de votre terminal**
(et la suit quand vous redimensionnez), de sorte qu'un agent plein écran se met en page pour votre
fenêtre plutôt que pour la valeur par défaut sans affichage. Quand vous vous détachez, le fils
revient à cette valeur par défaut, donc les `send` programmatiques produisent le même rendu, que
vous soyez attaché ou non. **Ctrl-]** détache et laisse tout tourner — c'est toute la différence
avec `rune watch`, qui possède le fils qu'il a lancé. Ctrl-C n'est délibérément *pas* la touche de
détachement : elle doit continuer d'atteindre le fils pour que vous puissiez interrompre un agent
emballé.

## Archivage

Une session arrêtée garde son nom réservé et encombre `list`. Archivez-la :

```console
$ rune session stop --name reviewer
$ rune session archive --name reviewer
$ rune session list --archived
```

L'archivage libère le nom et classe la transcription dans les archives du projet. Une session
archivée est hors de portée de `read` — `read --name` sur celle-ci répond qu'il n'existe pas de
telle session — récupérez donc tout ce que vous voulez garder *avant* d'archiver. Une session
archivée ne peut jamais être confondue avec une session active, et réutiliser le nom repart
véritablement de zéro — `start` réinitialise la transcription, de sorte que les curseurs de `send`
et les décalages de `read` décrivent toujours la même durée de vie.

## Savoir quand l'autre agent a terminé

C'est la partie difficile, et rune vous donne trois outils par ordre de préférence.

**`--settle-ms N` (800 par défaut)** — rendre la main une fois que le fils est resté silencieux
pendant N ms. C'est le signal principal. Le chronomètre de stabilisation ne démarre qu'à l'arrivée
d'une sortie qui n'est pas l'écho du pty renvoyant votre propre saisie, de sorte qu'un agent qui
répercute votre invite puis réfléchit avant de répondre renvoie la réponse plutôt que vos propres
mots.

> **Une invite qui n'est jamais soumise ressemble exactement à cela aussi, et c'est un bogue
> différent.** rune écrit le texte d'un envoi puis son retour chariot dans une écriture *séparée*
> un instant plus tard, car une TUI qui les lit ensemble traite le retour comme faisant partie du
> texte et ne soumet jamais. Ce délai est une course critique que rien ne peut observer : mesuré
> contre Kimi, l'ancien délai de 0,05 s perdait 3 envois sur 3 — l'invite restait dans le
> compositeur, `send` renvoyait `settled: true` avec seulement l'écho, et le fils attendait une
> frappe qui avait déjà été écrite. Il est désormais de 0,25 s, et Claude Code, grok et Kimi
> soumettent tous. Si vous rencontrez une TUI plus lente encore, le signe révélateur est que
> `read --screen` montre votre texte qui attend dans la zone de saisie : envoyez une chaîne vide
> pour délivrer un simple retour chariot, et il partira.

> **Limitation connue, et la plus acérée de rune aujourd'hui : un fils qui *redessine* votre saisie
> peut tout de même se stabiliser dessus.** La règle ci-dessus vaut quand l'écho arrive une seule
> fois. Un éditeur de ligne qui redessine la ligne à la soumission renvoie votre saisie une seconde
> fois, et cette seconde copie compte comme si le fils avait parlé. Mesuré avec
> `--settle-ms 800` : `irb` et `python3 -q` renvoient `settled: true` en une seconde environ avec
> seulement l'écho, 3 fois sur 3 chacun, tandis que la vraie réponse arrive quelques secondes plus
> tard et atterrit dans ce que l'appel *suivant* capture. Un simple `bash -i` n'est pas affecté, y
> compris pour des saisies qui dépassent la largeur du terminal.
>
> **Rien dans la réponse ne distingue ce cas d'une vraie réponse** — `settled: true`,
> `busy_at_send: false`, et l'écho fait légitimement partie d'une réponse correcte aussi. En
> attendant que ce soit corrigé, pilotez un REPL qui redessine avec `--wait-for-regex`, qui n'est
> pas affecté, ou vérifiez que la réponse contient quelque chose au-delà de ce que vous avez
> envoyé.

**`--wait-for-regex RE`** — rendre la main dès que la sortie correspond. Déterministe, et la bonne
réponse chaque fois que vous savez ce que le destinataire affiche quand il a terminé :

```console
$ rune session send --name s --wait-for-regex '\$ $' "ls"
```

> **Le motif est comparé à la réponse, pas à l'écho de votre saisie.** Un pty répercute ce que vous
> écrivez, donc une implémentation naïve rend la main à l'instant où vos propres mots reviennent.
> rune localise l'écho dans le texte *condensé* — échappements et espaces retirés des deux côtés, ce
> qui fait la différence entre ce que vous avez envoyé et chaque écho transformé que nous avons pu
> capturer — et oppose son veto à une correspondance qu'une copie redessinée de la saisie recouvre.
> Mesuré contre `python3 -q`, dont le REPL redessine à chaque frappe : auparavant il rendait la
> main en 0,22 s avec `matched: true`, huit secondes avant que le code ne s'exécute, 4 fois sur 4 ;
> il attend désormais la vraie sortie, 3 fois sur 3.
>
> L'affirmation honnête est *chaque forme d'écho que nous avons pu capturer d'un vrai fils est
> exclue*, et non *cela ne peut pas arriver*. Si votre motif est un littéral que vous avez aussi
> envoyé, un fils qui récite votre demande mot pour mot peut quand même le satisfaire. Le veto doit
> aussi *voir* la copie : un redessinage qu'une lecture du pty a coupé en deux — la trame s'arrête
> au milieu du redessinage et le reste arrive à la lecture suivante — n'est pas encore reconnaissable
> comme une copie, et un motif qui n'apparaît qu'à l'intérieur de votre propre saisie peut être
> satisfait par cette moitié. Reproduit de façon déterministe en scindant une trame juste après le
> jeton. Un motif qui apparaît aussi dans ce que vous avez envoyé reste donc la forme à éviter.

> **Volume de sortie sur lequel le motif est comparé : les 256 Ko les plus récents après l'écho,
> relus 32768 caractères en arrière à chaque lecture.** C'est une borne délibérée, avec deux
> conséquences.
>
> - **Une correspondance unique pouvant atteindre 32768 caractères est toujours trouvée**, quelle
>   que soit la taille atteinte par le tour, car chaque balayage reprend cette distance en arrière
>   de l'endroit où le précédent s'est arrêté. Tout ce que vous attendriez raisonnablement — un
>   marqueur, une invite, une clôture de bloc — est bien en deçà.
> - **Une correspondance unique qui doit s'étendre sur plus de 32768 caractères n'est jamais
>   trouvée.** `OPEN[\s\S]*CLOSE` sur un demi-mégaoctet correspondait autrefois et ne correspond
>   plus ; l'envoi se poursuit jusqu'à `--settle-ms` ou `--timeout-ms` à la place. Attendez `CLOSE`
>   seul et utilisez `read` si vous avez besoin de l'intervalle entre les deux.
>
> `\A` s'ancre toujours au début de la réponse du fils, pas au début de la fenêtre — un motif ancré
> ne peut pas être satisfait par l'endroit où la fenêtre commence par hasard. `^`, `$` et `\z` ne
> sont pas affectés. **La réponse n'est bornée par rien de tout cela :** `output` reste tout ce que
> le fils a produit pendant le tour.
>
> Cette borne est ce qui rend une grande réponse accessible en premier lieu. Le motif était
> autrefois comparé à l'ensemble du tour à chaque lecture de 4 Ko, ce qui est quadratique en la
> taille du tour — et sur le seul thread du superviseur, ce qui affamait aussi la vidange du pty.
> Mesuré contre un fils qui émet N Mo puis affiche un marqueur, avec ce même marqueur comme motif :
>
> | output | avant | après |
> | --- | --- | --- |
> | 4 MB | 11.85s, matched | 0.53s, matched |
> | 12 MB | 90.51s, `timed_out: true`, 11.46 MB of 12.00 read | 0.98s, matched, 12.15 MB read |
> | 48 MB | 112.43s, matched | 3.37s, matched |
>
> À 12 Mo, l'envoi signalait un dépassement de délai alors qu'il détenait 96 % d'une réponse dont
> le fils avait déjà affiché le marqueur.

**`--timeout-ms N` (120000 par défaut)** — un plafond strict. À l'échéance, vous obtenez ce qui a
été capturé plus `settled: false, timed_out: true` — un résultat, pas un échec. Réglez cette
valeur délibérément : la valeur par défaut est généreuse parce que les agents sont lents, donc un
appel erroné coûte deux minutes.

`--no-wait` écrit et rend la main immédiatement, pour les cas où vous n'attendez aucune réponse. Sa
réponse a une forme différente — `{action, name, sent: true, waited: false}`, sans `output`,
`cursor` ni `prompt_detected`, car rien n'a été attendu.

`--no-newline` écrit le texte sans le retour chariot final qui le soumet, pour composer une ligne
par morceaux ou piloter une TUI qui lit les frappes.

### Les autres champs d'une réponse

- `settled: true` — **l'attente a reçu une réponse au lieu d'expirer.** Trois choses différentes
  l'activent, et le champ compagnon vous dit laquelle : le fils est resté silencieux pendant la
  fenêtre de stabilisation (pas de champ compagnon), `--wait-for-regex` a trouvé une correspondance
  (`matched: true`), ou le fils s'est terminé (`child_exited: true`). À lui seul, il ne signifie
  **pas** que le fils s'est tu — une correspondance de regex l'active sans aucune période de
  silence, c'est pourquoi une réponse peut porter `settled: true` 0,45 s après le début d'une
  fenêtre de stabilisation de 60 secondes.

  Là où il signifie *bel et bien* un silence, ce silence a trois causes que ce champ ne peut pas
  distinguer : le tour est terminé, le fils attend un humain, ou **le fils a mis une longue commande
  en arrière-plan et a cessé d'afficher quoi que ce soit**. C'est ce troisième cas qui mord : un
  appelant qui scrutait la disparition d'un marqueur d'activité a lu une trame sans ce marqueur et
  a conclu que le travail était terminé, 260 secondes avant qu'il ne le soit. Si votre décision
  repose sur l'*absence* de quelque chose, `settled` n'est pas une preuve suffisante à lui seul.
- `timed_out: true` — `--timeout-ms` a été atteint en premier. Un résultat, pas un échec.
- `matched: true` — `--wait-for-regex` a trouvé une correspondance.
- `child_exited: true` — le fils s'est terminé pendant que l'envoi était en cours.
- `busy_at_send: true` — le fils *produisait encore une sortie* quand cet envoi est arrivé, donc la
  réponse peut contenir la fin du tour précédent. À vérifier si une réponse semble appartenir à la
  question précédente.
- `regex_timed_out: true` — le motif de `--wait-for-regex` a dépassé son budget de correspondance et
  a été abandonné. Presque toujours un motif à retour sur trace catastrophique ; simplifiez-le.
- `dropped_bytes` — le nombre d'octets de sortie antérieure que le journal ne détient plus :
  évacués par rotation, ou perdus parce qu'une écriture de transcription a échoué. Cela
  n'invalide **pas** un curseur `--since` : les curseurs restent absolus, donc un curseur antérieur
  à une perte renvoie tout ce qui est encore détenu *après* elle plutôt qu'une erreur. Un curseur
  qui tombe à l'intérieur d'une région perdue se résout sur la sortie qui a suivi cette région —
  jamais sur une sortie déjà livrée, qui arriverait en ayant l'air d'une nouvelle sortie pour le
  tour courant.
- `transcript_gap_bytes` — sur `status` et sur une réponse de `send` uniquement, et seulement tant
  qu'une sortie qu'aucune écriture n'a pu enregistrer reste due. C'est la seule fenêtre où le décalage
  n'est pas sur le disque : la prochaine écriture réussie l'enregistre et `read` le signale alors
  comme `dropped_bytes`.
- `screen_rows`, `screen_cols`, `screen_size_recorded` — seulement avec `--screen` : la géométrie à
  laquelle l'écran a été rendu, et si cette géométrie est le winsize enregistré du fils ou la
  valeur de repli. Voir [Il rend à la taille à laquelle le fils tourne réellement](#il-rend-à-la-taille-à-laquelle-le-fils-tourne-réellement).

### `child_busy` et `idle_ms` sont sur `read`, pas sur `send`

Indique si le fils a affiché quoi que ce soit dans la fenêtre de stabilisation, et depuis combien
de temps il ne l'a plus fait. C'est la forme structurée de « est-ce qu'il travaille encore » :
utilisez-la plutôt que de chercher avec grep un marqueur d'activité dans l'interface du
destinataire, qui est de la présentation et change sans prévenir.

**Ce sont des champs de `read` et de `list`, pas d'une réponse de `send`.** Un `send` a déjà bloqué
jusqu'à ce que le fils se stabilise, donc posez la question après :

```console
$ rune session send --name grok --settle-ms 2500 "run the suite"
$ rune session read --name grok --tail 1 --json     # child_busy, idle_ms
```

Ce document listait auparavant les deux parmi les champs d'une réponse de `send`, ce qui est faux
de la manière qui compte le plus — un appelant qui lit `.child_busy` sur un `send` obtient `nil`,
et se rabat sur un grep de l'interface, ce qui est exactement ce que ces champs existent pour
remplacer.

Notez que le nom dit que le fils *affiche*, pas qu'il *travaille* : un fils qui a mis une commande
en arrière-plan et s'est tu rapporte `child_busy: false`.

### Retrouver quelque chose dans une longue transcription

`--since` et `--tail` ne servent à rien quand ce que vous cherchez est au milieu. Une journée de
travail avec un agent piloté a atteint 379 Ko.

```console
$ rune session read --name grok --grep 'THE BOARD' --context 2
```

La recherche porte sur le texte *nettoyé* plutôt que sur le flux brut, car les trames de
redessinage d'un agent plein écran scindent les mots à travers des séquences d'échappement — un
motif que vous voyez clairement à l'écran ne correspondra pas aux octets. La réponse porte
`grep_matches`.

**Nettoyé n'est pas rendu, et la différence mord exactement sur les fils pour lesquels les sessions
existent.** Le texte nettoyé est l'ensemble du flux de redessinage débarrassé de ses échappements,
donc : l'historique écrasé correspond toujours, et revient sous forme d'une ligne autonome propre
que l'écran n'a plus affichée depuis ; une trame peinte au curseur n'a aucun saut de ligne, c'est
donc une seule ligne pour grep, `--context` ne fait rien, et une seule correspondance renvoie la
trame entière sous un `grep_matches: 1` à l'apparence plausible ; et un motif ancré à ce que vous
voyez à l'écran peut renvoyer `grep_matches: 0`, car la contiguïté à l'écran n'est pas la contiguïté
dans le flux. Quand la question est *qu'est-ce qui est affiché en ce moment*, utilisez `--screen`.
`--grep` sert à retrouver une ligne dans une longue transcription, ce pour quoi il est bon.

Un motif qui ne compile pas revient sous forme de `grep_error` plutôt que d'une exception, et **ne
sélectionne rien** : `output` et `clean_output` sont vides et `grep_matches` est absent, ce qui
vous permet de distinguer « le filtre n'a jamais tourné » de « le filtre n'a rien trouvé ». La
lecture elle-même réussit quand même, donc `cursor`, `prompt_detected` et `child_busy` sont tous
toujours présents — aucun ne dépend du motif, et vous avez besoin du curseur pour avancer.
(`send --wait-for-regex` est différent : là, le motif décide quand rendre la main, donc un motif
défectueux est refusé d'emblée.)

### `prompt_detected` n'est qu'indicatif

Chaque résultat de `send`/`read` porte `prompt_detected`, mais **ne le conditionnez à rien**, et
sachez dans quel sens il se trompe.

Mesuré contre des sorties réelles : il vaut `false` pour du texte simple, `false` pour un `$ `
nu, **`false` pour `Do you want to proceed?`**, et `true` pour `❯ `. Donc pour grok il vaut `true`
sur pratiquement chaque lecture, parce que le compositeur de grok se termine toujours par `❯` — un
appelant l'a vu à `true` 8 fois sur 8 et a conclu qu'il ne discriminait rien. Il discrimine ; il
détecte simplement des *dernières lignes en forme d'invite*, ce qui n'est pas la même question que
« est-ce que cela attend ma réponse ». Notez le troisième cas ci-dessus : il vaut `false` pour
précisément la boîte de dialogue de permission que vous voudriez le plus voir capturée. Pour cela,
regardez l'écran. Les motifs d'invite de rune correspondent à des invites en forme de shell
(`user@host:~$`, `[y/N]`, `Password:`) et sont délibérément conservateurs. Les REPL d'agents ne
ressemblent pour l'essentiel à aucun d'entre eux, donc pour exactement les CLI que vous voulez
piloter, il vaut généralement `false`. Attendre une invite bloquerait indéfiniment contre la
plupart des cibles réelles — c'est pourquoi le temps de stabilisation est le signal principal.

## Lire la transcription

`read` rejoue la transcription durable de la session, et fonctionne de la même façon que la session
soit active ou déjà arrêtée :

```console
$ rune session read --name grok --tail 50
$ rune session read --name grok --since 41234     # page from a cursor a previous call returned
```

Chaque session écrit un journal d'événements NDJSON dans le même format que celui que produit
`rune watch`, vous pouvez donc suivre une session active depuis un autre panneau :

```console
$ tail -f ~/.rune/projects/<project>/sessions/grok/output.ndjson
```

Les agents TUI plein écran génèrent beaucoup de trafic de redessinage ANSI, donc préférez
`--tail`/`--max-output` à la lecture d'une transcription entière.

`--max-output=BYTES` conserve un début et une fin et marque la jointure dans le texte lui-même :

```
...the last line before the cut
[rune] ==== 41233 bytes omitted by --max-output ====
the first line after it...
```

Sans cette ligne, la réponse se lit comme une sortie continue que le fils n'a jamais affichée —
mesuré, une transcription de 201 octets à `--max-output=200` a perdu l'unique octet qui transformait
`chsh -s /bin/zsh` en `chsh -s bin/zsh`, un chemin différent et toujours plausible. Le marqueur est
une annotation de rune et non de la transcription, donc il n'est pas imputé sur BYTES et une réponse
peut dépasser un peu le budget ; `truncated` et `omitted_bytes` restent la réponse faisant autorité,
car un fils peut afficher n'importe quoi, y compris une ligne qui ressemble au marqueur.

### `--screen` : ce que le terminal affiche, pas ce qui est arrivé

Pour un agent plein écran, c'est généralement le champ que vous voulez. Le flux d'octets contient
chaque trame de chaque redessinage, avec la réponse répartie entre elles ; l'écran ne contient que
ce qui est affiché.

```console
$ rune session send --name grok --screen -- "reply with just the branch name"
$ rune session read --name grok --screen
```

Mesuré contre grok : une transcription de 361 Ko s'est rendue en un écran de 1,1 Ko, et une réponse
que l'agent avait clairement affichée était **absente du flux d'octets sur 3 tours sur 3 et présente
dans l'écran rendu sur 3 tours sur 3**. Si vous faites des correspondances sur le contenu, faites-les
sur `screen`.

Trois choses qu'il n'est pas. C'est l'*état final*, donc tout ce qui a défilé hors de vue a disparu —
la transcription reste le dossier de ce qui s'est passé. Il est optionnel parce qu'il n'a de sens que
pour un fils qui peint un écran : pour un shell en mode cooked, le flux d'octets est déjà la réponse.
Et il n'est **pas borné par les filtres de lecture** — `--since`, `--tail`, `--grep` et
`--max-output` bornent tous `output`/`clean_output` et laissent `screen` tranquille. Il est borné,
mais par la géométrie : au plus `screen_rows x (screen_cols + 1)`, les deux étant renvoyés dans la
même réponse. Une transcription de 219 941 octets se rend en environ 2 Ko. Donc
`--max-output=200 --screen` vous donne une réponse bornée, bornée par une règle que vous n'avez pas
nommée.

### Il rend à la taille à laquelle le fils tourne réellement

Le fils d'une session démarre en 40x120, et `attach` le redimensionne à la taille de quelque
terminal que ce soit qui en a pris le contrôle — la taille n'est donc pas une constante, et rendre
à une taille fixe produit un écran que personne n'a jamais vu. Le superviseur enregistre le winsize
courant du fils dans `meta.json` chaque fois qu'il le modifie, et `--screen` rend à cette taille et
la rapporte :

```console
$ rune session read --name grok --screen --json | jq '{screen_rows, screen_cols, screen_size_recorded}'
{ "screen_rows": 30, "screen_cols": 100, "screen_size_recorded": true }
```

Mesuré de bout en bout, avec pyte 0.8.2 et GNU screen 4.00.03 rejouant les mêmes octets comme
oracles indépendants (ils étaient exactement d'accord entre eux pour chaque forme) :

| ce qui était piloté | lignes fausses avant | lignes fausses après |
|---|---|---|
| redimensionnement par socket de contrôle vers 30x100, le fils redessine sur WINCH | 36/37 | **0/31** |
| le même à 24x80 | 30/31 | **0/25** |
| le même à 12x40 | 18/19 | **0/13** |
| le même à 50x200 | 50/51 | **0/51** |
| le même à 40x120 (les tailles coïncident) | 0/41 | 0/41 |
| un vrai `rune session attach` depuis un pty 30x100, le fils ignore WINCH | 29/30 | **0/30** |

Dans la ligne de l'attach, les oracles ont reçu les octets que ce terminal a lui-même reçus, donc
« 0 sur 30 » signifie que l'écran rendu par rune correspondait, ligne pour ligne, à ce que l'humain
regardait.

**`screen_size_recorded` est ce qui distingue une géométrie réelle de la valeur de repli — pas les
nombres.** Une session attachée depuis un terminal de 40 lignes enregistre exactement le même
40x120 que celui qu'utilise la valeur de repli, donc le couple à lui seul ne peut pas porter la
distinction. `screen_size_recorded` ne vaut true que lorsque la taille rapportée est celle que
`meta.json` contenait réellement. Il vaut false dans trois cas, qui rapportent tous 40x120 :

- une session que personne n'a redimensionnée. Le superviseur règle le pty à 40x120 et ne
  l'enregistre pas, donc la valeur de repli n'est ici pas une estimation — c'est la taille à
  laquelle le fils tourne réellement.
- un répertoire de session écrit avant que rune n'enregistre de taille du tout.
- une taille enregistrée qui n'est pas un terminal utilisable, et qui est écartée ou bornée plutôt
  qu'allouée : `meta.json` est un fichier sur disque et la grille est construite avec empressement.

Un redimensionnement arrivant par la socket de contrôle est borné à 300x1000 — au-delà de tout
terminal réel — et la borne est appliquée au pty comme à l'enregistrement, de sorte que le fils,
l'enregistrement et le rendu sont toujours d'accord. Les champs de winsize d'un pty sont sur 16
bits, et un 65535x65535 enregistré aurait fait piloter à chaque `--screen` ultérieur une grille de
cette taille : sur une transcription délibérément hostile de 683 Ko, un `read --screen` coûte 0,76 s
à 40x120, 3,41 s au plafond, et 17,72 s sans la borne.

**Un cas de redimensionnement n'est pas résolu.** Toute la transcription conservée est rendue à la
taille *courante* du fils, donc si la géométrie a changé en cours de route, la sortie peinte avant
le changement est remise en page à la nouvelle. Pour un agent plein écran, c'est juste, et c'est
prouvable : une TUI redessine sur SIGWINCH, et à l'attach le superviseur rejoue son arriéré dans le
terminal à la taille du terminal, ce qui est exactement ce que reproduit le rendu de toute la
transcription à cette taille — la ligne « 0 sur 30 » de l'attach ci-dessus vaut même pour un fils
qui ignore entièrement SIGWINCH. Ce n'est pas résolu pour un fils qui peint une fois et ne redessine
jamais *et* dont le pty est ensuite redimensionné sous un terminal déjà attaché, parce que ce
terminal remet en page des glyphes qu'il a déjà tracés et qu'il n'existe aucune réponse de référence
à laquelle se comparer. Réduit en plein flux de 40x120 à 24x80 sur un tel flux, GNU screen n'a
conservé que la ligne du curseur, pyte n'a rien conservé du tout, et les deux étaient en désaccord
entre eux sur une ligne du peu qu'ils avaient retenu. rune conserve le contenu et le remet en page,
donc il diffère des deux. Rendre à l'ancienne taille fixe obtenait un meilleur score au compte brut
des lignes (15 fausses contre 24), mais seulement parce qu'un écran presque vide correspond par
coïncidence à un oracle presque vide — pas parce qu'il montrait à quiconque quelque chose de plus
juste.

**Le rendu se fait à partir des 512 derniers Ko, et pour certains agents cela a un coût visible.**
Un recensement de la sortie de grok sur 4,5 Mo a trouvé 109 364 déplacements absolus du curseur,
31 798 délimiteurs de mises à jour synchronisées, et **zéro** effacement d'aucune sorte — pas de
`\e[K`, pas de `\e[2K`, pas de `\e[2J`, pas de régions de défilement. Un agent qui redessine
uniquement par positionnement et écrasement dépend du fait que le terminal se souvient de chaque
cellule qu'il a écrite, si lointaine soit-elle. Rendre depuis une fenêtre part au contraire d'une
grille vierge, donc tout ce qui a été peint une fois et jamais repeint — un en-tête, une bannière —
est tout simplement absent, et rune ne peut pas savoir qu'il manque. Lire `--screen` plus souvent
n'aide pas ; la fenêtre se mesure en octets, pas en temps.

Le même recensement explique un point plus subtil. Quand un agent n'efface jamais, une ligne
dupliquée à l'écran peut être entièrement fidèle : si sa mise en page glisse d'une ligne vers le bas
et qu'il redessine à la nouvelle position, rien ne supprime l'ancienne copie, et **un vrai terminal
affiche le doublon aussi**. Avant de traiter une ligne répétée comme un bogue de rune, vérifiez si
l'agent efface quoi que ce soit.

### Limitation connue : un `--screen` interrogé par scrutation peut renvoyer une trame à moitié peinte

Signalé depuis un usage réel, et **non corrigé**. Interroger `--screen` par scrutation sur un agent
qui redessine renvoie parfois une trame en plein redessinage — dans le cas signalé, une ligne
dupliquée sur deux lignes adjacentes.

Deux corrections candidates ont été mesurées et rejetées. Comparer des rendus consécutifs et ne
renvoyer qu'un rendu répété a mesuré **pire** que ne rien faire — 13 trames déchirées sur 20 contre
11 — parce qu'un agent qui peint en cycle rend rarement la même trame deux fois, donc la
vérification expire et rend la trame déchirée de toute façon. Redéfinir la stabilité comme une
quiescence n'a pas pu reproduire le déchirement du tout : le fils identique a donné 11/20 une fois
et 0/20 deux fois, ce qui signifie que le harnais ne mesurait pas ce qu'il semblait mesurer. Une
correction qui échoue silencieusement vers « a l'air terminé » est pire qu'une limitation que l'on
peut contourner.

**Quoi faire.** Ne traitez pas une trame rendue unique comme faisant autorité pour une décision que
vous ne pouvez pas défaire. Si vous lisez une valeur, interrogez deux fois et exigez l'accord. Si
vous attendez un marqueur, `--wait-for-regex` est déterministe là où `--screen` est un instantané.

**Ce n'est peut-être pas la faute de rune.** Un recensement de la sortie d'un agent sur 4,5 Mo a
trouvé zéro effacement d'aucune sorte, et un agent qui n'efface jamais et décale sa mise en page
laisse l'ancienne copie à l'écran — un vrai terminal affiche le doublon aussi. Le moteur de rendu de
rune est d'accord avec un émulateur indépendant sur six profils construits à partir de ce
recensement. Avant de déclarer une ligne dupliquée comme bogue de rune, vérifiez si l'agent efface
quoi que ce soit.

### La transcription est bornée

Le fichier comme la mémoire du superviseur sont plafonnés, donc une session laissée à tourner
pendant une journée ne grossit pas sans limite. Le plafond du fichier est appliqué deux fois :
normalement par rotation, et — quand la rotation ne peut pas réussir du tout, parce que le
répertoire est devenu non inscriptible ou qu'un disque est resté plein — par un plafond strict au
double de la borne, au-delà duquel la sortie est enregistrée comme perdue plutôt qu'écrite. Dans un
cas comme dans l'autre, `read` rapporte `dropped_bytes` et les curseurs restent absolus. Quand la
rotation évacue une sortie plus ancienne, `read` rapporte `dropped_bytes` et les curseurs restent
absolus — un curseur désigne toujours la même position dans le flux, il pointe simplement vers une
sortie qui n'est plus conservée.

Une écriture de transcription qui échoue — un disque plein, un répertoire non inscriptible — perd de
la sortie de la même façon, sauf qu'au *milieu* d'un flux qui se poursuit ensuite. Ces octets sont
conservés et enregistrés dès que l'écriture reprend, et un curseur est mis en correspondance à
travers chaque région perdue plutôt qu'au-delà d'un seul total cumulé, de sorte que la sortie
antérieure à un trou n'est pas relivrée comme si elle était nouvelle. Tant qu'une écriture n'a pas
réussi, il n'existe nulle part sur le disque où enregistrer le trou, ce que `transcript_gap_bytes`
sur `status` rapporte.

## Ce qu'il faut savoir avant de piloter un vrai agent

- **`start` rend la main quand le *superviseur* est prêt, pas le fils.** Un CLI d'agent met des
  secondes à démarrer, et une saisie envoyée avant qu'il n'écoute est tout simplement perdue.
  Attendez un marqueur de disponibilité — interrogez `read`, ou faites du premier `send` un
  `--wait-for-regex` — avant de piloter une session fraîchement démarrée.
- **La stabilisation est une heuristique.** Un fils qui marque une pause au milieu d'une réponse
  plus longtemps que `--settle-ms` renvoie une réponse tronquée. Augmentez la valeur, ou utilisez
  `--wait-for-regex`.
- **`--wait-for-regex` voit les 256 Ko les plus récents, pas tout le tour.** Toute correspondance
  unique pouvant atteindre 32768 caractères est toujours trouvée ; une correspondance qui doit
  s'étendre au-delà ne l'est jamais. Attendez un marqueur, pas un motif qui encadre des mégaoctets.
- **Une ligne unique de 1024 octets ou plus disparaît dans un fils en mode cooked.** C'est
  `MAX_CANON`, une limite du terminal, pas de rune : la discipline de ligne ne peut pas assembler une
  ligne canonique plus longue et l'abandonne silencieusement — 1023 octets arrivent, 1024 non. La
  plupart des CLI d'agents font tourner leur terminal en mode raw et ne sont pas affectés (300 Ko
  arrivent à l'octet près). Un shell interactif non plus : `bash --norc -i` utilise readline, qui
  met le terminal en mode raw, et accepte une ligne de 1995 caractères à l'octet près. La limite
  mord un fils qui lit en mode *cooked* — un simple `cat`, ou un script lisant stdin sans readline.
  Découpez en morceaux, ou pilotez une cible en mode raw.
- La touche Entrée est envoyée comme un retour chariot, ce qui est ce qu'un vrai terminal envoie, donc les TUI
  en mode raw le reçoivent. Les shells en mode cooked ne sont pas affectés.
- Le pty du fils reçoit une taille de fenêtre explicite, parce qu'une session détachée n'a aucun
  terminal auprès duquel en copier une et qu'un pty sans réglage vaut 0x0 — ce qui laisse les agents
  plein écran rendre dans le vide. Il démarre à 40x120, suit un terminal attaché tant qu'il y en a
  un (jusqu'à un plafond de 300x1000), et revient à 40x120 quand le dernier s'en va. `--screen` rend
  à celle de ces tailles qui est courante.

## Où vit l'état

`RUNE_HOME` (`~/.rune` par défaut), avec des permissions réservées au propriétaire :

```
$RUNE_HOME/projects/<project>/
  sessions/<name>/
    meta.json        0600   pid, supervisor pid, command, state, child terminal size
    output.ndjson    0600   full transcript
    supervisor.log   0600   supervisor stderr, for when something goes wrong
    control.sock     0600   the supervisor's control socket
  archive/<stamp>-<name>/   archived sessions, out of the live namespace
```

Définissez `RUNE_HOME` pour garder des sessions isolées (tests, bacs à sable, travail en parallèle).

`meta.json` est remplacé par renommage, jamais tronqué sur place, parce que tout autre processus
rune le lit pour répondre à « cette session existe-t-elle, et est-elle vivante ? » sans verrou à
prendre. Une fenêtre où il était tronqué était une fenêtre où `send` répondait « No such session »
et où `list` rapportait `state: dead` ; l'enregistrement du winsize du fils en a fait une écriture à
chaque redimensionnement, et un humain qui tire le bord d'une fenêtre en émet une par trame. Mesuré
à travers un vrai attach tiré sur 250 formes de fenêtre en 7,5 secondes, avec un autre processus
lisant meta en boucle serrée : 90 lectures sur 294 728 sont revenues illisibles avant, 0 sur
312 582 après.

## Ce que coûte d'en faire tourner plusieurs à la fois

Une session, c'est un processus superviseur, et cet isolement est délibéré : un agent bloqué
emporte sa propre session et rien d'autre. Le prix est un interpréteur Ruby par session, et il vaut
la peine de le savoir avant de démultiplier.

Mesuré, avec des fils inactifs :

| sessions | mémoire résidente | descripteurs |
|----------|-----------------|-------------|
| 24 | 543 MB | 648 |
| 60 | 1361 MB | 1620 |

Cela fait **~23 Mo et 27 descripteurs par session**, à plat — pareil à 60 qu'à 24, et inchangé au
fil de séries d'envois. Le coût est donc prévisible et linéaire plutôt que surprenant, mais il est
payé d'avance : soixante agents coûtent bien plus d'un gigaoctet avant qu'aucun d'eux ait fait quoi
que ce soit.

La concurrence elle-même a tenu sous le même test : 60 démarrages simultanés ont tous réussi, chaque
envoi a atteint la session à laquelle il était adressé, `list` était d'accord avec la réalité, et
rien ne tournait plus ensuite. Trente appels `start` simultanés *sans* `--name` pour le même outil
ont produit trente noms de code distincts et aucune collision.

## Périmètre

rune est un **courtier** de sessions, pas un bus de messages. Il détient des sessions et les adresse
par nom ; décider qui parle à qui est le travail de l'agent appelant — il a déjà les noms. Le
routage entre sessions, les profils par agent et un journal de conversation partagé sont
délibérément hors de portée.
