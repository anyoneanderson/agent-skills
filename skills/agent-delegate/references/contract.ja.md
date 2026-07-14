# agent-delegate — スクリプト契約

この文書は `references/scripts/agent-delegate.sh` の公開インターフェースです。他の
スキルや自動化はこの契約に依存し、`SKILL.md` を経由せずスクリプトを
直接実行します。正はスクリプトの現在の実装であり、この文書はそれを追随します。引数や
`report.json` スキーマの変更は契約変更であり、必ずこの文書に反映してください。

English version: [contract.md](contract.md)

## 実行方法

```bash
agent-delegate.sh --mode <delegate|review> --prompt-file <path> --out-dir <path> [options]
```

プロンプトは **stdin**（`--prompt-file` の内容を読み込んで渡す）で渡します。エスケープと
長さ制限の事故を避けるため、コマンドライン引数では渡しません。

### 引数

| フラグ | 必須 | 既定 | 意味 |
|---|---|---|---|
| `--mode <delegate\|review>` | ○ | — | `delegate` はタスク委譲、`review` は読み取り専用の敵対的レビュー |
| `--prompt-file <path>` | ○ | — | stdin として相手に渡すファイル |
| `--out-dir <path>` | ○ | — | 成果物（report・ログ・レビューファイル）の出力先 |
| `--label <slug>` | — | `<mode>-<epoch>` | 成果物ファイル名の接頭辞 |
| `--target <codex\|claude>` | — | 自動判定 | 起動する相手 CLI（下記「ターゲット解決」） |
| `--resume <thread_id>` | — | — | 前セッションを継続（下記「resume」） |
| `--model <name>` | — | CLI 既定 | 相手に渡すモデル（codex resume では無視） |
| `--effort <level>` | — | — | 推論の effort。codex のみ。codex resume では無視 |
| `--sandbox <stage>` | — | `full-access` | `full-access` / `workspace-write` / `read-only`。review では無視され常に read-only |
| `--review-output <path>` | — | `<out-dir>/<label>-review.md` | 生成したレビューファイルの出力先（review モード） |
| `--detach` | — | off | デタッチ実行して即座に戻る（下記「detach」） |
| `--force` | — | off | 同一 label の既存 pid/report を上書き |
| `-h`, `--help` | — | — | usage を stdout に出力して exit 0 |

### 終了コード

| コード | 意味 |
|---|---|
| `0` | 終端状態まで実行した。成功（`done`）か失敗（`blocked`）かは `report.json` の `status` を読む。 |
| `2` | 相手を起動する前の前提エラー（引数不正・ターゲット解決不能・相手 CLI 不在・codex workspace 未信頼・resume 検証失敗）。exit 2 のとき `report.json` は生成されない。 |

### stdout 契約

正常に起動すると、確定した run id と report パスを次の順序で出力する。

```text
run_id: 19235118-80D0-4DCD-94E0-2E38C42AB5F2
/absolute/out/label-report.json
```

**stdout の最終行が `report.json` の絶対パスである契約は変わらない。**
最終行だけを使う既存の呼び出し元はそのまま動く。
detach の呼び出し元は `run_id:` の値も expected run として保存し、launcher が戻ったローカル時刻を記録する。
出力されたパスに report がまだ存在しない場合がある。

## ターゲット解決

スクリプトは *相手側* の CLI を起動する。順序は次のとおり:

1. `--target <codex|claude>` が指定されていればそれ。
2. `AGENT_DELEGATE_HOST` 環境変数（`claude` → ターゲット codex、`codex` → ターゲット claude）。
3. `CLAUDECODE` が設定済み → Claude Code 配下 → ターゲット **codex**。
4. Codex 実行時のマーカー（`CODEX_SANDBOX` / `CODEX_SANDBOX_NETWORK_DISABLED` / `CODEX_HOME`）→ ターゲット **claude**。
5. いずれも該当しなければ exit 2 で `--target` を要求。

解決した方向（`claude->codex` / `codex->claude`）は `report.json` の `meta.direction` に記録される。

