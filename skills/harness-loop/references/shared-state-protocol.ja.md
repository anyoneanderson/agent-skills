# Shared-read / Isolated-write プロトコル

sprint 中、Planner / Generator / Evaluator と Orchestrator は同一の
`shared_state.md` 台帳を全員が読むが、**書き込みは Orchestrator のみ**。
他のエージェントは各自の `feedback/{role}-{iter}.md` に append する。
これにより台帳は race なく、iteration 毎の監査可能性を保つ。

## ファイル配置（sprint 単位）

```
.harness/<epic>/sprints/sprint-<n>-<feature>/
├── contract.md                     ← 交渉後に凍結（Orchestrator 書込、全員読取）
├── shared_state.md                 ← Orchestrator のみ書込、全員読取
├── feedback/
│   ├── planner-ruling.md           ← Planner のみ書込（交渉停滞時）
│   ├── planner-<iter>.md           ← Planner のみ書込（稀：再計画要求）
│   ├── generator-neg-<round>.md    ← Generator のみ書込（交渉ラウンド）
│   ├── generator-<iter>.md         ← Generator のみ書込（実装 iteration）
│   ├── evaluator-neg-<round>.md    ← Evaluator のみ書込（交渉ラウンド）
│   └── evaluator-<iter>.md         ← Evaluator のみ書込（実装 iteration）
└── evidence/                       ← Evaluator が実行成果物、全員読取
```

交渉ラウンドは `<round>`（1..3）で、明示的に `-neg-` prefix を持つ。
実装 iteration は `<iter>`（1..max_iterations）で、従来どおり
role 名だけのファイル名を使う。よって両系列は `contract.status`
だけでなくファイル名からも判別できる。

harness-loop 内での実装：両シリーズを同一ディレクトリに置く。Orchestrator
は読取時に `contract.status` かファイル名パターン（`*-neg-*` と通常 iter）
のどちらでも round / iter を判別できる。

## 書き込み権限（正式）

| パス | Orchestrator | Planner | Generator | Evaluator |
|---|---|---|---|---|
| `contract.md` frontmatter | ✅ freeze のみ | ❌ | ❌ | ❌ |
| `contract.md` `generator_backend` field | ✅ roadmap から copy（contract-draft）／ Negotiation 合意 ／ ruling | ✅ `ruling` phase のみ | ❌（`feedback/generator-neg-*.md` で変更提案可）| ❌（`feedback/evaluator-neg-*.md` で変更提案可）|
| `contract.md` Negotiation Log | ✅ feedback から転記 | ❌ | ❌ | ❌ |
| `shared_state.md` | ✅ 唯一の書き手 | ❌ | ❌ | ❌ |
| `feedback/planner-*.md` | ❌ | ✅ | ❌ | ❌ |
| `feedback/generator-*.md` | ❌ | ❌ | ✅ | ❌ |
| `feedback/evaluator-*.md` | ❌ | ❌ | ❌ | ✅ |
| `evidence/*` | ❌ | ❌ | ❌ | ✅ |
| `_state.json` | ✅ 唯一の書き手 | ❌ | ❌ | ❌ |
| `metrics.jsonl` | ✅ 唯一の書き手 | ❌ | ❌ | ❌ |
| `progress.md` | ✅ 直接 append | PostToolUse hook 経由 | PostToolUse hook 経由 | PostToolUse hook 経由 |

`progress.md` はエージェント側の書き込みが
`.harness/scripts/progress-append.sh` hook 経由で到達する共有ログ。直接の
ファイル操作ではない。hook 経路は race-safe（POSIX 上の小さな `>>` 追記は
atomic）。

validator / dispatch script は `_state.json` を直接書かない。
`pending_human`、`consecutive_validator_violations`、`halt_reason` を含む
全 state transition は Orchestrator だけが担当する。

## `shared_state.md` セクション所有権

テンプレートのコメントで所有権は明示済み。要約:

| セクション | 記入タイミング | Orchestrator のアクション |
|---|---|---|
| `## Plan` | sprint 開始時 | contract.md の `goal` と `acceptance_scenarios` を転記 |
| `## Contract` | contract 凍結時 | `sprint-<n>-contract.md @ <SHA>` を記録 |
| `## Negotiation` | 各ラウンド後 | ラウンド毎に 2 行（G+E）、停滞時は ruling 行 |
| `## WorkLog` | 各 Generator turn 後 | 1 行: iter, agent, commit, 要約ポインタ |
| `## Evaluation` | 各 Evaluator turn 後 | 1 行: iter, verdict, 軸毎スコア, evidence ポインタ |
| `## Decisions` | 状態遷移時 | 1 行: decision 種別, 理由, commit SHA |

append は常に新規行。in-place 編集は禁止。正準的な append 実装:

```bash
# 擬似コード; 実 Orchestrator 経路は jq 駆動で値を作る
printf '\n- %s\n' "$line" >> shared_state.md
```

