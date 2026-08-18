> هذه ترجمة عربية لملف `docs/getting_started.md`، والنسخة الإنجليزية الأصلية هي المرجع المعتمد.

# البدء مع rune

`rune` أداة سطر أوامر ومكتبة مكتوبتان بلغة Ruby، صُمِّمتا ليستعملهما الإنسان من الطرفية ووكيل الذكاء
الاصطناعي الذي يقودهما برمجياً بالقدر نفسه من اليسر. كل أمر يُعيد كائن `Result` المنظَّم نفسه — وما
يتغيَّر هو *طريقة العرض* وحدها تبعاً لطريقة استدعائك له.

## التثبيت

اسم الجيم المجرَّد `rune` محجوز أصلاً في سجل RubyGems.org العام لحزمة لا صلة لها بالمشروع، ولذلك فإن
`gem install rune` هناك يثبِّت شيئاً آخر. أما مسار التثبيت المعتمد للمستخدم النهائي فهو الصيغة
المثبَّتة على مجموع تحقُّق في مستودع tap الخاص بـ CorvidLabs في Homebrew:

```sh
brew install corvidlabs/tap/rune
rune version --json
```

يضيف Homebrew هذا المستودع تلقائياً عند أول تثبيت. ولترقية Rune استعمل:

```sh
brew upgrade corvidlabs/tap/rune
```

ولا تستنسخ الشيفرة المصدرية إلا إذا كنت تطوّر Rune نفسه:

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