**入れ子連鎖の注意.** エージェント連鎖（例: Claude Code → `codex exec` → 本スクリプト）
では、親の `CLAUDECODE` / `CODEX_*` が子シェルに継承されるため、環境変数による自己判定は
信頼できない。**プログラム利用（他スキル・パイプラインからの呼び出し）では `--target` を
必ず明示すること。** 自己判定は単一エージェントの対話利用向けの便宜にすぎない。

実測のマーカー（2026-07-03、codex-cli 0.142.5）: Codex 実行シェルには
`CODEX_SANDBOX`（例: `seatbelt`）/ `CODEX_SANDBOX_NETWORK_DISABLED=1` / `CODEX_THREAD_ID`
が環境に注入される。

## サンドボックス段階

優先順位: `--sandbox` フラグ > `AGENT_DELEGATE_SANDBOX` 環境変数 > 既定 `full-access`。
review モードはこれらを無視して常に `read-only`。

| 段階 | codex exec | claude -p |
|---|---|---|
| `full-access` | `--sandbox danger-full-access` | `--permission-mode bypassPermissions` |
| `workspace-write` | `--sandbox workspace-write` | `--permission-mode acceptEdits` |
| `read-only` | `--sandbox read-only` | `--permission-mode plan` + `--disallowedTools Write,Edit,NotebookEdit,Bash` |

**保証水準は方向で異なる。** codex 方向の `read-only` はカーネルレベルのファイルシステム
サンドボックス。claude 方向の `plan` はポリシーレベルの制御で、ツール無効化もアプリケーション
レベルのブロックであり、OS が強制する書き込み防止はない。codex `read-only` は強い保証、
claude `read-only` はベストエフォートのポリシーとして扱うこと。

## report.json スキーマ

アトミックに書き込まれる（`.tmp` に書いてから `mv`）。
expected run の valid terminal report が完了結果の正である。
detach の実行中は `report.json` が存在しなくても失敗ではないため、待機中は後述の heartbeat とプロセス状態を使う。

```json
{
  "status": "done | blocked",
  "summary": "相手の最終メッセージ先頭の非空行（200字まで）",
  "touchedFiles": ["リポジトリルート相対のパス.ts"],
  "blocker": null,
  "blocker_category": null,
  "thread_id": "abc-123 | unknown",
  "artifacts": {
    "last_message": "<out-dir>/<label>-last.txt",
    "stdout": "<out-dir>/<label>-stdout.jsonl | .json",
    "stderr": "<out-dir>/<label>-stderr.log",
    "review_file": "<out-dir>/<label>-review.md"
  },
  "meta": {
    "run_id": "uuid またはナノ秒タイムスタンプ",
    "mode": "delegate | review",
    "direction": "claude->codex | codex->claude",
    "sandbox": "full-access | workspace-write | read-only",
    "model": "gpt-5.4 | null",
    "resumed": false,
    "ts": "2026-07-03T00:00:00Z"
  }
}
```

- `touchedFiles` は git スナップショット（実行前後の
  `git ls-files --full-name -m -o --exclude-standard` をリポジトリルート相対で比較）から
  スクリプトが算出する。相手の自己申告は使わない。`--out-dir` 配下の自身の成果物は除外。
  git リポジトリ外では空 + 警告（delegate は status=done のまま縮退）。
- `blocker` は失敗時、相手 stderr の末尾20行。成功時は `null`。
- `artifacts.review_file` は review モードのみ存在。

### blocker_category

失敗の機械分類（成功時は `null`）。呼び出し元は `blocker` 本文から再分類してもよい。

| 分類 | 意味 |
|---|---|
| `malformed_output` | レビュー出力が4点の構造検証に失敗（下記「review モード」） |
| `tool_unavailable` | 相手 CLI 不在・未インストール（stderr が一致） |
| `timeout` | 相手のタイムアウト（stderr 一致、または exit code 124/137） |
| `sandbox_violation` | `read-only` のレビューが、自身の成果物を除外してもファイルを変更した |
| `env_error` | report を生成せずに終了した実行。同期/worker のセーフティネット、または detach の監視ラッパーが合成する |
| `unclassified` | パターン不一致の非0終了 |

