# 賢者アダプター — 設定と導入

3つの席にどの CLI を座らせるか、`magi-run.sh` がそれをどう呼び出すか、どう差し
替えるかを説明する。英語版は [sages.md](sages.md)。

賢者の構成をスキル本体ではなく設定ファイルに置いているのは意図的である。
ヘッドレスのエージェント CLI は数ヶ月単位で登場と終了を繰り返す。Gemini CLI は
2026年6月に個人向け提供を終了したが、集約記事はその後も現役として紹介していた。
そのため `SKILL.md` の判断規則には特定の CLI 名を書かず、以下のフィールド名だけ
を参照する。

## 設定ファイルの探索順

`magi-run.sh` は、次の順で**最初に見つかった1ファイル**だけを読む。

1. `$MAGI_SAGES_FILE` — 実行ごとの上書き。変数が設定されているのにファイルが
   存在しない場合、既定へ戻らず exit 2 で停止する。明示した上書きが黙って無効に
   なるほうが、エラーで止まるより厄介だからである。
2. `./.magi/sages.json` — プロジェクトごと（カレントディレクトリ基準）。
3. `~/.magi/sages.json` — 利用者ごと。
4. `references/scripts/sages.default.json` — 同梱の既定。

読むのは1ファイルだけで、内容の合成はしない。1体だけ差し替えたい場合も、上書き
ファイルには使いたい**全賢者**を書く必要がある。

## トップレベルのフィールド

| フィールド | 型 | 意味 |
|---|---|---|
| `timeout_seconds` | 正の整数 | 賢者1体あたりの実時間の上限。`perl alarm` のラッパーが強制する。既定は 600（10分）。これで停止された賢者は `status: "timeout"` として記録される |
| `sages` | 配列（1〜3件） | 賢者の一覧。`summary.json` の行と結果マトリクスの行はこの順に並ぶ |

上限は3体である。`SKILL.md` の採決規則は3体（縮退時は2体）を前提に組んであるた
め、4体を書いた設定は採決方法を黙って変えるのではなく exit 2 で停止する。

2体の構成は受け付けるが、何も欠けていなくてもそれは縮退合議である。
`preflight.json` は `missing` を空のまま `available_count: 2` と報告する。
ホストは送信前にユーザーへ確認し、2体の規則（2対0で可決、1対1は討論1ラウンド
のみ）を適用する。1体の構成はこの時点でホストが中止する。1体は合議ではない。

## 賢者ごとのフィールド

| フィールド | 必須 | 意味 |
|---|---|---|
| `name` | はい | 表示名（例: `MELCHIOR`）。実行ディレクトリのファイル名になるため、使える文字は `A-Z a-z 0-9 _ -` のみ。重複不可 |
| `cli` | はい | preflight が `command -v` で存在確認するコマンド名。欠落時に報告される名前であり、マトリクスで賢者名に併記される名前でもある |
| `command` | はい | 文字列の非空配列。シェルを介さず argv としてそのまま実行される |
| `input` | いいえ | `"stdin"` を指定すると、プロンプトファイルを標準入力へリダイレクトして渡す。省略すると `{PROMPT_FILE}` でパスを渡す。他の値は受け付けない |
| `extract` | はい | 回答本文の取り出し方。jq フィルタ / `"answer-file"` / `"raw"`（後述） |
| `schema_args` | いいえ | 文字列の配列。`--schema-file` を渡した実行のときだけ `command` の後ろに追加される |
| `notes` | いいえ | 次に設定を読む人向けの自由記述。スクリプトは無視する |

### `command` と `schema_args` のプレースホルダー

置換は配列の要素単位で行い、シェルを通さない。空白や `&` を含むパスが構文として
再解釈されることはない。

| プレースホルダー | 置換される内容 |
|---|---|
| `{PROMPT_FILE}` | このラウンドでこの賢者へ送るプロンプトファイルの絶対パス |
| `{ANSWER_FILE}` | CLI が最終回答を書き出すことをスクリプトが期待するパス |
| `{SCHEMA}` | `--schema-file` で渡したファイルの全文 |

**プロンプト本文は `command` に入れない。** コマンドライン引数は同一マシンの
全プロセスから `ps` で読めるため、問いは標準入力かファイルパスのどちらかで渡す。
旧 `{PROMPT}` プレースホルダーはこの理由で廃止され、設定の検査はそれを名指しで
拒否する。したがって各賢者は `command` に `{PROMPT_FILE}` を持つか、
`"input": "stdin"` を持つ必要がある。どちらも無い設定は、問いを届ける手段が無い
ため拒否される。

### `extract` に指定できる値

| 値 | 使う場面 | 動作 |
|---|---|---|
| jq フィルタ（例: `.result`） | CLI が stdout に JSON 封筒を出す | `jq -er` で適用する。キーが無い、`null`、結果が空のいずれも取り出し失敗として扱う |
| `"answer-file"` | CLI が最終メッセージをファイルへ書く | `{ANSWER_FILE}` を読む。`command` にこのプレースホルダーが必要。内容は変換しない |
| `"raw"` | CLI が回答をプレーンテキストで出す | stdout をそのまま複製する |

