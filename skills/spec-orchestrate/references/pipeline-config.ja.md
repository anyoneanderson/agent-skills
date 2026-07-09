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
| `repairs` | 任意。resume 時や整合性検査の失敗後に適用した state 乖離の修復記録（§state 突合 参照） |
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

## Run マーカーと watchdog

`.specs/.orchestrate-active.json`（リポジトリに1つ）は「実行が途中である」ことの印で、
watchdog Stop hook（`references/scripts/pipeline-watchdog.sh`）が「停滞した
オーケストレーター」と「終わった実行」を見分けるために使う。運転記録であり、
決してコミットしない。

```json
{
  "feature": "user-auth",
  "waiting_report": null,
  "paused": false,
  "blocks": 0,
  "fingerprint": "",
  "ts": "2026-07-09T00:00:00Z"
}
```

ライフサイクル（state と同じくオーケストレーターが所有する）:

- **作成** — intake で（resume 時に無ければ再作成）:
  ```bash
  jq -n --arg f "$feature" '{feature:$f, waiting_report:null, ts:(now|todate)}' \
    > .specs/.orchestrate-active.json
  ```
- **`ts` の更新** — state を書くたびに同じ `jq ... > tmp && mv` 流儀で更新する。
  4時間触られていないマーカーは放棄された実行とみなされ、watchdog はブロックを止める。
- **待機の登録** — detach 待ちで yield する前に登録し、回収後に消す
  （`role-dispatch.ja.md` Step 3 参照）:
  ```bash
  jq --arg p "$report" '.waiting_report = $p | .ts = (now|todate)' \
    .specs/.orchestrate-active.json > t && mv t .specs/.orchestrate-active.json
  ```
- **削除** — retrospective フェーズの最後の手順として削除する。マーカーの削除が
  watchdog に対する終端の合図である。

`paused` / `blocks` / `fingerprint` は watchdog 側のフィールド（人が黙らせたい
ときは `paused: true` を立てる。hook は state が進まないままの連続ブロックを数え、
3回で諦めるため、詰まったセッションを永遠に閉じ込めることはない）。

hook はリポジトリごとに Claude Code の Stop hook として登録する
（spec-workflow-init の Step 6d が行う。`.claude/settings.json` への手動追記例）:

```json
{"hooks": {"Stop": [{"hooks": [{"type": "command",
  "command": "bash .claude/skills/spec-orchestrate/references/scripts/pipeline-watchdog.sh"}]}]}}
```

## state 突合（整合性検査）

`references/scripts/pipeline-state-check.sh <spec-dir>` は、state ファイルの主張を
偽装できない証拠と突き合わせる: 正準フェーズ順序と `completed_phases`（先のフェーズに
居るのに前段が未記録 = state 更新なしでフェーズが走った。ただし `arbitrations` に
`decision: "draft"` が記録された draft PR 着地は approval / implement / evaluate を
免除する）、`tasks.md` のチェックボックスと `implement.tasks_done`（両方向）、
運転記録ファイル（`retrospective.md`・`evaluate-*`）と記録上のフェーズ、そして
`gh` があれば現在ブランチの PR 実在と `pr` 未到達の state。
exit 0 = 整合、exit 1 = 乖離1件につき `DRIFT:` 行を1つ出力する。

**実行タイミング（必須）:** state を書くたびに1回、および resume の最初の手順として。

**乖離したら、証拠が勝つ。** 実際に起きたことへ state を合わせる — 欠けている
`completed_phases` を足し、欠けている `tasks_done` を足し、証拠が示す位置へ `phase` を
直す — そして修復を記録する:

```bash
jq --arg d "$drift_summary" \
   '.repairs = ((.repairs // []) + [{ts:(now|todate), drift:$d}])' \
   "$state" > "$state.tmp" && mv "$state.tmp" "$state"
```

修復後にもう一度検査を走らせ、clean になってからループを続ける。state が忘れていた
だけで成果物が実在するフェーズを、再実行してはならない。

## 成果物の分類

パイプラインは `.specs/` 配下に2種類のファイルを書き、それぞれコミット方針が異なる。

**仕様成果物** — `requirement.md` / `design.md` / `tasks.md` / `test.md`。
これらをコミットするかはプロジェクトの判断（既存の動作から変更なし）。人が読める
ドキュメントであり、機能の設計記録に属する。

**運転記録** — `pipeline-state.json` / `inspection-report.md` /
`.inspection_result.json` / `review-*.md` / `evaluate-*.md` / `evidence/` /
`retrospective.md` / `pipeline-metrics.jsonl` / `.orchestrate-active.json`。
これらは**既定でコミットしない**。理由:

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

1. **最初に state 突合を走らせる**（§state 突合）。乖離があれば証拠に合わせて state を
   修復し、修復を記録してから先へ進む — 古い state を信じた resume は、終わった作業を
   やり直すか、残っている作業を飛ばす。`.specs/.orchestrate-active.json` が無ければ
   再作成する。
2. 状態ファイルを読む。
3. 1ブロックの要約を出す: モード、feature、`completed_phases`、現在の `phase`、次の
   アクション（`phase` を走らせると何が起こるか）。
4. `phase` からループを続ける。完了フェーズは再実行しない。途中で止まった（完了が
   記録されていない）フェーズはその先頭から再入する。各フェーズは前進前に自分の出力
   を検証するため安全。

数時間の実行が中断・クラッシュしても最後に記録したフェーズから再開する — これは
異常系ではなく通常の経路。