## detach の運転記録

detach は report と同じディレクトリへローカル運転記録を公開する。
運転記録は診断と所有権のためのデータであり、`report.json` にフィールドを追加しない。

### heartbeat

monitor は worker の実行中、30秒ごとに `<out-dir>/<label>-heartbeat.json` をアトミックに置き換える。
`last_beat` が現在時刻から90秒以内なら heartbeat は新鮮である。

```json
{
  "run_id": "19235118-80D0-4DCD-94E0-2E38C42AB5F2",
  "state": "running | done | blocked",
  "pid": 303,
  "monitor_pid": 202,
  "started_at": "2026-07-14T00:00:00Z",
  "last_beat": "2026-07-14T00:00:30Z",
  "target": "codex | claude",
  "mode": "delegate | review",
  "report_path": "/absolute/out/label-report.json"
}
```

`pid` は Bash worker の PID、`monitor_pid` は detach monitor の PID である。
`monitor_pid` は `<out-dir>/<label>.pid` の先頭にある `pid:` と一致する。
`started_at` と `last_beat` は UTC RFC 3339 形式を使う。
monitor は同じ run id の valid terminal report を公開した後に限り `done` または `blocked` を公開し、heartbeat の更新を止める。
terminal heartbeat は、同じ label の次の run が所有権を得るまで残る。

### owner と handoff

`<out-dir>/<label>-owner.json` は共有 report、heartbeat、pid の所有権 token である。
`<out-dir>/<label>-owner.lock/` は所有権の変更と lease の更新を直列化する。

```json
{
  "run_id": "19235118-80D0-4DCD-94E0-2E38C42AB5F2",
  "run_kind": "detach",
  "runner_pid": 202,
  "launcher_pid": 101,
  "monitor_pid": 202,
  "worker_pid": 303,
  "started_at": "2026-07-14T00:00:00Z",
  "lease_at": "2026-07-14T00:00:30Z",
  "handoff_dir": "/tmp/agent-delegate-handoff.101.random",
  "handoff_phase": "verified"
}
```

`run_kind` は `sync` または `detach` である。
対応するプロセスや handoff が存在しない場合、PID と handoff のフィールドは null になる。
`handoff_phase` は `not_applicable`、`not_started`、`committed`、`verified` のいずれかである。
detach owner の値は診断用 mirror であり、worker の起動可否は `<handoff_dir>/handoff-sentinel.json` に永続化した `handoff_phase` で決める。
monitor は handoff FIFO を作る前に完全な owner と pid を公開する。
heartbeat を公開するたびに、monitor は同じ owner lock 区間で `lease_at` も更新する。
launcher は owner と pid の run id と monitor PID が一致した後にだけ、owner の `run_id` を expected run として採用する。
launcher はその値を出力し、呼び出し側は sentinel から expected run を導出しない。

同じ label の次回起動では、preflight stale-reaper が放棄済みの handoff を検査する。
owner と pid が同じ不在 monitor を指し、lease が90秒より古い場合に限り削除候補とする。
handoff のパスは設定 root の直下にある非 symlink の mode 0700 ディレクトリであり、実行ユーザーが所有し、basename の launcher PID と device/inode が検査中に変わらないことを要求する。
sentinel があれば JSON の識別情報も一致しなければならない。
列挙済みの FIFO、一致する一時ファイル、sentinel だけを削除でき、未知の項目や不一致があれば保持して診断を残す。
terminal report と terminal heartbeat は残す。

## review モード

- 常に `read-only`。レビュワー自身はファイルを書けないため、構造化レビューファイル
  （形式は下記で検証）全文を **最終メッセージ**として出力し、スクリプトがそれを `--review-output` に書き出す。
- 相手に送るプロンプトは `adversarial-review-prompt.md`（`AGENT_DELEGATE_REVIEW_LANG=ja`
  なら `.ja.md`）に、呼び出し元の `--prompt-file`（レビュー対象の文脈: 差分・仕様書パス・観点）を連結したもの。