取り出しに失敗すると、CLI が exit 0 でも `status: "error"` になる。回答がホスト
の要求した JSON かどうかをスクリプトは検査しない。その検査はホストの担当であり
（CON-002）、解析できない回答はホストが縮退扱いにする（REQ-010）。

## 同梱の既定設定

```json
{
  "timeout_seconds": 600,
  "sages": [
    {
      "name": "MELCHIOR",
      "cli": "claude",
      "command": ["claude", "-p", "--output-format", "json", "--allowedTools", "WebSearch", "WebFetch"],
      "input": "stdin",
      "extract": ".result"
    },
    {
      "name": "BALTHASAR",
      "cli": "codex",
      "command": ["codex", "exec", "--sandbox", "read-only", "--output-last-message", "{ANSWER_FILE}", "-"],
      "input": "stdin",
      "extract": "answer-file"
    },
    {
      "name": "CASPER",
      "cli": "grok",
      "command": ["grok", "--prompt-file", "{PROMPT_FILE}", "--output-format", "json", "--permission-mode", "auto"],
      "extract": ".text",
      "schema_args": ["--json-schema", "{SCHEMA}"]
    }
  ]
}
```

実ファイルには `notes` も入っているが、ここでは省いた。知っておく価値がある点は
3つある。

- BALTHASAR は `--sandbox read-only` で起動する。意見を求めるだけならファイル
  書き込みは不要なので、サンドボックスは閉じたままにしておく。
- BALTHASAR の末尾の `-` が、`codex exec` に標準入力からプロンプトを読ませる。
- 既定で `schema_args` を持つのは CASPER だけである。Grok は回答を JSON スキーマ
  で拘束できるため、回答不正による失敗をほぼ無くせる。他の2体はプロンプトの指示
  と、ホスト側の解析に頼る。

### Web 検索の権限

research モードの品質は、賢者が実際に Web を確認できるかで決まる。ヘッドレス時の
ツール利用の可否は CLI ごとに異なるため、既定設定にはそれを開くフラグを入れて
ある。以下は 2026-07-27 に実際の実行で確認した内容である。

- **MELCHIOR には `--allowedTools WebSearch WebFetch` が必要。** ヘッドレスの
  `claude -p` は明示的に許可されていないツールをすべて拒否する。この許可リストが
  無いと検索・取得・シェルの呼び出しがすべて拒否され、賢者は学習データだけで答え
  るか、確認できなかったと報告する。許可リストを付けると検索が動く。このフラグは
  ツール名の一覧を取るため、後続のフラグを飲み込まないよう `command` の末尾に置く。
- **BALTHASAR は追加のフラグ不要。** 検索は提供元のサーバー側で実行されるため、
  `--sandbox read-only` は妨げにならない。サンドボックスが制限するのはこのマシンの
  ファイルであり、モデル側のツールではない。検索が走ると
  `BALTHASAR.stderr` に `web search:` の行が出る。
- **CASPER には `--permission-mode auto` が必要。** これが無いと、答える人のいない
  ツール承認待ちで止まり、`stopReason: "Cancelled"` として途中終了する。使える
  回答は残らない。

CASPER は、要求した JSON オブジェクトの前に散文を1文置くことがある。ホストが
JSON 部分を抽出するため（`SKILL.md` の Step 5）これは失敗ではないが、`grok` 用の
アダプターを自分で書くときは起こるものとして扱うこと。

## 既定の賢者の導入と認証

2026-07-27 に macOS 上の `claude` 2.1.220 / `codex-cli` 0.145.0 / `grok` 0.2.112
で確認した。導入コマンドはフラグより頻繁に変わるので、失敗したら提供元の最新の
手順を確認すること。

### MELCHIOR — Claude Code (`claude`)

```bash
npm install -g @anthropic-ai/claude-code   # または: curl -fsSL https://claude.ai/install.sh | bash
claude                                     # 対話で1回サインインする
claude setup-token                         # 任意: ヘッドレス用の長期トークンを作る
```

### BALTHASAR — Codex CLI (`codex`)

```bash
npm install -g @openai/codex               # または: brew install codex
codex login                                # ブラウザでサインイン
codex login status                         # 状態を確認
```

ブラウザではなく API キーを使う場合:
`printenv OPENAI_API_KEY | codex login --with-api-key`。

### CASPER — Grok Build (`grok`)

```bash
grok login --device-auth                   # デバイスコード方式（別名: --device-code）
grok login --oauth                         # auth.x.ai でのブラウザ方式
```

