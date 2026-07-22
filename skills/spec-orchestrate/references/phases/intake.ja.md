# フェーズ: intake

入ってきた要求（manual の対話 / auto の Issue）を、仕様ディレクトリと初期 state
ファイルに変換する。オーケストレーターが入力を集める唯一のフェーズであり、以降の
フェーズは人ではなく state を読む。

## 入力

- モード（`manual` / `auto`）。auto では `--issue <N>` 番号。
- `pipeline.yml`（roles + アプリ起動レシピ）があれば。なければ既定 roles。
- 呼び出し言語（要求から検出し state に記録）。

## アクション

**manual:**
1. 作業ディレクトリが git リポジトリであることを確認。`gh auth` はここでは **不要**
   — manual は Issue を取得しない。`gh` が最初に要るのは pr フェーズ。
2. 自然言語の要求を spec-generator の対話モードに引き渡す。人との対話は planner の
   実行内で起こる — オーケストレーター自身は planner の起動以上に利用者へ質問しない。
3. feature 名はその対話で確定し、`.specs/{feature}/` ディレクトリ名になる。

**auto:**
1. git リポジトリと `gh auth` を確認（auto は Issue を取得するため `gh` の認証が
   ここで必要）。
2. Issue を取得:
   ```bash
   gh issue view <N> --json title,body,labels
   ```
3. JSON を無対話の planner 入力に整形する（title + body を要求、labels をヒント）。
   auto モードでは AskUserQuestion を一切呼ばない。
4. feature 名を Issue タイトルから kebab-case で導出する。

**両モード共通 — 運転記録の `.gitignore`:**

`.specs/.gitignore` が運転記録を除外するようにする。`.specs/` を追跡している
プロジェクトでも運転記録をコミットしないためのもの。ファイルが無ければ、以下の内容
そのままで作成する。あれば、不足しているパターンのみ追記する — 既存行は変更・削除
しない（プロジェクトが1行を削って意図的にある記録を戻している場合がある）。

```
# spec-orchestrate run records — local only (see spec-orchestrate references/pipeline-config.md)
# Delete lines here if your project intentionally commits run records.
pipeline-metrics.jsonl
.orchestrate-active.json
*/pipeline-state.json
*/inspection-report.md
*/.inspection_result.json
*/review-*.md
*/evaluate-*.md
*/evidence/
*/retrospective.md
# agent-delegate runtime artifacts when .specs/{feature} is the --out-dir
*/*-report.json
*/*-heartbeat.json
*/*-owner.json
*/*-owner.lock/
*/*-report.candidate.*.json
*/*-last.txt
*/*-stdout.jsonl
*/*-stderr.log
*/*.pid
```

初期stateを書く前に`run_id`を1回だけ生成する。ISO 8601 UTC timestampとrandom suffixを
組み合わせる（例: `2026-07-03T00:00:00Z-a1b2c3d4`）。これは論理runの識別子なので、
crash recoveryと以後のすべてのresumeで同じ値を保持する。

## 出力

- 確定した書き込み可能な `.specs/{feature}/` ディレクトリパス。
- 初期 `pipeline-state.json`（state 更新を参照）。
- 運転記録を除外する `.specs/.gitignore`（新規作成または追記）。
- auto: Issue から導いた整形済みの無対話 planner 入力。

## 検証

- `.specs/{feature}/` のパスが決まり、書き込み可能である。
- `.specs/.gitignore` が存在し、上記の運転記録パターンを含む。
- auto: Issue が存在し取得できた（title/body が非空）。`gh` の認証/不在エラー時は
  §エラー処理に従いここで停止する。

## state 更新

初期 `pipeline-state.json` を書く:
```json
{ "feature": "<name>", "run_id": "<UTC timestamp>-<random suffix>",
  "mode": "manual|auto", "issue": <N|null>,
  "language": "en|ja", "host_runtime": "claude|codex", "phase": "spec_generate",
  "completed_phases": ["intake"], "rounds": {}, "threads": {},
  "role_overrides": {}, "review_fallbacks": [], "arbitrations": [] }
```
詳細スキーマと jq/awk の書き込み流儀は `../pipeline-config.ja.md` にある。intake は
spec_generate に入るのに必要な最小限を書く。`host_runtime` は現在の runtime から
明示的に確定する。不明なら state を書く前に `../role-dispatch.ja.md` Step 0 の
manual / auto フォールバックを適用する。既存stateがあるときは`run_id`を再生成しない。

## 遷移

- manual: 対話完了 → **spec_generate**
- auto: Issue 取得・整形完了 → **spec_generate**