- 最終メッセージを4点で検証する。いずれか欠落で `status: blocked` /
  `blocker_category: malformed_output`（欠落項目を `blocker` に列挙）:
  1. `type: review` ヘッダー行、
  2. `## Meta` セクション、
  3. `### Critical`・`### Improvement`・`### Minor` を持つ `## Findings` セクション、
  4. `Gate: PASS|FAIL` 行を持つ `## Summary` セクション。
- read-only 実行なのにファイルを変更していた場合（自身の成果物を除外後）:
  `status: blocked` / `blocker_category: sandbox_violation`。
- レビューファイルの形式（severity 区分 + finding ごとの `fix_before` タグ + Gate）は安定した機械可読フォーマットであり、後段のツールがそのまま取り込める。Gate は `fix_before` だけから導く — ゲートを止める段階（有効な段階一覧の先頭。既定の一覧では `implementation`）の finding が1件でもあれば FAIL（`adversarial-review-prompt.ja.md` 参照）。
- 構造検査が確認するのはセクション等の**存在**だけで、`fix_before` の値や Gate 行と findings の一致は検証しない。消費側はまず Critical / Improvement の全 finding が、有効な段階一覧 — 既定の4値、または呼び出し側がレビュー文脈で渡した順序付き一覧 — に含まれる `fix_before` 値を持つことを検証し（タグの欠落・一覧外の値は形式不正 — その状態で Gate を計算しない。タグ無しの Critical が黙って PASS になるため）、そのうえでタグから Gate を再集計し（一覧の先頭 = ゲートを止める段階の finding が1件でもあれば FAIL）、不一致は安全側（不合格扱い）に倒すこと。

## resume

`--resume <thread_id>` で前セッションを継続する。

- `thread_id` の取得元: codex は `thread.started` イベントの `.thread_id` のみ（後続
  イベントは `item_*` を返すため無視）。claude は結果 JSON の `.session_id`。取得失敗時は `"unknown"`。
- `--resume unknown` → exit 2。
- codex resume は `codex exec resume <id> --json --output-last-message <file>` のみを使う。
  `--sandbox` / `--model` / `-c`（effort）は受け付けない（sandbox・model はセッション作成時に
  固定）。codex resume での `--effort` は警告つきで無視。
- スクリプトは要求サンドボックスと、前ラウンド report（`<out-dir>/<label>-report.json`）の
  `meta.sandbox` を照合する。不一致は exit 2（権限を変えたい場合は新規セッションを作る）。
  review の resume は、前セッションが `read-only` であることも要求する。

## detach

`--detach` は OS デタッチの監視プロセス配下で相手を実行し、呼び出し元を host command の実行上限から切り離す。

- 前提チェック（引数・相手 CLI 存在・codex trust）は同期的に行い、失敗はデタッチ前に exit 2。
- 成功時は monitor を独立した process group で起動する。
  monitor が owner と pid を公開し、永続化した handoff を完了してから、worker を1回だけ起動できる。
  launcher は run id と将来の report パスを出力して exit 0 で戻る。
- ラッパーは相手完了時に `report.json` をアトミックに書く。相手が report を書かずに殺された
  場合は、ラッパー自身が `blocked` の report（`blocker_category: env_error`）を合成する。
  呼び出し元にスキーマ再実装をさせない。

### ポーリングと expected run の状態

detach 起動時に `expected_run_id`、`report_path`、`launched_at` を保存する。
15秒間隔を標準とし、30秒を超えない周期で次の順序を繰り返す。

1. report を読む。
   valid JSON であり、`status` が `done` または `blocked`、`meta.run_id` が `expected_run_id` と一致する場合だけ終了する。
2. owner と pid を読む。
   owner が別の run へ移っていれば `SUPERSEDED` とする。
3. heartbeat を読む。
   新しいファイルを一時的に読めない場合は、最後の valid heartbeat を保持する。
4. worker PID と monitor PID を確認する。
   permission error は不在ではなく生存不明として扱う。
5. `DEATH_CANDIDATE` では30秒待ち、次の周期も report の確認から始める。

