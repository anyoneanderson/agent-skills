# Shared-read / Isolated-write プロトコル

REQ-030 と REQ-074 を扱う。sprint 中、Planner / Generator / Evaluator と
Orchestrator は同一の `shared_state.md` 台帳を全員が読むが、**書き込みは
Orchestrator のみ**。他のエージェントは各自の `feedback/{role}-{iter}.md`
に append する。これにより台帳は race なく、iteration 毎の監査可能性を
保つ。

## ファイル配置（sprint 単位）

```
.harness/<epic>/sprints/sprint-<n>-<feature>/
├── contract.md                     ← 交渉後に凍結（Orchestrator 書込、全員読取）
├── shared_state.md                 ← Orchestrator のみ書込、全員読取
├── feedback/
│   ├── planner-ruling.md           ← Planner のみ書込（交渉停滞時）
│   ├── planner-<iter>.md           ← Planner のみ書込（稀：再計画要求）
│   ├── generator-<round>.md        ← Generator のみ書込（交渉ラウンド）
│   ├── generator-<iter>.md         ← Generator のみ書込（実装 iteration）
│   ├── evaluator-<round>.md        ← Evaluator のみ書込（交渉ラウンド）
│   └── evaluator-<iter>.md         ← Evaluator のみ書込（実装 iteration）
└── evidence/                       ← Evaluator が実行成果物、全員読取
```

交渉ラウンドは `<round>`（1..3）で、実装 iteration は `<iter>`
（1..max_iterations）でキー付け。ファイル名上の番号空間は重ならない。
書込時の `contract.status` で区別：`negotiating` → `round`、
`active` → `iter`。

harness-loop 内での実装：両シリーズを同一ディレクトリに置き、番号レンジを
分けて保持。Orchestrator は読取時に `contract.status` から round か iter
を判別する。

## 書き込み権限（正式）

| パス | Orchestrator | Planner | Generator | Evaluator |
|---|---|---|---|---|
| `contract.md` frontmatter | ✅ freeze のみ | ❌ | ❌ | ❌ |
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

設計参照: `.specs/harness-suite/design.md` §9.5
