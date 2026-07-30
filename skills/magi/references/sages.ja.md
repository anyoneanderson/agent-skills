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
| `timeout_seconds` | 正の整数 | 賢者1体あたりの実時間の上限。既定は 600（10分）。`--timeout <秒>` は実行ごとに上書きし、有効値は `preflight.json` に記録される |
| `sages` | 配列（1〜3件） | 賢者の一覧。`summary.json` の行と結果マトリクスの行はこの順に並ぶ |

上限は3体である。`SKILL.md` の採決規則は3体（縮退時は2体）を前提に組んであるた
め、4体を書いた設定は採決方法を黙って変えるのではなく exit 2 で停止する。

2体の構成は受け付けるが、何も欠けていなくてもそれは縮退合議である。
`preflight.json` は `missing` を空のまま `available_count: 2` と報告する。
ホストは送信前にユーザーへ確認し、2体の規則（2対0で可決、1対1は討論1ラウンド
のみ）を適用する。1体の構成はこの時点でホストが中止する。1体は合議ではない。

runner は賢者ごとに別のプロセスグループを作る。有効なタイムアウトを超えると、
そのグループへ TERM を送り、短い上限付き猶予の後も残っていれば KILL を送り、終了
コード `142` を記録する。他の賢者グループは継続する。意図的にグループを離れた
子孫プロセスはこの保証の対象外である。

## 賢者ごとのフィールド

| フィールド | 必須 | 意味 |
|---|---|---|
| `name` | はい | 表示名（例: `MELCHIOR`）。実行ディレクトリのファイル名になるため、使える文字は `A-Z a-z 0-9 _ -` のみ。重複不可 |
| `cli` | はい | preflight が `command -v` で存在確認するコマンド名。欠落時に報告される名前であり、マトリクスで賢者名に併記される名前でもある |
| `command` | はい | 文字列の非空配列。シェルを介さず argv としてそのまま実行される |
| `isolation_args` | いいえ | 文字列の配列。`--confidential` のときだけ `command` の後ろへ追加する。既定のツール範囲を変えずに機密モードの制限を定義する |
| `input` | いいえ | `"stdin"` を指定すると、プロンプトファイルを標準入力へリダイレクトして渡す。省略すると `{PROMPT_FILE}` でパスを渡す。他の値は受け付けない |
| `extract` | はい | 回答本文の取り出し方。jq フィルタ / `"answer-file"` / `"raw"`（後述） |
| `schema_args` | いいえ | 文字列の配列。`--schema-file` を渡した実行のときだけ `command` の後ろに追加される |
| `notes` | いいえ | 次に設定を読む人向けの自由記述。スクリプトは無視する |

### コマンド配列のプレースホルダー

`command`、`isolation_args`、`schema_args` の配列要素ごとに置換し、シェルを
通さない。空白や `&` を含むパスが構文として再解釈されることはない。

