> このドキュメントは [README.md](../../README.md) の日本語訳です。英語の原文が正本です。
> 両者に矛盾がある場合は英語版に従ってください。

# rune

[![CI](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml/badge.svg)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-3.0%20%E2%80%93%204.0-CC342D?logo=ruby&logoColor=white)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)

**人間と AI エージェントの両方を第一級市民として**扱うことを念頭に一から設計された
Ruby CLI ツールおよびライブラリ。

`rune` は、あらゆる CLI コマンドや対話型 TUI アプリケーションに対応した、ユニバーサルな
疑似端末（PTY）ランナー兼構造化データブリッジとして機能します。

すべてのコマンドは、人間向けに整形・着色されたターミナル出力と、AI エージェント向けの
構造化 JSON を生成します。さらに `rune watch` は、人間がセッションを操作している間、
ライブの NDJSON イベントストリームを書き出します。同じツール、同じコマンドで、二つの
インターフェースを提供します。

`rune session` はさらに一歩進んでいます。`claude`、`grok`、`codex` といったエージェント
CLI を複数の呼び出しをまたいで開いたまま維持するため、あるエージェントが別のエージェント
と対話的にやり取りでき、人間が同じセッションにアタッチして引き継ぐこともできます。

📖 はじめての方は、まず **[入門ガイド](docs/getting_started.md)** からどうぞ。

---

## 機能

1. **二重出力（人間向け TTY / エージェント向け JSON & NDJSON）**
   - ターミナルモード: 整形・着色された出力（`rune version`）
   - エージェント JSON モード: `--json` またはパイプの自動検出（`rune version | cat`）
   - エージェント NDJSON モード: 一貫した結果エンベロープを得るには `--ndjson`
     （`rune version --ndjson`）
2. **ユニバーサル PTY プロセスランナー（`rune run`）**
   - あらゆる CLI ツールや TUI を疑似端末セッション内で起動します
   - ANSI エスケープコード、カーソル移動、制御シーケンスを自動的に除去します
   - ターミナルページャー（`PAGER=cat`）を無効化し、クエリが即座に返るようにします
   - プロセスの実行時間をミリ秒単位で計測し、対話型プロンプトを検出します
3. **構造化自動パーサー（`Rune::Parsers`）**
   - `TableParser`: 空白またはパイプ区切りのターミナル表をハッシュの配列に変換します
   - `KeyValueParser`: キーバリュー出力（`key: val`）を型付きハッシュに変換します
   - `TextSanitizer`: 改行コードを正規化し、ANSI エスケープコードを除去します
4. **対話型スクリプト DSL（`Rune::Script`）**
   - 対話型ターミナルプロンプトや TUI メニューを操作するための、ステップバイステップの
     TUI スクリプト自動化 DSL
5. **ライブ対話パススルー（`rune watch`）**
   - ターミナルを raw モードにし、キーストロークをバイト単位でそのまま
     子プロセスへライブ転送します
   - 子プロセスの出力を発生と同時に画面へストリーミングします（`rune run` とは異なり、
     バッファして最後にまとめて返します）
   - 同時に、すべてのチャンクを NDJSON イベントとして一時ファイルに記録します（パスは
     一度だけ通知、または `--log=PATH` で指定）されるため、人間が操作している間、AI
     エージェントがセッションをライブで tail できます
6. **永続的な名前付きセッション（`rune session`）**
   - REPL 型の子プロセス — `claude`、`grok`、`codex`、シェル — を複数の `rune`
     呼び出しを*またいで*開いたままにします。これは `run`（バッファして一度だけ返す）にも
     `watch`（子プロセスと共に終了する）にもできないことです
   - **Send-and-settle（送信と待機）**: 入力を書き込み、子プロセスが静かになるのを待ち、
     その送信が生成した出力だけを正確に受け取ります。非同期 TTY を同期的な
     リクエスト/レスポンス呼び出しへと変えます
   - `--screen` は生のバイトストリームではなく*レンダリング済みのターミナル*を返します。
     フルスクリーンのエージェントは回答を自身の再描画と混ぜて出力するため重要です。
     実測したあるトランスクリプトでは、361KB の再描画トラフィックが
     1.1KB の画面になりました
   - `attach` はライブセッションを人間のターミナルに引き渡し、**Ctrl-]** で
     実行中のままセッションを返却できます
   - セッションは名前付きで、プロジェクト単位にスコープされ、アーカイブ可能です。
     トランスクリプトはディスク上でもメモリ上でも上限が設けられているため、
     一日中動かし続けたセッションが際限なく肥大化することはありません

