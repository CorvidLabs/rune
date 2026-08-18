# rune

यह README.md का हिंदी अनुवाद है; अंग्रेज़ी संस्करण ही प्रामाणिक है।

[![CI](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml/badge.svg)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-3.0%20%E2%80%93%204.0-CC342D?logo=ruby&logoColor=white)](https://github.com/CorvidLabs/rune/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-blue)](../../LICENSE)

एक Ruby CLI उपकरण और लाइब्रेरी, जिसे शुरू से ही **मनुष्यों और AI एजेंटों — दोनों के लिए प्रथम-श्रेणी** बनाने के उद्देश्य से डिज़ाइन किया गया है।

`rune` किसी भी CLI कमांड या इंटरैक्टिव TUI अनुप्रयोग के लिए एक सार्वभौमिक छद्म-टर्मिनल (PTY) रनर और संरचित डेटा सेतु का काम करता है।

हर कमांड मनुष्यों के लिए स्वरूपित, रंगीन टर्मिनल आउटपुट और AI एजेंटों के लिए संरचित JSON उत्पन्न करता है। इसके अतिरिक्त, जब कोई व्यक्ति सत्र चला रहा होता है, तब `rune watch` एक लाइव NDJSON इवेंट स्ट्रीम भी लिखता है। वही उपकरण, वही कमांड, दोहरा इंटरफ़ेस।

`rune session` इससे एक कदम आगे जाता है: यह किसी एजेंट CLI — `claude`, `grok`, `codex` — को अलग-अलग इनवोकेशनों के बीच खुला रखता है, जिससे एक एजेंट दूसरे को संवादात्मक ढंग से चला सकता है और कोई व्यक्ति उसी सत्र से जुड़कर नियंत्रण अपने हाथ में ले सकता है।

📖 यहाँ नए हैं? **[Getting Started guide](docs/getting_started.md)** से शुरुआत करें।

---

## क्षमताएँ

1. **दोहरा आउटपुट (मानव TTY / एजेंट JSON और NDJSON)**
   - टर्मिनल मोड: स्वरूपित रंगीन आउटपुट (`rune version`)
   - एजेंट JSON मोड: `--json` या स्वचालित पाइप पहचान (`rune version | cat`)
   - एजेंट NDJSON मोड: एक सुसंगत परिणाम आवरण के लिए `--ndjson` (`rune version --ndjson`)
2. **सार्वभौमिक PTY प्रक्रिया रनर (`rune run`)**
   - किसी भी CLI उपकरण या TUI को एक छद्म-टर्मिनल सत्र के भीतर चलाता है
   - ANSI एस्केप कोड, कर्सर संचलन और नियंत्रण अनुक्रमों को स्वतः हटा देता है
   - टर्मिनल पेजरों को निष्क्रिय कर देता है (`PAGER=cat`), ताकि क्वेरियाँ अटके बिना तुरंत लौटें
   - प्रक्रिया के निष्पादन की अवधि मिलीसेकंड में मापता है और इंटरैक्टिव प्रॉम्प्ट पहचानता है
3. **संरचित स्वतः-पार्सर (`Rune::Parsers`)**
   - `TableParser`: स्थान या पाइप से विभाजित टर्मिनल तालिकाओं को हैशों की सरणियों में पार्स करता है
   - `KeyValueParser`: कुंजी-मान आउटपुट (`key: val`) को टाइप किए गए हैशों में पार्स करता है
   - `TextSanitizer`: पंक्ति-अंत चिह्नों को सामान्य करता है और ANSI एस्केप कोड साफ़ करता है
4. **इंटरैक्टिव स्क्रिप्ट DSL (`Rune::Script`)**
   - इंटरैक्टिव टर्मिनल प्रॉम्प्ट और TUI मेन्यू चलाने के लिए चरण-दर-चरण TUI स्क्रिप्ट स्वचालन DSL
5. **लाइव इंटरैक्टिव पासथ्रू (`rune watch`)**
   - आपके टर्मिनल को रॉ मोड में रखता है और कीस्ट्रोक्स को बाइट-दर-बाइट, लाइव, चाइल्ड तक पहुँचाता है
   - चाइल्ड का आउटपुट जैसे-जैसे बनता है वैसे-वैसे आपकी स्क्रीन पर स्ट्रीम करता है (`rune run` के विपरीत, जो
     सब कुछ बफ़र करके अंत में लौटाता है)
   - साथ ही हर खंड को एक NDJSON इवेंट के रूप में अस्थायी फ़ाइल में लॉग करता है (पथ एक बार घोषित होता है, या
     `--log=PATH`), ताकि जब कोई व्यक्ति सत्र चला रहा हो, तब एक AI एजेंट उसे लाइव पढ़ता रह सके
6. **स्थायी नामित सत्र (`rune session`)**
   - REPL-जैसे चाइल्ड — `claude`, `grok`, `codex`, कोई शेल — को अलग-अलग `rune` इनवोकेशनों के *आर-पार*
     खुला रखता है, जो न `run` (जो बफ़र करके एक बार लौटता है) कर सकता है और न `watch` (जो अपने चाइल्ड के
     साथ ही समाप्त हो जाता है)
   - **सेंड-एंड-सेटल**: इनपुट लिखें, चाइल्ड के शांत होने की प्रतीक्षा करें, और ठीक वही आउटपुट वापस पाएँ जो उस
     सेंड ने उत्पन्न किया — इस तरह एक एसिंक्रोनस TTY एक सिंक्रोनस अनुरोध/प्रतिक्रिया कॉल में बदल जाता है
   - `--screen` कच्ची बाइट स्ट्रीम के बजाय *रेंडर किया गया टर्मिनल* लौटाता है, जो इसलिए मायने रखता है
     क्योंकि एक फ़ुल-स्क्रीन एजेंट अपने उत्तर को अपने ही पुनर्लेखनों के बीच गूँथ देता है — एक मापे गए
     ट्रांसक्रिप्ट में 361KB का रीपेंट ट्रैफ़िक घटकर 1.1KB की स्क्रीन रह गया
   - `attach` जीवित सत्र को एक मानव टर्मिनल के हवाले कर देता है और **Ctrl-]** उसे वापस लौटा देता है, सत्र
     तब भी चलता रहता है
   - सत्र नामित, प्रोजेक्ट-स्कोप्ड और संग्रहणीय होते हैं; ट्रांसक्रिप्ट डिस्क और मेमोरी दोनों में सीमित रखे जाते
     हैं, इसलिए दिन भर चलता छोड़ा गया सत्र बिना किसी सीमा के नहीं बढ़ता

