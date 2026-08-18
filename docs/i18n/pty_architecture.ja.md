> この文書は `docs/pty_architecture.md` の日本語訳です。内容に相違がある場合は、英語版を正文とします。

# Rune 疑似端末（PTY）と TTY アーキテクチャ

> **開発者と AI エージェント向けガイド**
> *Ruby が疑似端末、対話ストリーム、プロンプト自動化をどのように管理しているかを、`rune` を題材に理解する。*

---

## 1. 概要：疑似端末（PTY）とは何か

プログラムが通常のサブシェルやサブプロセスのパイプ（例：`IO.pipe` や通常のサブシェル実行）で動作する場合、OS は `stdin`、`stdout`、`stderr` に対して通常のパイプを割り当てます。多くの CLI プログラム（`git`、`docker`、`python`、`zsh`、`sudo` など）は、`stdout` が端末かどうかを（`isatty()` を使って）検出し、端末でない場合にはカラー表示、プロンプトの整形、行バッファリングを無効化します。

**疑似端末（PTY）** とは、カーネルレベルで用意されるマスターとスレーブの仮想端末デバイスのペアです：
- **スレーブ PTY**：子プロセスの制御端末（`tty`）として子プロセスに割り当てられます。子プロセスは、自分が本物の端末（iTerm2 や xterm など）の中で動作していると認識します。
- **マスター PTY**：`rune`（`PTYRunner`）が所有します。`rune` は子プロセスの出力を読み取り、キーボード入力をマスターのディスクリプタへ直接書き込みます。

```
+------------------+         Master PTY          Slave PTY         +-------------------+
|  Rune PTYRunner  | <=======================> (Virtual Terminal) <==> |  Child Process    |
| (Agent / Human)  |    (reader / writer IO)                       | (bash, git, etc.) |
+------------------+                                               +-------------------+
```

---

## 2. Ruby における PTY 実行（`PTY.spawn`）

Ruby の標準ライブラリには `require 'pty'` が用意されています。`rune` は `lib/rune/pty_runner.rb` の内部で `PTY.spawn` を使用しています：

```ruby
PTY.spawn(env, command) do |reader, writer, pid|
  # reader: IO object to read output from slave PTY
  # writer: IO object to write stdin into slave PTY
  # pid:    Process ID of child process
end
```

### ノンブロッキングなチャンク読み取り（`readpartial`）

通常の行読み取り（`reader.each_line`）は、改行（`\n`）を受け取るまでブロックします。**対話型プロンプト**（`Password: `、`Select option [y/N]`、`user@host:~$ ` など）は**改行で終わりません**。`each_line` で読み取ると、親プロセスは `\n` を待ってブロックし、その間に子プロセスはユーザー入力を待ち続けるため、**デッドロック**が発生します。

デッドロックを回避するため、`rune` は `readpartial(4096)` を使ってチャンク単位で読み取ります：

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

子プロセスが終了するとスレーブ PTY が閉じられ、`readpartial` は `Errno::EIO` または `EOFError` を発生させます。`rune` はこれを捕捉してクリーンに終了します。

---

## 3. ANSI サニタイズと二重出力（人間向けとエージェント向け）

`rune` は生の ANSI 端末エスケープシーケンス（カラー、カーソル移動、画面クリア）をキャプチャします。

- **人間向け（TTY モード）**：生出力は `Renderer.render_tty` で整形され、フルカラーかつ対話的な書式で表示されます。
- **AI エージェント向け（JSON モード）**：出力は `Parsers::TextSanitizer.strip_ansi(raw_output)` を通して処理され、ANSI コードが除去されます。これは LLM のトークン効率を高めるためのクリーンなテキストを返すためです。ただしこの関係が無条件に成り立つのは `--max-output` を付けない場合だけです。このフラグを付けると、2つのフィールドは同じバジェットに対してそれぞれ独立に切り詰められるため、実行の異なる時間窓を表すことになり、`clean_output` は `strip_ansi(raw_output)` とは一致しなくなります：