---

## インストール

修飾なしの `rune` という gem 名は、公開の RubyGems.org レジストリですでに無関係な
パッケージに取得されているため、そこで `gem install rune` を実行すると誤ったものが
インストールされます。CorvidLabs の Homebrew tap から、メンテナンスされチェックサムで
固定された formula をインストールしてください:

```sh
brew install corvidlabs/tap/rune
rune version --json
```

後のリリースへのアップグレードも同じチャンネル経由で行います:

```sh
brew upgrade corvidlabs/tap/rune
```

ソースから開発する場合:

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

---

## 使用例

### 0. CLI を調べる

```sh
rune --help              # every command, plus the global flags
rune run --help          # one command's usage and its own flags
rune help watch          # same thing, spelled the other way
```

ヘルプも構造化されているため、エージェントはテキストをスクレイピングせずに機能全体を把握できます:

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

> **ラップするコマンドの前に `--` を置いてください。** すべての rune フラグ — `--json`、
> `--ndjson`、`--help`、`--timeout`、`--log` — は最初の `--` の*前*でのみ認識されます。
> これにより、`rune run -- gh pr list --json number` は `--json` を自分で消費せず `gh` に
> 渡すことができます。セパレーターがないと、rune がフラグを自分のものとして取り込み、
> ラップされたコマンドはそれを黙って受け取れません。

### 1. 任意の CLI コマンドをエージェント JSON モードで実行する
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

### 2. NDJSON 結果エンベロープ
```sh
rune run --ndjson -- fledge lanes run check
```
```json
{"event":"result","status":"ok","data":{"command":"fledge lanes run check","exit_code":0,"clean_output":"...","duration_ms":1652.8}}
```

`rune run --ndjson` はコマンド終了時にこの単一のエンベロープを出力します。出力イベントの
ライブストリームが必要な場合は `rune watch` を使ってください。

### 3. 表形式の CLI 出力をハッシュに変換する
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

### 4. 対話型 TTY / TUI アプリケーションを操作する
```ruby
require 'rune'

# Harness an interactive TUI program with input keystrokes
runner = Rune::PTYRunner.new("fledge plugins search --interactive", input: "\x03")
result = runner.run
# => Result with exit_code 130, clean_output, duration_ms
```

### 5. セッションをライブで監視する（人間が操作し、エージェントが追跡する）
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

エージェントモード — `--json`、`--ndjson`、または stdout がターミナルでないすべての場合 —
では、ライブパススルーは **stderr** に移り、stdout には結果エンベロープだけが流れます。
人間はライブ表示をそのまま使え、呼び出し側のプログラムはクリーンな JSON を受け取れます:

```sh
rune watch --json -- ruby examples/humans/demo_tui.rb 2>/dev/null | jq .data.log_path
```

### 6. あるエージェント CLI を別のエージェントから操作する（`rune session`）

`run` はバッファして一度だけ返し、`watch` はターミナルの前に人間が必要で、子プロセスと
共に終了します。どちらもエージェントの REPL を呼び出しをまたいで開いたままには
できません。`session` ならできます:

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