---

## इंस्टॉल

बिना उपसर्ग वाला `rune` जेम नाम सार्वजनिक RubyGems.org रजिस्ट्री पर पहले से ही एक असंबंधित पैकेज ने ले
रखा है, इसलिए वहाँ `gem install rune` करने पर गलत चीज़ इंस्टॉल होती है। CorvidLabs Homebrew टैप से
अनुरक्षित, चेकसम-पिन किया गया फ़ॉर्मूला इंस्टॉल करें:

```sh
brew install corvidlabs/tap/rune
rune version --json
```

बाद के रिलीज़ भी इसी माध्यम से अपग्रेड करें:

```sh
brew upgrade corvidlabs/tap/rune
```

सोर्स से विकास के लिए:

```sh
git clone https://github.com/CorvidLabs/rune.git
cd rune
bundle install
ruby bin/rune version
```

---

## उपयोग के उदाहरण

### 0. CLI को खोजें

```sh
rune --help              # every command, plus the global flags
rune run --help          # one command's usage and its own flags
rune help watch          # same thing, spelled the other way
```

हेल्प भी संरचित है, इसलिए कोई एजेंट टेक्स्ट खुरचे बिना ही पूरी सतह का पता लगा सकता है:

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

> **लपेटे जाने वाले कमांड से पहले `--` का प्रयोग करें।** rune का हर फ़्लैग — `--json`, `--ndjson`, `--help`,
> `--timeout`, `--log` — *केवल* पहले `--` से पहले ही पहचाना जाता है। इसी कारण
> `rune run -- gh pr list --json number` में `--json` को `gh` तक पहुँचाया जाता है, न कि rune उसे खुद खा
> जाता है। इस विभाजक के बिना rune फ़्लैग को अपने लिए ले लेता है और लपेटे गए कमांड तक वह चुपचाप कभी
> पहुँचता ही नहीं।

