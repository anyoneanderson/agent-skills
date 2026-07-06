# パイプライン設定と状態 — pipeline.yml と pipeline-state.json

オーケストレーターは2つのデータファイルを持つ: `pipeline.yml`（静的設定、リポジトリ
に1つ）と `pipeline-state.json`（実行中の状態、機能ごとに1つ）。このファイルは両者と、
起動時に状態を読む再開動作を規定する。

既定の `pipeline.yml` は spec-workflow-init が生成できる（その
`references/pipeline-yml-template.ja.md` を参照）。ファイルが無くてもオーケストレーター
は組み込みの既定値で動く。

English version: [pipeline-config.md](pipeline-config.md)

## pipeline.yml

配置: `.specs/pipeline.yml`（リポジトリに1つ）。不在時は下記の既定が適用され、`app`
は空（起動レシピなし）、`limits` は既定値になる。

```yaml
roles:
  spec_author: claude
  spec_reviewer: codex
  impl_ui: claude
  impl_backend: codex
  impl_test: codex
  e2e_runner: claude
app:                      # spec-evaluate の起動レシピ（UI 項目がある場合のみ必須）
  start: "npm run dev"
  url: "http://localhost:3000"
  ready_pattern: "ready in"
  stop: "auto"            # auto = 起動プロセスを kill。それ以外は停止コマンド
  auth: none              # none | 認証手順を書いた references パス
limits:
  role_swap_max: 1        # auto 裁定でのロール入れ替え上限（stall-detection.ja.md 参照）
improve:                  # retrospective 自動改善 — improve-apply.ja.md 参照
  skills_repo: "~/Documents/zenchaine/agent-skills"
  auto_apply: true
  line_budget: 300
```

- **roles**: 各値は `claude` か `codex`。`role-dispatch.ja.md` が消費する。
- **app**: spec-evaluate が使う起動レシピ。`test.md` の項目が `playwright` を使う
  ときのみ必須。`playwright` 項目があるのに `app` が欠落・不完全な場合はモードで
  分ける:
  - manual: 警告して人に確認する（レシピを追加、または該当項目をスキップ）。
  - auto: 該当項目を **blocked** にし arbitration へ回す。無人実行で未検証の UI
    要件を黙って素通りさせない。
  - どちらも「設定不足（blocked）」と「試験失敗」を区別する。
- **limits.role_swap_max**: 裁定のロール入れ替え上限。これを消費する検知器と裁定は
  `stall-detection.ja.md` にある。
- **improve**: retrospective 自己改善ブロック。フィールドと動作は
  `improve-apply.ja.md` にある。このファイルはスキーマ上の位置づけだけを固定する。

## pipeline-state.json

配置: `.specs/{feature}/pipeline-state.json`、機能ごとに1つ。

```json
{
  "feature": "user-auth",
  "mode": "auto",
  "issue": 42,
  "language": "en",
  "phase": "spec_review",
  "completed_phases": ["intake", "spec_generate", "inspect"],
  "inspect": {"critical": 0, "warning": 0, "info": 2, "gate": "PASS"},
  "rounds": {
    "spec_review": [
      {"round": 1, "critical": 3, "improvement": 2, "minor": 1,
       "fingerprints": ["a1b2..", "c3d4.."], "gate": "FAIL"}
    ],
    "evaluate": []
  },
  "threads": {"spec_reviewer": "codex-thread-abc"},
  "role_overrides": {},
  "arbitrations": [
    {"phase": "spec_review", "signal": "S1", "decision": "continue", "note": "...", "ts": "..."}
  ],
  "ts_updated": "2026-07-03T00:00:00Z"
}
```

| フィールド | 意味 |
|-----------|------|
| `feature` / `mode` / `issue` | 実行の同定（manual では issue は null） |
| `language` | 検出した入出力言語。intake で設定 |
| `phase` | 現在フェーズ。ループがこれを読んで次に何を走らせるか決める |
| `completed_phases` | 最低1回終えたフェーズ（再開サマリ用） |
| `inspect` | 最後の inspect 結果の要約: CRITICAL / WARNING / INFO 件数とゲート（CRITICAL/WARNING が無ければ `PASS`）。inspect はレビューループではなく単一の機械検査なので、`rounds` 配列ではなく1要約オブジェクト |
| `rounds` | ループ別のラウンド履歴（`spec_review`、`evaluate`）。各エントリは severity 件数・findings 指紋・ゲートを持つ。`evaluate` のエントリは `blocked` 件数も持つ（blocked は critical にも improvement にも数えない。`phases/evaluate.ja.md` 参照）。停滞検知（`stall-detection.ja.md`）が消費 |
| `threads` | resume 用の peer セッションID（例: `spec_reviewer`） |
| `role_overrides` | この実行で振り替えたロール（能力フォールバック or 裁定入れ替え） |
| `arbitrations` | 停滞裁定の記録（`stall-detection.ja.md` 参照） |
| `ts_updated` | 最終書き込み時刻 |