`grok` は一部のデスクトップ環境に同梱されているため、個別に導入する前に
`command -v grok` を確認するとよい。xAI の無料プランではクォータが週単位のプール
になっており、使い切るとエラー応答として返る。ホストはそれを
「回答なし（エラー）」として記録し、2体で続行する。クォータのための特別扱いはし
ない。

## 賢者の差し替え: CASPER → Antigravity CLI (`agy`)

2026-07-27 に導入済みの `agy` で実機確認した。この CLI は既定の3体とは異なる形の
アダプターが必要になる。採用する前に理由まで読むことを勧める。

```json
{
  "name": "CASPER",
  "cli": "agy",
  "command": [
    "agy",
    "--add-dir", "{PROMPT_FILE}",
    "--print-timeout", "10m",
    "-p", "Read the file {PROMPT_FILE} and follow the instructions inside it exactly. Reply with only the JSON object it asks for: no prose, no code fence. Do not ask any questions."
  ],
  "extract": "raw",
  "notes": "Antigravity CLI. No stdin mode and no prompt-file flag, so the prompt path is passed in argv and agy reads the file itself; --add-dir grants read access to that one file. Plain-text output, no schema flag."
}
```

この形にしている理由:

- **`agy` は標準入力からプロンプトを読めない。** `-p`（別名 `--print`）は値を
  必須とする。`agy -p` だけでは "flag needs an argument" で失敗し、`agy -p -` は
  ハイフンをプロンプト本文として扱い「How can I help you today?」と答えた。
  よって `"input": "stdin"` は使えない。
- **`agy` に `--prompt-file` に相当するフラグは無い。** 問いを `-p` の値として
  渡すとプロンプト全文が argv に載り、`ps` から読めてしまう。設定の検査はこの形
  を拒否する。そこで argv にはパスと固定の指示文だけを載せ、ファイルの中身は
  `agy` 自身が読み取りツールで開く。問いの本文はプロセス一覧に現れない。
- **`--add-dir` は必須で、許可されるのは1ファイルだけである。** これが無いと
  ヘッドレスモードは `read_file` の権限要求を自動で拒否する。`{PROMPT_FILE}` を
  指定すると、そのファイルだけに読み取りが許可される（同じディレクトリにある別
  ファイルを読ませる試行は拒否された）。したがってこの賢者は、同じラウンド
  ディレクトリに置かれた他の賢者の回答を見られない。round1 の独立性は保たれる。
- **`extract: "raw"`。** JSON 封筒は無く、回答は stdout にプレーンテキストで届く。
  実機確認では、指示どおり JSON オブジェクトだけを返した。
- **`schema_args` は書かない。** `agy` に JSON スキーマのフラグは無いため、回答
  形式はプロンプトの指示だけに依存する。形式が壊れた回答は他の壊れた回答と同じ扱
  いで、ホストがその賢者を「回答なし（回答不正）」として記録し、縮退して続行する。
  同一ラウンド内での再送はしない（REQ-010）。
- **`--print-timeout` の既定は5分**で、`timeout_seconds` の600秒より短い。
  少なくとも `timeout_seconds` 以上に設定しないと、合議側の上限より先に `agy` が
  諦める。値は Go の duration 文字列（`10m`）で指定する。
- **この CLI の Web 検索可否は未検証。** `agy` がヘッドレスで Web 検索できるか、
  そのためにどの権限フラグが必要かは確認していない。research モードの合議に
  `agy` を座らせる前に確認すること。検索できない賢者も自信のある回答を返すが、
  その中身は学習データに依存している。

運用上の注意が1つある。**`agy` は回答を出せなかったときも exit 0 で終了する。**
読み取り権限を拒否した場合、通知文（"no output produced — a tool required the
read_file permission…"）を出して exit 0 するため、スクリプトはその通知文を回答と
して `status: "ok"` で記録する。ホストは回答が JSON として解析できないことで気付
く。`SKILL.md` の Step 5 の解析チェックを省略できないのはこのためである。
`CASPER.stdout` にこの通知文があれば、`--add-dir` が無いか、別の場所を指している。

## 設定変更の確認方法

```bash
# コマンドは存在するか、読まれた設定ファイルは意図したものか
MAGI_SAGES_FILE=./.magi/sages.json \
  references/scripts/magi-run.sh --out-dir /tmp/magi-check --preflight-only
```

`preflight.json` には実際に読み込んだ設定ファイルのパス（`sages_file`）が入る。
探索順が同梱既定ではなく自分の上書きを選んだことは、これで確認できる。構造上の
誤り（使えない `extract`、プロンプトを渡す手段が無い、`name` の重複など）は
exit 2 で停止し、問題点を一度にすべて列挙する。

新しいアダプターを実際の推論を使わずに試すには、
`references/scripts/tests/fixtures/` の設定をコピーし、決まった回答を echo する
シェルスクリプトを指すように書き換える。並列・タイムアウト・障害の経路は
`references/scripts/tests/run-tests.sh` がこの方法で検証している。