### 1. किसी भी CLI कमांड को एजेंट JSON मोड में चलाएँ
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

### 2. NDJSON परिणाम आवरण
```sh
rune run --ndjson -- fledge lanes run check
```
```json
{"event":"result","status":"ok","data":{"command":"fledge lanes run check","exit_code":0,"clean_output":"...","duration_ms":1652.8}}
```

कमांड पूरा होने पर `rune run --ndjson` वही एकल आवरण उत्सर्जित करता है। आउटपुट इवेंट्स की लाइव स्ट्रीम के
लिए `rune watch` का प्रयोग करें।

### 3. सारणीबद्ध CLI आउटपुट को हैशों में पार्स करें
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

### 4. इंटरैक्टिव TTY / TUI अनुप्रयोगों को चलाएँ
```ruby
require 'rune'

# Harness an interactive TUI program with input keystrokes
runner = Rune::PTYRunner.new("fledge plugins search --interactive", input: "\x03")
result = runner.run
# => Result with exit_code 130, clean_output, duration_ms
```

### 5. किसी सत्र को लाइव देखें (मनुष्य चलाता है, एजेंट पढ़ता रहता है)
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

एजेंट मोड में — `--json`, `--ndjson`, या जब भी stdout कोई टर्मिनल न हो — लाइव पासथ्रू **stderr** पर चला
जाता है, ताकि stdout पर परिणाम आवरण के सिवा और कुछ न रहे। मनुष्य को उसका लाइव दृश्य मिलता रहता है और
कॉल करने वाले प्रोग्राम को साफ़ JSON:

```sh
rune watch --json -- ruby examples/humans/demo_tui.rb 2>/dev/null | jq .data.log_path
```

### 6. एक एजेंट CLI से दूसरे को चलाएँ (`rune session`)

`run` बफ़र करके एक बार लौटता है; `watch` को टर्मिनल पर एक मनुष्य चाहिए और वह अपने चाइल्ड के साथ ही समाप्त
हो जाता है। इनमें से कोई भी किसी एजेंट REPL को कई कॉलों के आर-पार खुला नहीं रख सकता। `session` रख सकता है:

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

**कच्चे आउटपुट के बजाय `--screen` क्यों।** एक फ़ुल-स्क्रीन एजेंट लगातार पुनर्लेखन करता रहता है, इसलिए बाइट
स्ट्रीम में हर पुनर्लेखन का हर फ़्रेम होता है और उत्तर उन सबमें बँटा रहता है। grok के विरुद्ध मापा गया: 361KB का
ट्रांसक्रिप्ट रेंडर होकर 1.1KB की स्क्रीन बना, और जो उत्तर एजेंट ने स्पष्ट रूप से दिखाया था वह 3 में से 3 बार
बाइट स्ट्रीम में अनुपस्थित था तथा 3 में से 3 बार रेंडर की गई स्क्रीन में उपस्थित। यदि आप विषय-वस्तु पर मिलान
कर रहे हैं, तो `screen` पर मिलान कीजिए।

**कमान खुद संभालें**, और फिर बिना कुछ रोके उसे वापस लौटा दें:

```sh
rune session attach --name reviewer   # Ctrl-] detaches; the session keeps running
```

सत्र अपने आसपास के git वर्किंग ट्री तक सीमित होते हैं, इसलिए दो चेकआउट में `reviewer` दो अलग सत्र हैं। यह
जानबूझकर है, और यही सबसे आम आश्चर्य भी है — यदि `list` कुछ न दिखाए, तो देखें कि आप किस डायरेक्टरी में हैं
और `RUNE_HOME` क्या है:

```sh
rune session list --all-projects
```