أو بوصفه إضافة لـ [fledge](https://github.com/CorvidLabs/fledge):

```sh
fledge plugins install CorvidLabs/rune
fledge rune run --json -- git status
```

## اكتشاف ما هو متاح

```sh
rune --help              # or -h, or `rune help`
rune run --help          # or `rune help run`, or `rune run -h`
```

تسرد مساعدة الأمر رايات ذلك الأمر نفسه — `--timeout=SECONDS` مع `rune run`، و`--log=PATH` مع
`rune watch` — إلى جانب الرايات العامة. وهي منظَّمة في وضع الوكيل أيضاً، فلا يحتاج الاكتشاف إلى
تحليل العرض الموجَّه للبشر:

```sh
$ rune run --help --json | jq -c '.data.flags'
[{"flag":"--timeout=SECONDS","description":"Kill the wrapped command after N seconds (default 30). Before `--` only."},{"flag":"--max-output=BYTES","description":"Bound clean_output/raw_output to BYTES each, keeping head+tail and marking the join with a `[rune] ==== N bytes omitted by --max-output ====` line. Mutually exclusive with --tail. Before `--` only."},{"flag":"--tail=N","description":"Keep only the last N lines of clean_output/raw_output. Mutually exclusive with --max-output. Before `--` only."},{"flag":"--separate-streams","description":"Adds clean_stdout/clean_stderr (stderr on a pipe, not the pty) alongside the merged view. Before `--` only."}]
```

وتخضع رايات المساعدة لقاعدة الفاصل نفسها التي يخضع لها كل شيء آخر (انظر أدناه): فالأمر
`rune run -- mytool --help` يمرِّر `--help` إلى `mytool`.

## أوضاع الإخراج الثلاثة

يختار `rune` وضع العرض تلقائياً بحسب طريقة استدعائه، أو يمكنك فرض وضع بعينه براية صريحة. والأوضاع
الثلاثة تنفِّذ منطق الأمر ذاته تماماً — الفارق في صيغة الإخراج وحدها.

### 1. وضع الطرفية البشري (الافتراضي، طرفية تفاعلية)

حين يكون stdout طرفيةً حقيقية ولم تُمرَّر راية `--json` أو `--ndjson`، يطبع `rune` مخرجات ملوَّنة
مهيَّأة للقراءة البشرية:

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

### 2. وضع JSON للوكلاء (`--json`، أو الكشف التلقائي عن الأنبوب)

مرِّر `--json` صراحةً، أو اكتفِ بتوجيه مخرجات `rune` عبر أنبوب أو إعادة توجيه — فوجود stdout غير
طرفي ينقل العرض إلى JSON تلقائياً دون حاجة إلى أي راية:

```sh
$ ruby bin/rune run --json -- echo "hello agent"
{"status":"ok","data":{"command":"echo hello\\ agent","exit_code":0,"clean_output":"hello agent\n","raw_output":"hello agent\r\n","prompt_detected":false,"duration_ms":5.27}}
```

```sh
$ ruby bin/rune version | cat
{"status":"ok","data":{"name":"rune","version":"0.7.0","ruby":"4.0.6","ruby_platform":"arm64-darwin25","fledge":true,"specsync":true}}
```

> **`exit_code` هو حالة خروج العملية المغلَّفة، لا حكمٌ على صحة العمل.** إنه يجيب عن سؤال "هل انتهت
> العملية، وكيف انتهت"، وهو في واجهة أوامر موجَّهة للوكلاء يساوي `0` في أغلب الأحوال — بما في ذلك
> عمليات جاءت مخرجاتها خاطئة. فقد حصل أحد المستدعين على `0` في ثماني عمليات `rune run` متتالية،
> أنتج عدد منها استنتاجات اضطر إلى تصحيحها لاحقاً. وإن أردت أن تعرف هل نجح *العمل* نفسه، فذلك يأتي
> من المخرجات لا من هذا الحقل. و`124` هو الاستثناء الجدير بالمعرفة: فهو يعني أن rune أنهى العملية
> عند انقضاء `--timeout`.

ولكل استجابة JSON الغلاف نفسه: `{"status": "ok"|"error", "data": {...}}` (أو
`{"status": "error", "error": "..."}` عند الإخفاق).

يكتب Rune الغلاف النهائي إلى stdout في حالتَي النجاح والإخفاق معاً. وهذا يمنح الوكلاء قناة نتائج
واحدة قابلة للتحليل، لكنه يعني أيضاً أن من يعيد توجيه stdout من البشر يعيد معه توجيه رسائل الأخطاء
الصادرة عن Rune نفسه. أما stderr فمحجوز للإعلانات التشغيلية ولتمرير `rune watch` الحي الذي يجب ألا
يفسد مخرجات stdout المنظَّمة.

ولا يُعترف برايات الإخراج العامة إلا قبل أول فاصل `--`. أما الرموز التي تليه فهي ملك للأمر المغلَّف
وتُحفظ كما هي، فالأمر `rune run -- tool --json` يمرِّر `--json` إلى `tool`.

وأي راية `--flag` لا يعرفها rune، إذا وردت في موضع رايات rune نفسها، تُعدّ خطأً لا شيئاً يُمرَّر
بصمت: فالأمر `rune run --tiemout=5 -- echo hi` كان فيما مضى يحاول *تنفيذ* الراية المكتوبة خطأً
ويجيب بـ `status: ok` مع `exit_code: 127`. ولا تُفحص إلا الرموز السابقة للأمر المغلَّف، فيبقى
`rune run cargo clippy --tests` و`rune run -- mytool --tiemout=5` بلا مساس — فما إن يظهر اسم الأمر
حتى تصير كل راية `--flag` بعده ملكاً له.

### 3. وضع غلاف NDJSON للوكلاء (`--ndjson`)

تغلِّف `--ndjson` النتيجة نفسها في غلاف `{"event": "result"|"error", ...}` بدلاً من الشكل المجرَّد
`{"status": ...}` الذي تستعمله `--json` — وهي صيغة تتوقعها بعض بيئات الوكلاء على نحو موحَّد لكل أمر،
بما في ذلك `rune run`:

```sh
$ ruby bin/rune run --ndjson -- echo "hello stream"
{"event":"result","status":"ok","data":{"command":"echo hello\\ stream","exit_code":0,"clean_output":"hello stream\n","raw_output":"hello stream\r\n","prompt_detected":false,"duration_ms":11.45}}
```

ومع `rune run` يبقى هذا سطراً واحداً بالضبط، يُبعث بعد انتهاء الأمر — إذ يخزّن `PTYRunner` التشغيلة
كاملة في ذاكرة مؤقتة ثم يعيد `Result` واحداً، فـ `--ndjson` هنا اختيار غلاف لا بثّاً تدريجياً. وإذا
أردت تدفّق أحداث حياً فعلاً مع تقدّم أمر طويل الأمد أو تفاعلي، فانظر
[`rune watch`](#متابعة-الجلسة-حياً-عبر-rune-watch) أدناه، فهو يبعث سطر NDJSON واحداً لكل دفعة
مخرجات لحظة حدوثها.

## تشغيل الأوامر عبر `rune run`

يشغّل `rune run` أي أمر سطر أوامر أو واجهة نصية تفاعلية داخل PTY حقيقي، ويجرّد تسلسلات الهروب ANSI،
ويعطّل صفحات العرض، ويقيس زمن التنفيذ:

```sh
rune run -- git status
rune run --json -- npm test
rune run --ndjson -- fledge lanes run check
```

### تجاوز المهلة

لكل استدعاء لـ `rune run` مهلة افتراضية مقدارها ثلاثون ثانية. وتستطيع تجاوزها بـ `--timeout=SECONDS`
موضوعة *قبل* الفاصل `--` كي لا تُحسب راية تخصّ الأمر المغلَّف:

```sh
$ ruby bin/rune run --json --timeout=1 -- sleep 3
{"status":"ok","data":{"command":"sleep 3","exit_code":124,"clean_output":"\n[rune] Execution timed out after 1 seconds","raw_output":"\n[rune] Execution timed out after 1 seconds","prompt_detected":false,"duration_ms":1005.32}}
```

والأمر الذي تنقضي مهلته يعيد رمز الخروج `124` مع رسالة
`[rune] Execution timed out after N seconds` مُلحَقة بالمخرجات الملتقطة — وهو مع ذلك `Result` عادي
لا استثناء.

**تُعاد دائماً المخرجات الملتقطة قبل الإنهاء**، فالعملية الابنة التي طبعت شيئاً ثم تعلّقت تُظهر ما
طبعته. وإذا كانت المخرجات *فارغة* فذلك يعني أن الابنة لم تطبع شيئاً حقاً، ويقول rune ذلك صراحةً مع
ذكر السبب الأكثر شيوعاً.

**لا يمرِّر `rune run` مدخلاته القياسية إلى العملية الابنة.** فالطرفية ملك للإنسان — والاستيلاء
عليها مهمة `rune watch` — كما أن تمرير أنبوب سيعيد صدى مدخلات المستدعي عبر الـ pty إلى
`clean_output`. لذلك تنقضي مهلة `echo hi | rune run -- cat`: فـ `cat` ينتظر مدخلات لا تصل أبداً.
ضع إعادة التوجيه داخل الأمر نفسه، حيث تنفّذها الصدفة داخل الـ pty:

```sh
$ rune run -- sh -c 'claude -p --output-format text < prompt.md'
```

هذا يعمل، وكذلك يعمل تمرير مُوجَّه متعدد الفقرات وسيطاً واحداً — فأسطر الفصل تعبر argv سليمة. أما
حقل `command` في الرد فهو إعادة بناء *للعرض* على البشر بعد تهريب رموز الصدفة، لا ما تلقّته العملية
الابنة؛ فلا تشخّص مشكلات الاقتباس انطلاقاً منه.

### تحديد حجم المخرجات وفصل التدفقات

ثلاث رايات إضافية، جميعها قبل الفاصل `--`، وجميعها تغيّر *شكل* النتيجة:

- **`--max-output=BYTES`** تحدّ `clean_output` و`raw_output` بـ BYTES لكل منهما، مبقيةً على الصدر
  والذيل، وتضيف `truncated: true` مع `omitted_bytes`. ويترتب على كلمة "لكل منهما" أمران: أن الحقلين
  محدودان *كلٌّ على حدة*، فهما تحت هذه الراية يصفان نافذتين مختلفتين من التشغيلة، ولا يكون
  `clean_output` هو `strip_ansi(raw_output)` — فـ `omitted_bytes` هو عدّاد `clean_output`، بينما
  يحمل `raw_output` علامته الخاصة بعدد مختلف. ثم إن `omitted_bytes` يُقاس بالإزاحات داخل النص
  الأصلي، فيتطابق تماماً في نصوص ASCII ويحيد ببضعة بايتات في النصوص متعددة البايتات، حيث قد يشطر
  القطعُ محرفاً. ويُوصل النصفان بسطر
  `[rune] ==== N bytes omitted by --max-output ====` بدلاً من لصقهما، كي لا يُقرأ النص المُعاد بوصفه
  شيئاً طبعه الأمر: فمن دونه أسقط سجلٌّ طوله 201 بايت عند `--max-output=200` البايت الذي حوّل
  `chsh -s /bin/zsh` إلى `chsh -s bin/zsh` بالضبط. وهذه العلامة تعليقٌ من rune لا مخرجاتٌ للأمر،
  فلا تُحتسب ضمن BYTES وقد يتجاوز الرد الميزانية قليلاً.
- **`--tail=N`** تبقي على آخر N سطراً فقط، وتضيف `truncated: true` مع `omitted_lines`. وهي متنافية
  مع `--max-output`؛ وتمريرهما معاً خطأ لا أولوية صامتة لأحدهما.
- **`--separate-streams`** تضيف `clean_stdout` و`clean_stderr` إلى جانب `clean_output` المدمج، لا
  بدلاً منه.

ولـ `--separate-streams` كلفة حقيقية، ولهذا كانت اختيارية لا افتراضية: فللـ pty تدفق واحد، وفصل
التدفقين يعني منح stderr أنبوبه الخاص. عندئذ لا ترى العملية الابنة طرفية تحكّم واحدة لكليهما،
والبرنامج الذي يفحص `isatty(2)` سيتصرف كأن أخطاءه يُعاد توجيهها — وهو ما يعني في كثير من أدوات سطر
الأوامر إسقاط الألوان أو التحول إلى وضع غير تفاعلي بالكامل. فاستعملها حين تكون حاجتك إلى الفصل أكبر
من حاجتك إلى أن تصدّق العملية الابنة أنها على طرفية.

## متابعة الجلسة حياً عبر `rune watch`

يخزّن `rune run` مخرجات الأمر كاملة ولا يعيدها إلا بعد انتهائه — وهذا ممتاز للبرمجة النصية والالتقاط،
لكنه لا يصلح إن أردت فعلاً أن تجلس إلى لوحة المفاتيح وتقود برنامجاً تفاعلياً بينما يراقب الجلسةَ طرفٌ
آخر. وقد صُنع `rune watch` لهذا الغرض: يضع طرفيتك في الوضع الخام، ويمرِّر كل ضغطة مفتاح تكتبها إلى
العملية الابنة حياً — بما في ذلك تسلسلات الهروب الخام كمفاتيح الأسهم، لا الأسطر الكاملة وحدها —
ويبثّ مخرجات الابنة إلى شاشتك لحظة حدوثها (لا في النهاية)، ويسجّل في الوقت نفسه كل دفعة بوصفها حدث
NDJSON — فيستطيع وكيل ذكاء اصطناعي متابعة الجلسة آنياً بينما يقودها إنسان.

```sh
# A small interactive demo program ships with rune specifically to try this against:
rune watch -- ruby examples/humans/demo_tui.rb
```

ويقع سجل الأحداث افتراضياً في ملف مؤقت آمن من التصادم ومقصور على مالكه (`0600`)، لا في stderr — فقد
كان خلط أحداث NDJSON بالطرفية نفسها التي يجري فيها التمرير الحي هو التصميم الأصلي، وسرعان ما أظهر
الاستعمال الواقعي أنه الافتراض الخاطئ (إذ جعل تداخلُ JSON الجلسةَ غير قابلة للقراءة). ويُعلَن المسار
مرة واحدة في البداية:

```
[rune watch] live event log: /tmp/rune-watch-20260728-12345-abcd.ndjson
```

استعمل `tail -f` على ذلك المسار من لوح آخر (أو دع وكيلاً يتابعه) لترى الجلسة حية مع بقاء طرفيتك
نظيفة. ووجّهه إلى موضع محدد بدلاً من ذلك عبر `--log=PATH`:

```sh
rune watch --log=/tmp/session.ndjson -- ruby examples/humans/demo_tui.rb
```

وكل سطر في السجل كائن JSON: `{"event":"start","command":"...","pid":...}`، ثم
`{"event":"output","bytes":N,"text":"..."}` واحد لكل دفعة أثناء بثّها، ثم
`{"event":"exit","exit_code":N}` عند خروج العملية الابنة.

### `rune watch` في وضع الوكيل

يتبع `rune watch` قواعد أوضاع الإخراج نفسها التي يتبعها كل أمر آخر. فمع `--json` أو `--ndjson`، أو
في أي حال لا يكون فيها stdout طرفيةً، ينتقل التمرير الحي إلى **stderr** ويحمل stdout غلاف النتيجة
وحده — فيستطيع البرنامج المُغلِّف تحليل stdout مباشرة بينما يظل الإنسان الجالس إلى لوحة المفاتيح
يرى جلسته:

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

واحذف `2>/dev/null` إن أردت الاستمرار في متابعة الجلسة بنفسك بينما يُلتقط JSON في مكان آخر.

ويتطلب `rune watch` طرفيةً حقيقية (فهو يرفض العمل إن لم يكن stdin طرفية TTY — إذ لا معنى لوضع غير
تفاعلي هنا)، ولا يعمل داخل الـ PTY المتداخل الذي ينشئه `rune run`، ولذلك يتعذر عرضه في مثال ممرَّر
عبر أنبوب كما هي حال بقية هذا الدليل. والقائمة العليا في `examples/humans/demo_tui.rb` منتقٍ حقيقي
بمفاتيح الأسهم (↑/↓ مع Enter، أو `q` للخروج) لا قائمةَ اكتب-رقماً-واضغط-Enter، والغرض من ذلك تحديداً
تمرين تمرير البايتات المفردة الخام وتسلسلات الهروب — وهو ما لا تمسّه أبداً قائمةٌ مخزَّنة سطراً
بسطر. ويحوي التعليق الافتتاحي في `examples/humans/demo_tui.rb` أوامر جاهزة للنسخ واللصق، ويبيّن
`spec/rune/pty_watcher_spec.rb` كيف تُختبر وحدوياً آليات التمرير والتسجيل الكامنة، بما في ذلك اختبار
يقود قائمة مفاتيح الأسهم نفسها من طرف إلى طرف (كائن طرفية زائف مع أنابيب `IO.pipe` يقود عملية ابنة
تفاعلية حقيقية دون الحاجة إلى طرفية تحكّم فعلية).


### تحديد حدود المتابعة

حدّان مستقلان، كلاهما قبل الفاصل `--`، وكلاهما معطَّل افتراضياً:

- **`--timeout=SECONDS`** ينهي الجلسة بعد N ثانية من الزمن الفعلي مهما بلغ انشغالها.
- **`--idle-timeout=SECONDS`** ينهيها بعد N ثانية **بلا مخرجات ولا مدخلات** — وهو ما تريده للحالة
  التي "توقف فيها هذا الوكيل عن فعل أي شيء"، إذ إن البناء الطويل ليس خمولاً.

وأيّهما وقع أعطى رمز الخروج `124` مع `timed_out: true` و`timeout_kind` بقيمة `"timeout"` أو
`"idle_timeout"` تبيّن أيّهما انطلق.
## تحليل النص المنظَّم

يحوّل كلٌّ من `Rune::Parsers::TableParser` و`Rune::Parsers::KeyValueParser` مخرجات الطرفية غير
المنظَّمة إلى جداول تجزئة في Ruby:

```ruby
require 'rune'

Rune::Parsers::TableParser.parse(<<~TABLE)
  NAME           STATUS   VERSION
  fledge-plugin  active   1.0.0
TABLE
# => [{ name: 'fledge-plugin', status: 'active', version: '1.0.0' }]
```

ويقبل `TableParser.parse` كلمة مفتاحية `format:` (قيمتها `:auto` افتراضياً، أو `:pipe`/`:space`
لفرض وضع تحليل بعينه) — وانظر [`specs/parsers/parsers.spec.md`](../specs/parsers/parsers.spec.md)
للاطلاع على القيود المعروفة في الاستدلال قبل الاعتماد على `:auto` مع مخرجات غير مألوفة.

## الخطوات التالية

- [`examples/smoke_test.rb`](../examples/smoke_test.rb) — عبر `ruby examples/smoke_test.rb` أو
  `fledge run smoke-test`. جولة مستقلة قائمة على التوكيدات في السلوك الحقيقي (لا تحتاج إلى bundler
  أو rspec): أوضاع الإخراج، والتحقق من `--timeout`، والمحلّلات، و`Script`، وتمرير الإشارات، وكشف
  المُحَثّات.
- [`examples/humans/demo_tui.rb`](../examples/humans/demo_tui.rb) — العرض التفاعلي المستعمل في كل
  قسم `rune watch` أعلاه. أما [`examples/agents/pty_runner_example.rb`](../examples/agents/pty_runner_example.rb)
  و[`table_parser_example.rb`](../examples/agents/table_parser_example.rb)
  و[`script_automation_example.rb`](../examples/agents/script_automation_example.rb) فبرامج أصغر
  يعالج كلٌّ منها فكرة واحدة — وكلٌّ منها قابل للتشغيل مباشرة (`ruby examples/agents/<name>.rb`) بلا
  إعداد سوى `require_relative '../lib/rune'`.
- [دليل معمارية PTY](pty_architecture.md) — كيف يعمل داخلياً مشغّل PTY، وقراءة التدفقات، وكشف
  المُحَثّات، والتمرير الحي في `rune watch`.
- [`specs/`](../specs/) — عقود الوحدات المفحوصة آلياً (`spec-sync`) لـ `cli` و`parsers`
  و`pty_runner` و`session` و`watch`.
- [`AGENTS.md`](../AGENTS.md) — الأعراف المتّبعة في إضافة أوامر جديدة والعمل مع سلسلة أدوات الثقة.