```ruby
# Strips SGR ANSI color codes, cursor escape codes, and terminal controls
ANSI_REGEX = /\e\[[0-9;]*[a-zA-Z]/
clean_output = text.gsub(ANSI_REGEX, '')
```

---

## 4. プロンプト検出ロジック（`Parsers::PromptDetector`）

コマンドが完了したのか、それとも対話型プロンプトで待機しているのかを判別するために、`Parsers::PromptDetector` はストリーミングされる行の断片を解析します：

### サポートされているプロンプトのシグネチャ：
- シェルの PS1 プロンプト：`user@host:~$ `、`bash-5.2# `、`➜  rune git:(main)`、`❯ `
- メニューと対話的な選択肢：`Select:`、`[y/N]`、`(y/n)?`、`Password: `

かつてこの一覧に記載されていた2つのシグネチャは、現在は検出**されません**。追加ではなく削除という判断が取られました。検出器の保守的な設計は意図的なものだからです。1つは `Select an option: `（疑問文のパターンはアンカーされているため、`Select:` には一致しますが、コロンで終わる通常の文には一致しません）、もう1つは `(venv) λ `（`λ` はプロンプト記号のクラスに含まれず、そのクラスは `➜ ❯ ›` です）です。

### 誤検出の排除：
`PromptDetector` は、コードの比較式（`if x > 5`）やシェルの変数代入（`export PATH=$PATH`）を含む行を無視します。`> quote` のような Markdown の引用行も拒否されますが、これは除外ルールによるものではなく、そもそもどの肯定パターンにも一致しないためです。引用行の除外ルールが発動するのは、山括弧で囲まれたテキストも含む行だけです。

---

## 5. スクリプト自動化エンジン（`Rune::Script`）

`rune` では、複数ステップにわたる PTY プログラムを自動化するために、対話型の DSL スクリプトを定義できます：

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

スクリプトエンジンは、各ステップをノンブロッキングの単一パスで処理するため、`send_keys` は後続のチャンクを待たずに `writer` へ即座に書き込まれます。

---

## 6. ライブな対話型パススルー（`PTYWatcher` / `rune watch`）

`PTYRunner` はコマンドの出力全体をバッファリングし、終了時に一度だけ結果を返します。これはスクリプト実行やキャプチャには正しい設計ですが、実際にキーボードの前に座って、セッションを別の何かが観察している間に対話型プログラムを操作する、という用途には合いません。`PTYWatcher`（`lib/rune/pty_watcher.rb`）は、そのライブで双方向のケースのための独立したクラスであり、`PTYRunner` に後から付け足されたモードではありません。実行モデル（raw 端末モード、バックグラウンドの入力転送スレッド）は `PTYRunner` とは十分に異なるためそこに属さず、`PTYRunner` の「実行し、キャプチャし、一度だけ返す」という契約はそのまま固定されています。

### raw 端末モード（`io/console`）

矢印キーなどの単一バイト／エスケープシーケンスの入力を子プロセスへそもそも届くようにするには、*親*プロセス自身の制御端末が cooked モードを抜ける必要があります。cooked モードでは、カーネルが入力を行単位でバッファリングし、改行が来るまでキー入力をローカルにエコーします。`io/console`（`pty` が暗黙に読み込むのではなく、明示的に require されます）は `IO#raw` を提供し、これを `PTYWatcher#with_raw_input` が転送セッション全体を包む形で適用します：

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

`entered` フラグが重要です。raw モードが実際に有効化された後は、セッションの深部から発生した無関係な例外（例えば出力先の破損）は、通常どおり伝播させる必要があります。「raw モードがサポートされていない」と見なして、すでに起動済みのセッション全体を黙って二度目に実行し直すようなことはしてはいけません。

### 双方向転送