`shared_state.md` は**人間可読**を維持する。エージェントがコンテキストとして
読むため、台帳のノイズは token コストに直結する。

## 読み取りパターン

各エージェントは turn 開始時に以下を読む:

1. `contract.md` — sprint の真実
2. `shared_state.md` — 台帳要約
3. 直前の相手役の `feedback/*.md`（存在すれば）
4. `../../progress.md` の末尾（Boot Sequence）
5. `../../_state.json`（Boot Sequence）

エージェントは**デフォルトでは**他エージェントの過去 feedback を読まない。
Orchestrator が特定の過去ファイルをコンテキストに必要と判断すれば、プロンプト
に stitch する。feedback をデフォルト読取から外すことで、長 sprint でも turn
毎の token budget を安定させる。

## Atomic 書き込みの規律（Orchestrator 側）

atomic 性を要求する 3 ファイル:

1. **`_state.json`** — 全書き込みは:
   ```bash
   jq '<delta>' .harness/_state.json > .harness/_state.json.tmp
   mv .harness/_state.json.tmp .harness/_state.json
   ```
   同一ファイルシステム内の `mv` は macOS / Linux で atomic。

2. **`metrics.jsonl`** — 常に JSON 1 行 append。編集禁止。crash 時の
   部分書きは許容（tail reader が不正 JSON をスキップ）。

3. **`shared_state.md`** — 各 append は単一 `printf`。read 側は
   終端行が read 途中で到達しても line-oriented パーサで許容。

append-only 規律により、crash 後の復旧は
`git checkout -- path/to/file` で最後のコミット状態に戻し、Orchestrator が
`_state.json` + ディスク上に見える feedback ファイルから再構成する。

## `deliverable_checks` スキーマ（foundation sprint）

`type: foundation` sprint では Generator の `feedback/generator-<iter>-report.json`
に `deliverable_checks` オブジェクトを追加する。これは
`feedback/generator-<iter>.md` のナラティブを機械可読にしたもので、
`harness-loop` が `feedback/verification-<iter>.md` を組み立てる入力。

```json
{
  "status": "done" | "blocked",
  "touchedFiles": ["リポ root 相対パス", "..."],
  "summary": "<1 行サマリ>",
  "blocker": null | "<status=blocked 時の理由>",
  "deliverable_checks": {
    "<deliverable_key>": {
      "status": "pass" | "fail",
      "evidence": "<短い自由記述、具体的な file/commit/log を引用>"
    },
    "...": { "..." }
  }
}
```

ルール:

- **キーは `contract.deliverables` と完全一致すること**。Orchestrator が
  ingest 時に cross-check し、mismatch 時は WARN を吐く（Generator 側の
  余剰キーは drop、欠損キーは自動で
  `{status: "fail", evidence: "not reported by Generator"}` に）
- **per-key `status`** は Generator の自己申告。Orchestrator はこれを
  *仮説* として扱い、`foundation-readiness.sh --check <key>` の probe
  結果で**上書き確認**する（食い違ったら probe が優先、progress.md に
  WARN 行を残す）
- **evidence** は短い自由記述、≤ 160 字が目安。典型例:
  - `package.json + pnpm-lock.yaml committed`
  - `curl http://localhost:3000/ returned 200 at 2026-04-20T12:34Z`
  - `playwright test --list: 3 tests`
  - `prisma migrate dev: 20260420_init applied`
  - `SETUP.md sections: 1..7 (Prerequisites, GCP OAuth, ...)`
- **`touchedFiles`** は dirty file の正本。Orchestrator はこれを
  fallback source として使う。未記入時は Orchestrator 側で
  `git ls-files -m -o --exclude-standard` を計算し WARN ログ

### Orchestrator の組み立て（verification-<iter>.md へ）

Generator の report.json から `deliverable_checks` を読み、各キーに対し
`foundation-readiness.sh --check <key>` を実行、結果を
`feedback/verification-<iter>.md` に markdown 表として書く:

```markdown
---
role: orchestrator
sprint: 0
iter: <iter>
ts: <ISO-8601-UTC>
---

| Deliverable | Generator 申告 | Probe 判定 | Evidence | 一致 |
|---|---|---|---|---|
| package_manifest | pass | pass (ok) | package.json + pnpm-lock.yaml committed | ✅ |
| runtime_boots | pass | pass (ok) | curl / returned 200 | ✅ |
| test_runner_configured | pass | pass (ok) | playwright --list: 3 tests | ✅ |
| env_example_committed | pass | pass (ok) | .env.example keys: 6/6 | ✅ |
| external_setup_doc | pass | pass (ok) | docs/SETUP.md sections 1-7 | ✅ |
| dev_db_available | pass | pass (ok) | docker-compose.yml present | ✅ |

合計: 6/6 deliverables pass.
```

不一致行（Generator `pass` + probe `missing`、またはその逆）は一致列を
`⚠️ disagree` とマークし、attestation gate で operator の注意を喚起。

### なぜ deliverable 単位の構造か