| プレースホルダー | 置換される内容 |
|---|---|
| `{PROMPT_FILE}` | このラウンドでこの賢者へ送るプロンプトファイルの絶対パス |
| `{ANSWER_FILE}` | CLI が最終回答を書き出すことをスクリプトが期待するパス |
| `{SCHEMA}` | `--schema-file` で渡したファイルの全文 |
| `{MAGI_SCRIPTS_DIR}` | `magi-run.sh` が置かれたディレクトリの絶対パス。導入先のパスを設定に焼き付けずに、隣に同梱されたラッパーを起動するために使う |

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
      "command": ["claude", "-p", "--output-format", "json"],
      "isolation_args": ["--allowedTools", "WebSearch", "WebFetch"],
      "input": "stdin",
      "extract": ".result"
    },
    {
      "name": "BALTHASAR",
      "cli": "codex",
      "command": ["{MAGI_SCRIPTS_DIR}/codex-sage.sh", "--sandbox", "read-only", "--output-last-message", "{ANSWER_FILE}", "-"],
      "isolation_args": ["--confidential"],
      "input": "stdin",
      "extract": "answer-file"
    },
    {
      "name": "CASPER",
      "cli": "grok",
      "command": ["grok", "--prompt-file", "{PROMPT_FILE}", "--output-format", "json", "--permission-mode", "auto"],
      "isolation_args": ["--tools", "web_search,web_fetch", "--deny", "MCPTool(*)"],
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
  `codex` を直接ではなく同梱の `codex-sage.sh` 経由で起動している理由は次節にある。
- 既定で `schema_args` を持つのは CASPER だけである。Grok は回答を JSON スキーマ
  で拘束できるため、回答不正による失敗をほぼ無くせる。他の2体はプロンプトの指示
  と、ホスト側の解析に頼る。

### Web 検索の権限

research モードの品質は、賢者が実際に Web を確認できるかで決まる。既定のツール
範囲では利用者が設定したツールを保ち、機密モードでは次の Web 専用制限を適用する。
以下は 2026-07-27 に実際の実行で確認した内容である。

- **MELCHIOR には `--allowedTools WebSearch WebFetch` が必要。** ヘッドレスの
  `claude -p` は明示的に許可されていないツールをすべて拒否する。この許可リストが
  無いと検索・取得・シェルの呼び出しがすべて拒否され、賢者は学習データだけで答え
  るか、確認できなかったと報告する。許可リストを付けると検索が動く。このフラグは
  ツール名の一覧を取るため、後続のフラグを飲み込まないよう `isolation_args` の末尾に置く。
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

### 既定と機密モードのツール範囲

既定のツール範囲は、利用者が設定したツールを意図的に引き継ぐ。そのため問いは3社
の賢者提供元に加え、設定済みの MCP や拡張ツールの提供元へ届くことがある。ホストは
送信前にこれを告知する。`--confidential` は `isolation_args` を追加し、同梱の3体を
Anthropic、OpenAI、xAI に限定する。以下は 2026-07-27 に実測した制限である。

| 賢者 | MCP・プラグイン系ツールの遮断方法 | 残る部分 |
|---|---|---|
| MELCHIOR | `--allowedTools WebSearch WebFetch` は許可リストなので、MCP ツールはそこに載らない | 観測された残余はない。MCP の呼び出しも他の未許可ツールと同様に拒否される |
| BALTHASAR | 同梱の `codex-sage.sh` ラッパー（後述） | 残余なし。サーバー自体がツール登録から消える |
| CASPER | `--tools web_search,web_fetch` で組み込みツールを絞り、`--deny 'MCPTool(*)'` で MCP 呼び出しを拒否する | MCP ツールのスキーマ一覧はモデルに見えたままで、呼び出しだけが `Denied by permission policy: deny rule on mcp` で拒否される |

#### `codex-sage.sh`

`--confidential` が無いとき、ラッパーは受け取った引数を `codex exec` へそのまま
渡し、設定済みツールを保つ。機密モードでは「MCP を全部止める」1つのフラグが無い
ため、次の2つの手段で遮断を分担する。

- `--disable plugins --disable apps` は、プラグインとアプリが供給するサーバーを
  受け持つ。これらは個別に止められない。`-c mcp_servers.<name>.enabled=false` を
  当てると、無効化ではなく `invalid transport` で失敗する。
- `-c mcp_servers.<name>.enabled=false` は、利用者が設定したサーバーを受け持ち、
  名前ごとに1組ずつ生成する。

**サーバーの一覧は `config.toml` を読むのではなく
`codex mcp list --json --disable plugins` から得ている。** これは見た目より重要
である。TOML は同じサーバーを何通りにも書ける。`[mcp_servers.<name>]` ヘッダー、
`[mcp_servers]` 直下のインラインテーブル、`mcp_servers.<name>.command` のドット
記法、インデントされたヘッダーなどである。手書きのパーサーはこのうちいくつかを
黙って取りこぼし、取りこぼされたサーバーは有効なまま残る。codex に尋ねれば codex
自身の設定読み込みを使うことになり、プロジェクト単位の設定や移動された
`$CODEX_HOME` のように、ラッパーが見ていない設定もカバーされる。一覧の呼び出しに
`--disable plugins` を付けることでプラグイン由来のサーバーが結果から外れ、返って
くる名前はすべて `-c` で実際に止められるものになる。

codex-cli 0.145.0 では、これでツール登録数が 141 から 19 に減り、MCP 由来の
ツールは1つも残らず、それらのサーバーのツールを名指しした問いには
「no such tool is registered」と返った。

アダプターは `command[0]` をラッパーにしつつ `"cli": "codex"` のままにしている。
preflight が報告すべきなのは利用者が導入する必要のある CLI であり、それは
`codex` 本体だからである。

**機密モードには codex-cli 0.145.0 以上が必要**で、`mcp list --json` と `--disable`
を検証したのがこのリリースである。これより古い codex は未知のフラグを拒否するため、
機密モードでは BALTHASAR が「回答なし」として記録される。既定のツール範囲では
この検査を行わない。機密モードだけ失敗するときは `codex --version` を確認すること。

このラッパーは、次の3つの場合に **exit 2 でフェイルクローズする。** いずれも
「遮断すべきサーバーの集合を確定できなかった」状態である。

- 一覧の呼び出しが失敗した場合。codex 自身のメッセージは停止の通知と並んで stderr
  に残る。古いリリースで未知のフラグを拒否されたときのエラーはここに出る。
- 一覧が `name` を持つオブジェクトの配列でない場合。
- 名前が空、または `[A-Za-z0-9_-]` 以外を含む場合。ドット記法の `-c` パスに変換
  できないためである。そのサーバーを改名するか削除すること。なお、そうした名前を
  読み飛ばして残りを無効化することはしない。読み飛ばしは、賢者が正常に見えたまま
  1つのサーバーだけ有効に残るという、まさにその事故の起こし方である。

これらのフェイルクローズ検査は機密モードでのみ動く。いずれの場合も BALTHASAR は
「回答なし（エラー）」として現れ、理由は
`BALTHASAR.stderr` に残り、問いは送信されない。失敗した賢者は取り戻せるが、告知して
いない提供元へ送られた問いは取り戻せない。

#### 既知の制約: 無効化リストは起動時のスナップショットである

無効化リストは `codex exec` を起動する直前に1回だけ作る。その短い間に codex の設定
が変わった場合（別の端末での `codex mcp add`、エディタによる `config.toml` の保存
など）、そこで追加されたサーバーは一覧に含まれず、したがって無効化されない。
**合議の実行中に codex の MCP 設定を変更しないこと。**

これは事故を防ぐための注意であり、悪意ある同時変更への防御ではない。実行中にその
設定を書き換えられる主体は、賢者の設定やこのラッパー自体も同様に書き換えられる。
したがってこの時間差をセキュリティ境界として扱うのは誤りである。それでも記載する
のは、実行中にサーバーを追加してしまうのは十分あり得る操作ミスであり、遮断が何を
カバーしていないかは読み手が知っておくべきことだからである。

**賢者を差し替えるときは、機密モードを自分で定義する。** 設定の検査が確認するのは
`isolation_args` の構造であり、ツール権限ではない。許可リストまたは拒否フラグと
プラグイン停止方法を調べ、`--confidential` で外部ツールを呼べないことを実行確認し、
結果をアダプターの `notes` に書き残すこと。

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

**0.145.0 は機密モードの最低条件である。** 同梱の `codex-sage.sh` は遮断時に
`mcp list --json` と `--disable` を必要とし、それが無い環境では実行を続けない。

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
- **この CLI の Web 検索可否とツール遮断は未検証。** `agy` がヘッドレスで Web 検索
  できるか、そのためにどの権限フラグが必要か、MCP や拡張のツールをどう遮断するかは
  いずれも確認していない。`agy` を座らせる前に両方を確認すること。検索できない賢者
  も自信のある回答を返すが中身は学習データに依存しており、利用者の MCP ツールに
  届く賢者は前述の提供元の境界を破る。`--add-dir` によるファイル読み取りの制限は、
  ネットワーク系ツールについての根拠にはならない。

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