**लंबे ट्रांसक्रिप्ट में कोई एक चीज़ ढूँढ़ना।** किसी संचालित एजेंट के साथ एक दिन का काम 379KB तक पहुँच गया,
और जब आपकी ज़रूरत की चीज़ बीच में हो, तब न `--since` काम आता है और न `--tail`:

```sh
rune session read --name reviewer --grep 'THE BOARD' --context 2
```

📖 पूरी मार्गदर्शिका, जिसमें settle ट्यूनिंग और ज्ञात सीमाएँ भी शामिल हैं:
**[docs/sessions.md](docs/sessions.md)**.

---

## CorvidLabs के साथ एकीकरण

`rune` [CorvidLabs trust toolchain](https://github.com/CorvidLabs) के साथ एकीकृत होता है:

- **[fledge](https://github.com/CorvidLabs/fledge)** — टास्क रनर और प्रोजेक्ट लाइफ़साइकल। `rune` एक नेटिव `fledge` प्लगइन है, जिसे `plugin.toml` के ज़रिए परिभाषित किया गया है। सीधे इस तरह इंस्टॉल करें:
  ```sh
  fledge plugins install CorvidLabs/rune
  fledge rune run --json -- git status
  ```
- **[spec-sync](https://github.com/CorvidLabs/spec-sync)** — कॉन्ट्रैक्ट प्रवर्तन (`specs/`)
- **[augur](https://github.com/CorvidLabs/augur)** — परिवर्तन जोखिम स्कोरिंग

---

## आर्किटेक्चर और आंतरिक कार्यप्रणाली

- 📖 **[Getting Started guide](docs/getting_started.md)** — आउटपुट मोड, `rune run` का उपयोग, टाइमआउट, और वास्तविक कमांड आउटपुट के साथ पार्सर।
- 📖 **[Persistent sessions guide](docs/sessions.md)** — `rune session`: नामित PTY सत्र जो एक अकेली इनवोकेशन से आगे तक जीवित रहते हैं, और एक एजेंट CLI से दूसरे को चलाने के लिए सेंड-एंड-सेटल।
- 📖 **[Pseudo-TTY (PTY) Architecture Guide](docs/pty_architecture.md)** — छद्म-टर्मिनल, नॉन-ब्लॉकिंग स्ट्रीम पठन, ANSI स्वच्छता, प्रॉम्प्ट पहचान, स्क्रिप्ट निष्पादन, और `rune watch` का लाइव द्विदिश पासथ्रू — ये सब Ruby में परदे के पीछे कैसे काम करते हैं।
- 📖 **[Release guide](docs/releasing.md)** — संस्करण समकालन, सत्यापन, उद्गम-प्रमाण, टैगिंग, और पैकेज प्रकाशन।

---

## विकास और सत्यापन

```sh
fledge run test         # Run RSpec test suite (405 examples, 87% line coverage)
fledge run lint         # Run RuboCop linter (0 offenses)
fledge lanes run verify # Full CI gate (lint + tests + strict 100%-coverage spec-sync)
fledge lanes run release # Verify, smoke-test, and build the release gem
fledge run smoke-test   # Runnable, assertion-based tour of real behavior (examples/smoke_test.rb)
COVERAGE=1 bundle exec rspec  # Same suite, plus an HTML coverage report at coverage/index.html
```

`examples/smoke_test.rb` एक स्वतंत्र, निर्भरता-रहित स्क्रिप्ट है (न bundler चाहिए, न rspec), जो असली CLI
बाइनरी के विरुद्ध `rune run`, `--timeout`, `TableParser`/`KeyValueParser`, `Script`, सिग्नल अग्रेषण, और
प्रॉम्प्ट पहचान को परखती है, पास/फ़ेल आउटपुट देती है और विफलता पर शून्येतर एग्ज़िट कोड लौटाती है। त्वरित
मैनुअल जाँच के लिए उपयोगी, या ऐसी मशीन पर जहाँ डेवलपमेंट निर्भरताएँ इंस्टॉल न हों।

---

## लाइसेंस

MIT
