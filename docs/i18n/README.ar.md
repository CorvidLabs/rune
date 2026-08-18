> هذه ترجمة عربية لملف README.md، والنسخة الإنجليزية الأصلية هي المرجع المعتمد.

# rune

[![CI](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml/badge.svg)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-3.0%20%E2%80%93%204.0-CC342D?logo=ruby&logoColor=white)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

أداة سطر أوامر ومكتبة بلغة Ruby، مصمَّمة من الأساس لتكون **من الدرجة الأولى للبشر ولوكلاء الذكاء الاصطناعي معًا**.

يعمل `rune` كمشغِّل طرفية زائفة (PTY) شامل وجسر بيانات مُهيكَلة لأي أمر سطر أوامر أو تطبيق TUI تفاعلي.

كل أمر يُنتج مخرجات طرفية منسَّقة وملوَّنة للبشر، و JSON مُهيكَلًا لوكلاء الذكاء الاصطناعي. ويكتب `rune watch` إضافةً إلى ذلك تدفّق أحداث NDJSON حيًّا بينما يقود الإنسان الجلسة. الأداة نفسها، والأوامر نفسها، وواجهة مزدوجة.

ويمضي `rune session` خطوة أبعد: فهو يُبقي واجهة سطر أوامر وكيل — `claude` أو `grok` أو `codex` — مفتوحة عبر استدعاءات منفصلة، فيستطيع وكيل أن يقود وكيلًا آخر حواريًّا، ويستطيع إنسان أن يتّصل بالجلسة نفسها ويتولّى زمامها.

📖 جديد هنا؟ ابدأ بـ **[دليل البدء](docs/getting_started.md)**.

---

## القدرات

1. **مخرجات مزدوجة (طرفية للبشر / JSON و NDJSON للوكلاء)**
   - وضع الطرفية: مخرجات منسَّقة وملوَّنة (`rune version`)
   - وضع JSON للوكيل: `--json` أو الاكتشاف التلقائي للأنبوب (`rune version | cat`)
   - وضع NDJSON للوكيل: `--ndjson` للحصول على غلاف نتيجة متّسق (`rune version --ndjson`)
2. **مشغِّل عمليات شامل عبر PTY (`rune run`)**
   - يُشغِّل أي أداة سطر أوامر أو TUI داخل جلسة طرفية زائفة
   - يزيل رموز ANSI الهاربة وحركات المؤشّر وتسلسلات التحكّم تلقائيًّا
   - يعطّل مُصفِّحات الطرفية (`PAGER=cat`) كي تعود الاستعلامات فورًا دون تعليق
   - يقيس مدّة تنفيذ العملية بالمللي ثانية، ويكتشف المُحِثّات التفاعلية
3. **مُحلِّلات تلقائية مُهيكَلة (`Rune::Parsers`)**
   - `TableParser`: يحلّل جداول الطرفية المفصولة بمسافات أو بشُرَط رأسية إلى مصفوفات من الـ hashes
   - `KeyValueParser`: يحلّل مخرجات المفتاح-القيمة (`key: val`) إلى hashes ذات أنواع
   - `TextSanitizer`: يوحّد نهايات الأسطر ويُنظّف رموز ANSI الهاربة
4. **لغة DSL للنصوص التفاعلية (`Rune::Script`)**
   - لغة DSL لأتمتة نصوص TUI خطوة بخطوة، لقيادة مُحِثّات الطرفية التفاعلية وقوائم TUI
5. **تمرير حيّ تفاعلي (`rune watch`)**
   - يضع طرفيتك في الوضع الخام ويمرّر ضغطات المفاتيح إلى العملية الابنة حيًّا، بايتًا ببايت
   - يبثّ مخرجات العملية الابنة إلى شاشتك فور حدوثها (بخلاف `rune run` الذي يخزّن كل شيء
     ويعيده في النهاية)
   - يسجّل في الوقت نفسه كل قطعة كحدث NDJSON في ملف مؤقّت (يُعلَن مساره مرّة واحدة، أو
     `--log=PATH`) كي يستطيع وكيل ذكاء اصطناعي متابعة الجلسة حيًّا بينما يقودها إنسان