### 所有権: オーケストレーターが書き、ワーカーは読みもしない

`pipeline-state.json` を書くのは **オーケストレーターだけ**。ワーカーは書きも読みも
しない — パイプラインとは結果ファイル（`review-spec-{n}.md`、`evaluate-{n}.md`、
`report.json`）だけで結合する。これによりワーカーが状態の形に依存せず、状態は単一
書き込み者となり競合しない。

### 操作（jq / awk の流儀）

フィールドを読む:
```bash
phase="$(jq -r .phase "$state")"
mode="$(jq -r .mode "$state")"
```

アトミックに書く（その場編集しない — 一時ファイルに書いて mv）:
```bash
jq '.phase = "inspect"
    | .completed_phases += ["spec_generate"]
    | .ts_updated = (now | todate)' "$state" > "$state.tmp" && mv "$state.tmp" "$state"
```

レビューラウンドを追記:
```bash
jq --argjson r '{"round":1,"critical":3,"improvement":2,"minor":1,"fingerprints":[],"gate":"FAIL"}' \
   '.rounds.spec_review += [$r]' "$state" > "$state.tmp" && mv "$state.tmp" "$state"
```

YAML パーサなしで `pipeline.yml` のロール値を読む（フラットな `roles:` ブロックの
awk 流儀）:
```bash
awk '/^roles:/{f=1;next} f&&/^[a-z]/{exit} f&&/spec_reviewer:/{print $2}' "$pipeline"
```

## 成果物の分類

パイプラインは `.specs/` 配下に2種類のファイルを書き、それぞれコミット方針が異なる。

**仕様成果物** — `requirement.md` / `design.md` / `tasks.md` / `test.md`。
これらをコミットするかはプロジェクトの判断（既存の動作から変更なし）。人が読める
ドキュメントであり、機能の設計記録に属する。

**運転記録** — `pipeline-state.json` / `inspection-report.md` /
`.inspection_result.json` / `review-*.md` / `evaluate-*.md` / `evidence/` /
`retrospective.md` / `pipeline-metrics.jsonl`。これらは**既定でコミットしない**。
理由:

- バイナリ証跡（スクリーンショット）は diff でレビューできない。
- 稼働中のシステムから採った証跡は、実在の個人情報や機密データを git 履歴に永続
  させうる。
- レビューラウンドの生ファイルは PR 本文と重複する。PR 本文には機械生成のレビュー
  履歴要約と、証跡マニフェスト付きの合否表が既に載る。

中断再開に運転記録のコミットは要らない: 中断復帰はローカルの `pipeline-state.json`
で成立する（「再開動作」参照）ため、運転記録はローカルディスクにあれば足り、git に
は要らない。

intake は全機能を横断して運転記録を除外する `.specs/.gitignore` を1つ書く。運転記録
を意図的にコミットしたいプロジェクトは、そのファイル（案内コメント付き）を編集する。
コミット手順（implement / pr）のステージ pathspec が第一の防壁、`.specs/.gitignore`
が最後の防壁。

## 再開動作

再開が既定: 起動時に対象機能の `pipeline-state.json` があれば、オーケストレーターは
最初からやり直さない。

1. 状態ファイルを読む。
2. 1ブロックの要約を出す: モード、feature、`completed_phases`、現在の `phase`、次の
   アクション（`phase` を走らせると何が起こるか）。
3. `phase` からループを続ける。完了フェーズは再実行しない。途中で止まった（完了が
   記録されていない）フェーズはその先頭から再入する。各フェーズは前進前に自分の出力
   を検証するため安全。

数時間の実行が中断・クラッシュしても最後に記録したフェーズから再開する — これは
異常系ではなく通常の経路。