- **リプレイ性**: 同じ report.json を再 ingest するだけで probe を
  再実行できる（Generator の再 invocation 不要）
- **差分比較しやすさ**: retry iteration で同形の表が並ぶので、どの
  deliverable が修正 / 退行したか一目瞭然
- **機械 vs 人間判定の分離**: probe が独立した機械判定を提供し、
  Generator の申告も残る（probe 自体にバグがあった時の検証用）

## Feedback ファイルの汎用スキーマ

`feedback/{role}-<n>.md` は共通形状:

```markdown
---
role: <planner|generator|evaluator>
iter: <n>              # または交渉中は round: <r>
sprint: <sprint-number>
ts: <ISO-8601-UTC>
# 任意、役割固有: negotiation-protocol.ja.md 参照
---

## Summary

<1 パラグラフ、1〜3 文>

## Details

<自由記述 markdown; コード、ログ、evidence ポインタ可>

## Next action

<このエージェントが次に期待する動作; 空でも可>
```

Orchestrator は `Summary` を `shared_state.md` 行の構築に利用。Details と
evidence ポインタは feedback ファイル側に残す。

## Evaluator compliance report スキーマ

実装 iteration では Evaluator も `feedback/evaluator-<iter>-report.json`
を必ず書く。これは narrative の代替ではなく、Orchestrator が Step 6 で
Phase 実行と project quality gate の結果を機械検査するための正本。

```json
{
  "status": "pass",
  "axes": {
    "functionality": 1.0,
    "craft": 0.9,
    "design": 0.8,
    "originality": 0.7
  },
  "critical_count": 0,
  "improvement_count": 0,
  "minor_count": 0,
  "phases_executed": ["1", "2", "2.5", "3", "4"],
  "phase_2_5_quality_gate_found": true,
  "phase_2_5_commands": [
    {
      "cmd": "実行した command",
      "exit": 0,
      "log": "evidence/iter-<n>/quality-gate-command.log",
      "summary": "短い結果要約"
    }
  ],
  "evidence_refs": ["evidence/iter-<n>/quality-gate-command.log"],
  "forced_failure_reason": null
}
```

Orchestrator の検査ルール:

- JSON parse に失敗、または必須 field が欠ける場合は
  `forced_failure_reason = "evaluator-report-invalid"` として fail。
- `phases_executed` に `"1"`, `"2"`, `"2.5"`, `"3"`, `"4"` のいずれかが
  欠ける場合は `phase-<n>-skipped` として fail。
- `phase_3_evidence_status` は validator が書く field で、元の
  `phases_executed` 申告とは独立に `"present"`, `"missing"`, `"n/a"` を
  記録する。validator は `phases_executed` から phase を破壊的に削除しない。
- `validator_violations` は validator が書く field。存在する場合、再実行時は
  冪等性のため既存値を保持し、互換用 forced reason field はその token を
  カンマ結合して同期する。
- `validator_invoked` と `schema_version` も validator-owned であり、
  agent ではなく validator script が書く。
- `phase_2_5_quality_gate_found != false` かつ `phase_2_5_commands` が
  空の場合は `phase-2.5-commands-missing` として fail。
- `phase_2_5_commands[].exit` が 1 つでも non-zero の場合は
  `project-quality-gate-failed` として fail。
- fail 降格時は Functionality を pass threshold 未満に cap し、PR 作成へ
  進まない。

## 競合ケースと是正

| ケース | 是正 |
|---|---|
| 同一 iter で 2 エージェントが同じ `feedback/*` に書いた（bug） | Orchestrator が後発を `*.dup.<ts>.md` にリネームし progress.md にログ |
| エージェントが `shared_state.md` を直接編集 | Step 7 の commit 時に `git status` に出る。Orchestrator が revert（`git checkout --`）してログ |
| エージェントが `_state.json` に書き込み | 禁止。Orchestrator がメモリ + feedback 内容から正しい値に上書きしログ。破損なら halt してユーザ提示 |
| Evaluator が存在しない evidence を参照 | テスト基盤障害として扱う。verdict を `fail`（`reason: evidence-missing`）、Principal Skinner の stagnation で再発検知 |

## なぜ Shared-read / Isolated-write か

- **race 排除**: sub-agent 並列 dispatch 時に同一ファイルへ書き込みが
  衝突すると torn write が起きる。書き込みを分離することで種別として排除。
- **エージェント単位の監査性**: "iter-5 で Generator は何を考えたか" が
  `cat feedback/generator-5.md` で 1 ファイル 1 著者として完結する。
- **要約と詳細の分離**: 台帳は短く（event 毎 1 行）保ち、熟考は feedback
  に置く。台帳コストしか払わない将来のエージェントは O(sprint イベント)
  tokens で済み、O(全エージェント出力) を支払わない。
- **Replay**: 監査者は contract.md + shared_state.md + feedback/*-<iter>.md
  を順に読めばどの iteration も再構成できる。