6. **جلسات مُسمّاة دائمة (`rune session`)**
   - تُبقي عملية ابنة على هيئة REPL — `claude` أو `grok` أو `codex` أو صَدَفة — مفتوحة *عبر*
     استدعاءات `rune` منفصلة، وهو ما لا يستطيعه `run` (يخزّن ويعيد مرّة واحدة) ولا `watch`
     (يموت مع عمليته الابنة)
   - **الإرسال والانتظار حتى الهدوء**: تكتب المُدخَل، وتنتظر حتى تهدأ العملية الابنة، فتستعيد
     بالضبط المخرجات التي أنتجها ذلك الإرسال، محوِّلًا طرفية غير متزامنة إلى نداء طلب/استجابة متزامن
   - يعيد `--screen` *الطرفية المُصيَّرة* بدل تدفّق البايتات الخام، وهذا مهمّ لأن وكيلًا يعمل
     بملء الشاشة يُداخل جوابه مع إعادات رسمه — انتقل أحد النصوص المقيسة من 361KB من حركة
     إعادة الرسم إلى شاشة بحجم 1.1KB
   - يسلّم `attach` الجلسة الحيّة إلى طرفية إنسان، و**Ctrl-]** يعيدها، وهي ما تزال تعمل
   - الجلسات مُسمّاة، ومحصورة بنطاق المشروع، وقابلة للأرشفة؛ والنصوص المسجّلة محدودة الحجم على
     القرص وفي الذاكرة، فالجلسة المتروكة تعمل يومًا كاملًا لا تنمو بلا حدّ

---

## التثبيت

اسم الجيم المجرّد `rune` محجوز مسبقًا في سجلّ RubyGems.org العام لحزمة غير ذات صلة، لذا فإن
`gem install rune` هناك يثبّت الشيء الخطأ. ثبّت الصيغة المُصانة والمثبّتة بالمجموع الاختباري من
مستودع Homebrew الخاص بـ CorvidLabs:

```sh
brew install corvidlabs/tap/rune
rune version --json
```

ورقِّ الإصدارات اللاحقة عبر القناة نفسها:

```sh
brew upgrade corvidlabs/tap/rune
```

للتطوير من المصدر:

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

---

## أمثلة الاستخدام

### 0. اكتشاف واجهة سطر الأوامر

```sh
rune --help              # every command, plus the global flags
rune run --help          # one command's usage and its own flags
rune help watch          # same thing, spelled the other way
```

والمساعدة مُهيكَلة هي الأخرى، فيستطيع الوكيل اكتشاف السطح دون كشط النصوص:

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

> **استخدم `--` قبل الأمر المُغلَّف.** كل راية من رايات rune — `--json` و`--ndjson` و`--help`
> و`--timeout` و`--log` — لا يُتعرَّف عليها *إلا* قبل أول `--`. وهذا ما يجعل
> `rune run -- gh pr list --json number` يمرّر `--json` إلى `gh` بدل أن يستهلكها. ومن دون
> الفاصل، يأخذ rune الراية لنفسه، ولا يراها الأمر المُغلَّف أبدًا ودون أي إشعار.

### 1. تنفيذ أي أمر سطر أوامر في وضع JSON للوكيل
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

### 2. غلاف النتيجة بصيغة NDJSON
```sh
rune run --ndjson -- fledge lanes run check
```
```json
{"event":"result","status":"ok","data":{"command":"fledge lanes run check","exit_code":0,"clean_output":"...","duration_ms":1652.8}}
```

يُصدر `rune run --ndjson` ذلك الغلاف المفرد عند انتهاء الأمر. استخدم `rune watch` للحصول على
تدفّق حيّ لأحداث المخرجات.

### 3. تحليل مخرجات سطر الأوامر الجدولية إلى hashes
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

### 4. قيادة تطبيقات TTY / TUI التفاعلية
```ruby
require 'rune'

# Harness an interactive TUI program with input keystrokes
runner = Rune::PTYRunner.new("fledge plugins search --interactive", input: "\x03")
result = runner.run
# => Result with exit_code 130, clean_output, duration_ms
```

### 5. مراقبة جلسة حيّة (الإنسان يقود، والوكيل يتتبّع)
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

في وضع الوكيل — `--json` أو `--ndjson`، أو في أي وقت لا يكون فيه stdout طرفيةً — ينتقل التمرير
الحيّ إلى **stderr** كي لا يحمل stdout سوى غلاف النتيجة. فيحتفظ الإنسان بعرضه الحيّ، ويحصل
البرنامج المُستدعي على JSON نظيف:

```sh
rune watch --json -- ruby examples/humans/demo_tui.rb 2>/dev/null | jq .data.log_path
```

### 6. قيادة واجهة سطر أوامر وكيل من وكيل آخر (`rune session`)

يخزّن `run` ويعيد مرّة واحدة، ويحتاج `watch` إلى إنسان أمام طرفية وينتهي بانتهاء عمليته الابنة. ولا
يستطيع أيّ منهما إبقاء REPL وكيل مفتوحًا عبر الاستدعاءات. أما `session` فيستطيع:

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

