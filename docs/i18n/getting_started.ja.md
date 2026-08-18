> この文書は `docs/getting_started.md` の日本語訳です。内容に相違がある場合は、英語版を正文とします。

# rune をはじめる

`rune` は Ruby 製の CLI およびライブラリで、ターミナル上の人間からも、プログラム的に操作する AI
エージェントからも等しく使いやすいよう設計されています。すべてのコマンドは同じ構造化された `Result`
を返します。呼び出し方によって変わるのはその*レンダリング*だけです。

## インストール

`rune` という修飾なしの gem 名は、公開レジストリ RubyGems.org 上ですでに無関係のパッケージに
取得されているため、そこで `gem install rune` を実行すると別物がインストールされてしまいます。
サポートされているエンドユーザー向けのインストール方法は、CorvidLabs の Homebrew tap にある
チェックサム固定の formula です。

```sh
brew install corvidlabs/tap/rune
rune version --json
```

初回インストール時に Homebrew が自動的に tap を追加します。Rune のアップグレードは次のように行います。

```sh
brew upgrade corvidlabs/tap/rune
```

ソースのクローンは Rune 自体を開発する場合のみ行ってください。

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

あるいは [fledge](https://github.com/CorvidLabs/fledge) のプラグインとしても利用できます。

```sh
fledge plugins install CorvidLabs/rune
fledge rune run --json -- git status
```

## 利用可能な機能の調べ方

```sh
rune --help              # or -h, or `rune help`
rune run --help          # or `rune help run`, or `rune run -h`
```

コマンドのヘルプには、グローバルなフラグと並んで、そのコマンド固有のフラグ（`rune run` なら
`--timeout=SECONDS`、`rune watch` なら `--log=PATH`）が一覧表示されます。エージェントモードでも
構造化されているため、人間向けのレンダリングを解析しなくても機能を調べられます。

```sh
$ rune run --help --json | jq -c '.data.flags'
[{"flag":"--timeout=SECONDS","description":"Kill the wrapped command after N seconds (default 30). Before `--` only."},{"flag":"--max-output=BYTES","description":"Bound clean_output/raw_output to BYTES each, keeping head+tail and marking the join with a `[rune] ==== N bytes omitted by --max-output ====` line. Mutually exclusive with --tail. Before `--` only."},{"flag":"--tail=N","description":"Keep only the last N lines of clean_output/raw_output. Mutually exclusive with --max-output. Before `--` only."},{"flag":"--separate-streams","description":"Adds clean_stdout/clean_stderr (stderr on a pipe, not the pty) alongside the merged view. Before `--` only."}]
```

ヘルプ用のフラグも他のすべてと同じセパレータの規則（後述）に従います。
`rune run -- mytool --help` とすると `--help` は `mytool` に渡されます。

## 3 つの出力モード

`rune` は呼び出され方に応じてレンダリングモードを自動的に選択します。フラグを指定して明示的に
固定することもできます。どのモードでも実行されるコマンドのロジックはまったく同じで、異なるのは
出力形式だけです。

### 1. 人間向け TTY モード（デフォルト、対話型ターミナル）

stdout が実際のターミナルで、`--json`／`--ndjson` フラグが指定されていない場合、`rune` は
色付きの人間向けフォーマットで出力します。

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

### 2. エージェント向け JSON モード（`--json`、またはパイプの自動検出）

`--json` を明示的に渡すか、単に `rune` の出力をパイプまたはリダイレクトしてください。stdout が
TTY でない場合、フラグなしでレンダリングが自動的に JSON に切り替わります。

```sh
$ ruby bin/rune run --json -- echo "hello agent"
{"status":"ok","data":{"command":"echo hello\\ agent","exit_code":0,"clean_output":"hello agent\n","raw_output":"hello agent\r\n","prompt_detected":false,"duration_ms":5.27}}
```

```sh
$ ruby bin/rune version | cat
{"status":"ok","data":{"name":"rune","version":"0.7.0","ruby":"4.0.6","ruby_platform":"arm64-darwin25","fledge":true,"specsync":true}}
```

> **`exit_code` はラップされたプロセスの終了ステータスであり、作業の成否を示すものではありません。**
> これが答えるのは「プロセスが終了したか、どのように終了したか」で、エージェント CLI ではほぼ
> 常に `0` になります。出力内容が誤っていた実行でも同様です。ある呼び出し側では `rune run` の
> ディスパッチが 8 回連続で `0` を返しましたが、そのうち複数は後で訂正が必要な結論を出していました。
> *作業*が成功したかどうかを知りたい場合は、このフィールドではなく出力から判断する必要があります。
> 知っておくべき例外は `124` です。これは rune が `--timeout` によってプロセスを強制終了したことを
> 意味します。

すべての JSON レスポンスは同じエンベロープ構造を持ちます。`{"status": "ok"|"error", "data": {...}}`
（失敗時は `{"status": "error", "error": "..."}`）です。

Rune は成功時・失敗時のどちらでも最終的なエンベロープを stdout に書き出します。これにより
エージェントは解析可能な結果チャネルを 1 つだけ見ればよくなりますが、同時に、人間が stdout を
リダイレクトすると Rune レベルのエラーメッセージも一緒にリダイレクトされることになります。
stderr は運用上の告知や、構造化された stdout を壊してはならない `rune watch` のライブ
パススルーのために予約されています。

グローバルな出力フラグは最初の `--` セパレータより前でのみ認識されます。それ以降のトークンは
ラップされたコマンドのものとしてそのまま保持されるため、`rune run -- tool --json` は `--json` を
`tool` に渡します。

rune 自身のフラグが置かれるべき位置に、rune の知らない `--flag` があると、黙って後続へ渡すのでは
なくエラーになります。以前のバージョンでは、`rune run --tiemout=5 -- echo hi` はスペルミスした
フラグを*実行*しようとして、`exit_code: 127` で `status: ok` を返していました。チェック対象は
ラップされるコマンドより前のトークンだけなので、`rune run cargo clippy --tests` や
`rune run -- mytool --tiemout=5` は影響を受けません。コマンド名が現れた以降の `--flag` はすべて
そのコマンドのものとみなされます。

### 3. エージェント向け NDJSON エンベロープモード（`--ndjson`）

`--ndjson` は、`--json` が使う素の `{"status": ...}` 形式の代わりに、同じ結果を
`{"event": "result"|"error", ...}` というエンベロープで包みます。これは、一部のエージェント
ハーネスが `rune run` を含むすべてのコマンドについて一律に期待する形式です。

```sh
$ ruby bin/rune run --ndjson -- echo "hello stream"
{"event":"result","status":"ok","data":{"command":"echo hello\\ stream","exit_code":0,"clean_output":"hello stream\n","raw_output":"hello stream\r\n","prompt_detected":false,"duration_ms":11.45}}
```

`rune run` では、これは依然としてコマンド終了時に一度だけ出力される 1 行です。`PTYRunner` は
実行全体をバッファして単一の `Result` を返すので、ここでの `--ndjson` はエンベロープの選択で
あって、逐次ストリーミングではありません。長時間実行されるコマンドや対話型コマンドの進行に
応じた実際のライブイベントストリームについては、後述の
[`rune watch`](#rune-watch-でセッションをライブ観察する) を参照してください。こちらは出力
チャンクが発生するたびに 1 行の NDJSON を出力します。

## `rune run` でコマンドを実行する

`rune run` は任意の CLI コマンドや対話型 TUI を実際の PTY 内で起動し、ANSI エスケープ
シーケンスを除去し、ページャを無効化し、実行時間を計測します。

```sh
rune run -- git status
rune run --json -- npm test
rune run --ndjson -- fledge lanes run check
```

### タイムアウトの上書き

すべての `rune run` 呼び出しにはデフォルトで 30 秒のタイムアウトがあります。上書きするには
`--timeout=SECONDS` を使います。ラップされるコマンドのフラグと取り違えられないよう、
`--` セパレータの*前*に置いてください。

```sh
$ ruby bin/rune run --json --timeout=1 -- sleep 3
{"status":"ok","data":{"command":"sleep 3","exit_code":124,"clean_output":"\n[rune] Execution timed out after 1 seconds","raw_output":"\n[rune] Execution timed out after 1 seconds","prompt_detected":false,"duration_ms":1005.32}}
```

タイムアウトしたコマンドは終了コード `124` を返し、捕捉された出力の末尾に
`[rune] Execution timed out after N seconds` というメッセージが付きます。これは例外ではなく、
通常の `Result` です。

**強制終了の前に捕捉された出力は必ず返されます。** そのため、出力してからハングした子プロセス
でも、出力した内容を確認できます。出力が*空*の場合は、子プロセスが本当に何も出力していない
ということであり、rune はその旨を最もよくある原因とあわせて伝えます。

**`rune run` は自身の stdin を子プロセスに転送しません。** tty は人間のものであり、それを
引き受けるのは `rune watch` の役目です。また、パイプを転送すると呼び出し側自身の入力が pty
経由でエコーされ、`clean_output` に混ざってしまいます。そのため `echo hi | rune run -- cat` は
タイムアウトします。`cat` が決して届かない入力を待ち続けるからです。代わりに、シェルが pty 内で
リダイレクトを実行するように、コマンドの内側に書いてください。

```sh
$ rune run -- sh -c 'claude -p --output-format text < prompt.md'
```

これはうまく動きます。複数段落のプロンプトを 1 つの引数として渡すのも同様で、改行は argv 経由で
そのまま残ります。なお、応答の `command` フィールドは人間向けにシェルエスケープされた*表示用*の
再構成であり、子プロセスが実際に受け取ったものではありません。このフィールドを根拠にクォートの
扱いを判断しないでください。

### 出力の制限とストリームの分離

以下の 3 つのフラグは、いずれも `--` セパレータの前に置き、いずれも結果の*形*を変えます。

- **`--max-output=BYTES`** は `clean_output` と `raw_output` をそれぞれ BYTES バイト以内に
  制限し、先頭部分と末尾部分を残して、`omitted_bytes` 付きの `truncated: true` を追加します。
  「それぞれ」からは 2 つのことが帰結します。1 つは、各フィールドが*個別に*制限されるため、
  このフラグの下では両者が実行の異なる区間を表し、`clean_output` は `strip_ansi(raw_output)`
  ではなくなること。`omitted_bytes` は `clean_output` 側のカウントであり、`raw_output` は別の
  値を持つ独自のマーカーを含みます。もう 1 つは、`omitted_bytes` は元データへのオフセットで
  測られるため、ASCII では正確に一致しますが、マルチバイト文字列では切断位置が文字の途中に
  なることがあり、数バイトずれることです。先頭と末尾の 2 つの部分は単純に接合されるのではなく
  `[rune] ==== N bytes omitted by --max-output ====` という行でつながれるため、返されるテキストが
  コマンドの出力であるかのように読めることはありません。この行がなければ、201 バイトの
  トランスクリプトを `--max-output=200` で処理した場合に、`chsh -s /bin/zsh` を
  `chsh -s bin/zsh` に変えてしまう 1 バイトがちょうど欠落していました。このマーカーはコマンドの
  出力ではなく rune による注釈なので、BYTES の計上対象にはならず、応答は予算をわずかに超える
  ことがあります。
- **`--tail=N`** は末尾 N 行のみを残し、`omitted_lines` 付きの `truncated: true` を追加します。
  `--max-output` とは相互排他で、両方を渡すと黙って優先順位が適用されるのではなくエラーに
  なります。
- **`--separate-streams`** はマージ済みの `clean_output` を置き換えるのではなく、それに加えて
  `clean_stdout` と `clean_stderr` を追加します。

`--separate-streams` には実際のコストがあるため、デフォルトではなくオプトインになっています。
pty のストリームは 1 本なので、分離するには stderr に独自のパイプを与える必要があります。
すると子プロセスからは、もはや両方を受け持つ単一の制御端末が見えなくなり、`isatty(2)` を
チェックするプログラムはエラー出力がリダイレクトされているかのように振る舞います。多くの
CLI では、それはカラー表示をやめるか、完全に非対話モードに切り替わることを意味します。
子プロセスに端末上で動いていると思わせることよりも、ストリームの分離が必要な場合に使って
ください。

## `rune watch` でセッションをライブ観察する

`rune run` はコマンドの出力全体をバッファし、コマンドが終了してから初めてそれを返します。
スクリプト化やキャプチャには最適ですが、実際にキーボードの前に座って対話型プログラムを操作し、
その間セッションを別の何かに観察させたい場合には向きません。そのために作られたのが
`rune watch` です。ターミナルを raw モードにし、打ち込んだすべてのキーストロークを（行単位
ではなく、矢印キーのような生のエスケープシーケンスを含めて）リアルタイムで子プロセスに転送し、
子プロセスの出力を発生したその場で（最後ではなく）画面に流し、同時にすべてのチャンクを NDJSON
イベントとしてログに記録します。これにより、人間がセッションを操作している間、AI エージェントが
それをリアルタイムで tail できます。

```sh
# A small interactive demo program ships with rune specifically to try this against:
rune watch -- ruby examples/humans/demo_tui.rb
```

イベントログのデフォルトは衝突に安全で所有者のみがアクセスできる（`0600`）一時ファイルで、
stderr ではありません。ライブパススルーと同じターミナルに NDJSON イベントを混ぜるのが当初の
設計でしたが、実際に使ってみるとそれが誤ったデフォルトだとすぐに分かりました（JSON が混ざり込む
せいでセッションが読めなくなったのです）。パスは開始時に一度だけ告知されます。

```
[rune watch] live event log: /tmp/rune-watch-20260728-12345-abcd.ndjson
```

別のペインからそのパスを `tail -f` する（あるいはエージェントに tail させる）と、自分の
ターミナルをクリーンに保ったままセッションをライブ観察できます。特定の場所に出力したい場合は
`--log=PATH` を使います。

```sh
rune watch --log=/tmp/session.ndjson -- ruby examples/humans/demo_tui.rb
```

ログの各行は JSON オブジェクトです。まず `{"event":"start","command":"...","pid":...}`、
次にストリームされるチャンクごとに `{"event":"output","bytes":N,"text":"..."}`、
最後に子プロセスの終了時に `{"event":"exit","exit_code":N}` となります。

### エージェントモードでの `rune watch`

`rune watch` は他のすべてのコマンドと同じ出力モードの規則に従います。`--json` や `--ndjson`
の指定時、あるいは stdout がターミナルでない場合は常に、ライブパススルーは **stderr** に移り、
stdout には結果のエンベロープだけが載ります。そのため、ラップするプログラムは stdout を直接
解析でき、キーボードの前の人間は引き続き自分のセッションを見ることができます。

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

JSON を別の場所でキャプチャしながら自分でもセッションを見続けたい場合は、`2>/dev/null` を
外してください。

`rune watch` には実際のターミナルが必要です（stdin が TTY でない場合は実行を拒否します。
意味のある非対話モードが存在しないためです）。また、`rune run` 自身の PTY 入れ子環境では
動作しないため、このガイドの他の部分のようにパイプ経由の例で実演することはできません。
`examples/humans/demo_tui.rb` のトップレベルメニューは、数字を打って Enter を押す方式ではなく、
本物の矢印キーセレクタ（↑/↓ + Enter、終了は `q`）になっています。これは、純粋に行バッファの
メニューでは決して触れることのない、生の 1 バイト入力とエスケープシーケンスの転送を実際に
試すためのものです。`examples/humans/demo_tui.rb` 自身のヘッダコメントにコピー＆ペースト可能な
コマンドがあり、`spec/rune/pty_watcher_spec.rb` には基盤となる転送・ログ機構のユニットテストが
示されています。矢印キーメニュー自体をエンドツーエンドで操作するテストも含まれます（偽の
ターミナルオブジェクトと `IO.pipe` の組み合わせで、実際の制御端末なしに本物の対話型子プロセス
を動かしています）。


### watch の制限

独立した 2 つの制限があり、どちらも `--` セパレータの前に置き、どちらもデフォルトでは無効です。

- **`--timeout=SECONDS`** は、どれだけ活発に出力があっても、実時間で N 秒後にセッションを
  強制終了します。
- **`--idle-timeout=SECONDS`** は、**出力も入力もない**状態が N 秒続くと強制終了します。
  長時間のビルドはアイドルではないので、「このエージェントは何もしなくなった」という場合に
  使うべきものはこちらです。

どちらの場合も終了コードは `124` で、`timed_out: true` と、発動した方を示す `"timeout"` または
`"idle_timeout"` の `timeout_kind` が付きます。

## 構造化テキストの解析

`Rune::Parsers::TableParser` と `Rune::Parsers::KeyValueParser` は、非構造化のターミナル出力を
Ruby のハッシュに変換します。

```ruby
require 'rune'

Rune::Parsers::TableParser.parse(<<~TABLE)
  NAME           STATUS   VERSION
  fledge-plugin  active   1.0.0
TABLE
# => [{ name: 'fledge-plugin', status: 'active', version: '1.0.0' }]
```

`TableParser.parse` は `format:` キーワードを受け取ります（デフォルトは `:auto`。`:pipe` や
`:space` を指定すれば解析モードを強制できます）。見慣れない出力に対して `:auto` に頼る前に、
ヒューリスティクスの既知の制限について
[`specs/parsers/parsers.spec.md`](../specs/parsers/parsers.spec.md) を参照してください。

## 次のステップ

- [`examples/smoke_test.rb`](../examples/smoke_test.rb) — `ruby examples/smoke_test.rb` または
  `fledge run smoke-test` で実行します。実際の挙動をアサーションベースでたどる単体のツアーで
  （bundler も rspec も不要）、出力モード、`--timeout` の検証、パーサ、`Script`、シグナル転送、
  プロンプト検出をカバーします。
- [`examples/humans/demo_tui.rb`](../examples/humans/demo_tui.rb) — 上の `rune watch` の節全体で
  使われている対話型デモです。[`examples/agents/pty_runner_example.rb`](../examples/agents/pty_runner_example.rb)、
  [`table_parser_example.rb`](../examples/agents/table_parser_example.rb)、
  [`script_automation_example.rb`](../examples/agents/script_automation_example.rb) は、より小さな
  単一概念のスクリプトで、`require_relative '../lib/rune'` 以外のセットアップなしにそれぞれ直接
  実行できます（`ruby examples/agents/<name>.rb`）。
- [PTY アーキテクチャガイド](pty_architecture.md) — PTY ランナー、ストリームの読み取り、
  プロンプト検出、`rune watch` のライブパススルーが内部でどう動作するかを解説しています。
- [`specs/`](../specs/) — `cli`、`parsers`、`pty_runner`、`session`、`watch` の機械検証される
  モジュール契約（`spec-sync`）です。
- [`AGENTS.md`](../AGENTS.md) — 新しいコマンドの追加や trust ツールチェーンとの付き合い方に
  関する規約です。