**生の出力ではなく `--screen` を使う理由。** フルスクリーンのエージェントは絶えず
再描画するため、バイトストリームにはすべての再描画の全フレームが含まれ、回答はそれらの
間に分断されています。grok に対する実測では、361KB のトランスクリプトが 1.1KB の画面に
レンダリングされ、エージェントが明確に表示していた回答は、バイトストリームでは
3 ターン中 3 ターンとも欠落し、レンダリングされた画面では 3 ターン中 3 ターンとも
存在していました。内容でマッチングするなら、`screen` に対してマッチしてください。

**自分で操作を引き継ぎ**、何も止めずにセッションを返却できます:

```sh
rune session attach --name reviewer   # Ctrl-] detaches; the session keeps running
```

セッションはそれを囲む git ワーキングツリーにスコープされるため、二つのチェックアウトの
`reviewer` は二つの別セッションです。これは意図的なものであり、同時に最もよくある驚きでも
あります — `list` に何も表示されない場合は、いまいるディレクトリと `RUNE_HOME` を確認して
ください:

```sh
rune session list --all-projects
```

**長いトランスクリプトから一つのものを見つける。** 駆動されるエージェントとの一日の作業は
379KB に達しました。目的のものが中間にある場合、`--since` も `--tail` も役に立ちません:

```sh
rune session read --name reviewer --grep 'THE BOARD' --context 2
```

📖 settle チューニングや既知の制限を含む完全なガイド:
**[docs/sessions.md](docs/sessions.md)**。

---

## CorvidLabs との連携

`rune` は [CorvidLabs トラストツールチェーン](https://github.com/CorvidLabs) と連携します:

- **[fledge](https://github.com/CorvidLabs/fledge)** — タスクランナー &
  プロジェクトライフサイクル。`rune` は `plugin.toml` で定義されたネイティブな `fledge`
  プラグインです。以下で直接インストールできます:
  ```sh
  fledge plugins install CorvidLabs/rune
  fledge rune run --json -- git status
  ```
- **[spec-sync](https://github.com/CorvidLabs/spec-sync)** — コントラクト強制（`specs/`）
- **[augur](https://github.com/CorvidLabs/augur)** — 変更リスクスコアリング

---

## アーキテクチャと内部実装

- 📖 **[入門ガイド](docs/getting_started.md)** — 出力モード、`rune run` の使い方、
  タイムアウト、実際のコマンド出力を使ったパーサー。
- 📖 **[永続セッションガイド](docs/sessions.md)** — `rune session`: 単一の呼び出しを超えて
  生き続ける名前付き PTY セッション、およびあるエージェント CLI を別のエージェントから
  操作するための send-and-settle。
- 📖 **[疑似 TTY（PTY）アーキテクチャガイド](docs/pty_architecture.md)** —
  疑似端末、ノンブロッキングなストリーム読み取り、ANSI サニタイズ、プロンプト検出、
  スクリプト実行、そして `rune watch` のライブ双方向パススルーが Ruby で内部的にどう
  動作するか。
- 📖 **[リリースガイド](docs/releasing.md)** — バージョン同期、検証、プロベナンス、
  タグ付け、パッケージ公開。

---

## 開発と検証

```sh
fledge run test         # Run RSpec test suite (405 examples, 87% line coverage)
fledge run lint         # Run RuboCop linter (0 offenses)
fledge lanes run verify # Full CI gate (lint + tests + strict 100%-coverage spec-sync)
fledge lanes run release # Verify, smoke-test, and build the release gem
fledge run smoke-test   # Runnable, assertion-based tour of real behavior (examples/smoke_test.rb)
COVERAGE=1 bundle exec rspec  # Same suite, plus an HTML coverage report at coverage/index.html
```

`examples/smoke_test.rb` は、実際の CLI バイナリに対して `rune run`、`--timeout`、
`TableParser`/`KeyValueParser`、`Script`、シグナル転送、プロンプト検出を実行する、
スタンドアロンで依存関係のないスクリプト（bundler/rspec 不要）です。合格/不合格の出力を
行い、失敗時には非ゼロで終了します。手軽な手動サニティチェックとして、または開発依存関係が
インストールされていないマシンで有用です。

---

## ライセンス

MIT