**لماذا `--screen` بدل المخرجات الخام.** الوكيل الذي يعمل بملء الشاشة يعيد الرسم باستمرار، فيحتوي
تدفّق البايتات على كل إطار من كل إعادة رسم، والجواب موزَّع عليها. وبالقياس مقابل grok: نصٌّ مسجَّل
بحجم 361KB صُيِّر إلى شاشة بحجم 1.1KB، وجوابٌ كان الوكيل قد عرضه بوضوح غاب عن تدفّق البايتات في
3 دورات من 3، وحضر في الشاشة المُصيَّرة في 3 من 3. فإن كنت تطابق على المحتوى، فطابِق على `screen`.

**تولَّ القيادة بنفسك**، ثم أعِدها دون إيقاف أي شيء:

```sh
rune session attach --name reviewer   # Ctrl-] detaches; the session keeps running
```

الجلسات محصورة بنطاق شجرة عمل git المحيطة، فـ `reviewer` في نسختَي عمل هو جلستان. هذا مقصود،
وهو أيضًا أكثر المفاجآت شيوعًا — إن لم يُظهر `list` شيئًا، فتحقّق من الدليل الذي أنت فيه ومن
`RUNE_HOME`:

```sh
rune session list --all-projects
```

**العثور على شيء واحد في نصٍّ مسجَّل طويل.** بلغ عملُ يوم واحد مع وكيل مُقاد 379KB، ولا ينفع
`--since` ولا `--tail` حين يكون ما تريده في المنتصف:

```sh
rune session read --name reviewer --grep 'THE BOARD' --context 2
```

📖 الدليل الكامل، بما فيه ضبط الاستقرار والقيود المعروفة:
**[docs/sessions.md](docs/sessions.md)**.

---

## التكامل مع CorvidLabs

يتكامل `rune` مع [سلسلة أدوات الثقة في CorvidLabs](https://github.com/CorvidLabs):

- **[fledge](https://github.com/CorvidLabs/fledge)** — مشغِّل المهام ودورة حياة المشروع. و`rune` إضافة أصيلة لـ `fledge` معرَّفة عبر `plugin.toml`. ثبّتها مباشرةً عبر:
  ```sh
  fledge plugins install CorvidLabs/rune
  fledge rune run --json -- git status
  ```
- **[spec-sync](https://github.com/CorvidLabs/spec-sync)** — فرض العقود (`specs/`)
- **[augur](https://github.com/CorvidLabs/augur)** — تقييم مخاطر التغيير

---

## البنية والتفاصيل الداخلية

- 📖 **[دليل البدء](docs/getting_started.md)** — أوضاع المخرجات، واستخدام `rune run`، والمُهَل، والمُحلِّلات مع مخرجات أوامر حقيقية.
- 📖 **[دليل الجلسات الدائمة](docs/sessions.md)** — `rune session`: جلسات PTY مُسمّاة تتجاوز عمرَ استدعاء واحد، و"الإرسال والانتظار حتى الهدوء" لقيادة واجهة سطر أوامر وكيل من وكيل آخر.
- 📖 **[دليل بنية الطرفية الزائفة (PTY)](docs/pty_architecture.md)** — كيف تعمل الطرفيات الزائفة، والقراءة غير الحاجبة للتدفّقات، وتنقية ANSI، واكتشاف المُحِثّات، وتنفيذ النصوص، والتمرير الحيّ ثنائي الاتجاه في `rune watch`، من الداخل في Ruby.
- 📖 **[دليل الإصدار](docs/releasing.md)** — مزامنة الإصدارات، والتحقّق، والمنشأ، والوسم، ونشر الحزمة.

---

## التطوير والتحقّق

```sh
fledge run test         # Run RSpec test suite (405 examples, 87% line coverage)
fledge run lint         # Run RuboCop linter (0 offenses)
fledge lanes run verify # Full CI gate (lint + tests + strict 100%-coverage spec-sync)
fledge lanes run release # Verify, smoke-test, and build the release gem
fledge run smoke-test   # Runnable, assertion-based tour of real behavior (examples/smoke_test.rb)
COVERAGE=1 bundle exec rspec  # Same suite, plus an HTML coverage report at coverage/index.html
```

إن `examples/smoke_test.rb` نصٌّ مستقلّ بلا اعتماديات (لا يحتاج bundler ولا rspec) يمارس `rune run`
و`--timeout` و`TableParser`/`KeyValueParser` و`Script` وتمرير الإشارات واكتشاف المُحِثّات مقابل
ثنائي واجهة سطر الأوامر الحقيقي، مع مخرجات نجاح/فشل وخروج بقيمة غير صفرية عند الفشل. وهو مفيد
كفحص سلامة يدوي سريع، أو على جهاز لا تتوفّر فيه اعتماديات التطوير.

---

## الرخصة

MIT