| 観測 | 呼び出し側の状態 |
|---|---|
| expected run の valid report が `done` または `blocked` | `TERMINAL_DONE` または `TERMINAL_BLOCKED` |
| owner が別の run | `SUPERSEDED` |
| monitor が不在、worker が生存または不明 | `ORPHANED_WORKER` |
| worker が不在、monitor が生存または不明 | `FINALIZING` |
| worker と monitor が不在 | `DEATH_CANDIDATE`。30秒後も同じなら `DEAD` |
| report の JSON、status、run id が不正でプロセスが残る | `REPORT_INVALID_PENDING` |
| heartbeat が未生成、monitor が生存、起動から90秒以内 | `STARTING` |
| 起動から90秒を超えて heartbeat が未生成、monitor が生存 | `DEGRADED_NO_HEARTBEAT` |
| heartbeat が一時的に読取不能、プロセスが生存または不明 | `DEGRADED_UNREADABLE` |
| heartbeat が新鮮、プロセスが生存または不明 | `RUNNING` |
| heartbeat が90秒より古く、プロセスが生存または不明 | `DEGRADED_STALE` |

terminal report の検証を heartbeat と PID の状態より優先する。
terminal heartbeat は不正または欠落した report の代わりにならない。
`RUNNING`、すべての `DEGRADED_*`、`ORPHANED_WORKER`、`FINALIZING`、`REPORT_INVALID_PENDING` は待機状態であり、失敗ではない。

### 同期 / detach の使い分け

- ファイル変更、仕様の生成や修正、コード実装、テスト証跡の保存を伴う delegate は、明示的な `--detach` を既定とする。
- 同期実行は、読み取り専用であり、5分以内に終わる具体的な根拠がある review、調査、短い delegate に限る。
- 書き込みを伴う場合、または5分以内という根拠がない場合は `--detach` を使う。
- 呼び出し側が設ける自前タイムアウトは、仕様生成と仕様修正で20分以上、実装と E2E で30分以上とする。
  到達時は状態を再評価し、report の不在だけで失敗にしない。

CLI の互換性は維持する。
`--detach` を省略すると従来どおり同期実行になるため、上記の既定はスクリプト内部の自動切替ではなく呼び出し側の規約である。

## 環境変数

| 変数 | 効果 |
|---|---|
| `AGENT_DELEGATE_SANDBOX` | `--sandbox` 省略時の既定サンドボックス段階 |
| `AGENT_DELEGATE_HOST` | ターゲット解決の host 側を強制（`claude`/`codex`） |
| `AGENT_DELEGATE_REVIEW_LANG` | `ja` で日本語のレビューテンプレートを選択 |
| `AGENT_DELEGATE_TEST_MODE` | `1` は CLI を起動せず引数を解決し plan 行を出力して exit 0。`heartbeat` は peer CLI を起動せず、追跡済み harness で detach handoff、owner、heartbeat、terminal publication を検証 |

## エラーメッセージ

エラーは stderr に `agent-delegate:` 接頭辞つきで出力される。代表的な前提エラー（すべて exit 2）:

- `missing --mode` / `missing --prompt-file` / `missing --out-dir`
- `invalid --mode '<x>' (expected delegate|review)`
- `invalid --target '<x>' (expected codex|claude)`
- `cannot self-detect host CLI; pass --target <codex|claude> (or set AGENT_DELEGATE_HOST)`
- `prompt file not found: <path>`
- `codex CLI not found; install Codex CLI and ensure 'codex' is on PATH`
- `codex workspace trust_level must be 'trusted' (workspace=<dir>, found=<level>)`
- `cannot resume: thread_id is 'unknown' ...`
- `resume sandbox mismatch: session was created with '<a>' but '<b>' was requested; ...`
- `review resume requires a read-only session; prior session sandbox was '<x>'`
- `a run for label '<label>' is already tracked at <pid> (use --force to override)`
- `a report already exists for label '<label>' at <path> (use --force to overwrite or --resume to continue)`

非致命の警告（stderr）には、git リポジトリ外の実行、codex resume での `--effort` 無視、
read-only レビューがファイルを変更した場合が含まれる。