`PTYRunner` の単一の読み取りループとは異なり、`PTYWatcher` は2つの処理を並行して実行します。バックグラウンドスレッドが、人間の実際のキーストロークを入力されたタイミングで子プロセスの PTY へ転送し（`forward_input`）、一方でメインスレッドは子プロセスの出力をポーリングして即座に画面へストリーミングします（`pump_output`）。最後に一度だけ返されるバッファに出力を溜め込むようなことはしません。

どちらの経路も `UTF8StreamDecoder` でデコードされます。これは `readpartial` 呼び出しの間で、不完全な UTF-8 シーケンスの末尾部分を保持します。そのため、カーネルが有効なマルチバイト文字を複数のチャンクに分割してきても、その文字は正しく保たれます。本当に無効なシーケンスや、最後まで不完全なままのシーケンスだけが、置換文字に変換されます。

また `PTYWatcher` は、制御端末の現在の行数・列数を子プロセスの PTY に反映します。出力のポーリングループの中で再確認するため、リサイズされた端末のサイズは、シグナルトラップ内で危険な処理を行うことなく子プロセスへ届きます。

```
+------------------+   keystrokes    +------------------+   output    +-------------------+
|  Human terminal  | --------------> |  PTYWatcher       | ----------> |  Real terminal      |
|  (raw mode)      |  (bg thread)    |  (master PTY)     |  (live)     |  screen + NDJSON log |
+------------------+                 +------------------+             +-------------------+
```

### NDJSON イベントログ

画面に届くすべてのチャンクは、NDJSON イベントとしてログファイルにも書き込まれます（デフォルトでは通知済みの衝突安全な `0600` の一時ファイル、または `--log=PATH` で指定）。これにより、AI エージェントはセッションをライブで `tail -f` でき、JSON のノイズが人間自身の端末に混入することもありません：

```json
{"event":"start","command":"...","pid":12345}
{"event":"output","bytes":42,"text":"..."}
{"event":"exit","exit_code":0}
```

あえてデフォルトでは stderr にしていません。stderr はライブのパススルーと人間の端末を共有するため、実際の使用で、対話セッションに JSON を混在させると直ちに読めなくなることが確認されました。

出力先が `EPIPE` で閉じられた場合、`PTYWatcher` は構造化された失敗結果を返す前に子プロセスを kill して回収します。これにより、デタッチされた対話プロセスが watcher の終了後も生き残ることを防ぎます。

---

## 7. エラーハンドリングと終了コード

`PTYRunner` と `PTYWatcher` はどちらも、さまざまなエッジケースにわたって Unix の終了コードを標準化しています：

| 状況 | 終了コード | 処理 |
| :--- | :--- | :--- |
| 正常終了 | `status.exitstatus` | クリーンに完了 |
| コマンドが見つからない | `127` | `Errno::ENOENT` を捕捉 |
| 権限エラー | `126` | `Errno::EACCES` を捕捉 |
| 実行タイムアウト（`PTYRunner` のみ） | `124` | `Timeout::Error` を捕捉した後、子プロセスへ `SIGKILL` を送って回収 — `Timeout.timeout` が中断できるのは Ruby 自身の制御フローだけであり、起動済みの OS プロセスは中断できないため |
| 子プロセスの強制終了（シグナル） | `128 + sig` | `SIGKILL`（137）や `SIGTERM`（143）などのシグナル |

---

## 開発者向けまとめ

`rune` は以下を組み合わせています：
1. 本物の端末エミュレーションのための `PTY.spawn`
2. デッドロックのないストリーム読み取りのための `readpartial`
3. 境界安全でクリーンなエージェント向け JSON のための `UTF8StreamDecoder` と `TextSanitizer`
4. 賢い対話性チェックのための `PromptDetector`
5. ステップごとの自動化された入力のための `Script` DSL
6. エージェントが tail できる NDJSON ログ付きの、ライブで双方向な人間主導セッションのための `PTYWatcher` + `io/console` raw モード
