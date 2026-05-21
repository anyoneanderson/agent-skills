# Evaluator Review Process

このファイルは harness-loop における Evaluator review の **how** を定義する。
`evaluator.md` は role identity、`docs/review_rules.md` は what、
`evaluator-tooling/<tool>.md` は Phase 3 の tool-specific 手順を担う。

**全ての Phase は採点のための基準であり、定義された順番・見出し名・
出力形式どおりに忠実に実行する。Phase の省略・統合・改名・自己解釈に
よる再構成は禁止。** 必須 Phase のいずれかをスキップした場合は
Orchestrator により自動で fail に降格される。Phase 2.5
(project quality gate) も Functionality 軸の pass verdict の必要条件である。

## 0. Boot 読込順

1. `git log --oneline -20`
2. `tail -30 .harness/progress.md`
3. `cat .harness/_state.json`
4. 現 sprint の `contract.md` を読む
5. 現 phase の Generator feedback を読む
6. `.gitignore` をパースし、exclusion baseline に追加する
7. `docs/review_rules.md` を読む
8. `docs/coding-rules.md` があれば読む
9. `docs/issue-to-pr-workflow.md` の Quality Gate / `品質ゲート` 節が
   あれば読み、project の PR quality-gate command を特定する
10. primary tool の reference を読む:
   `.claude/skills/harness-loop/references/evaluator-tooling/<tool>.md`

## 1. Exclusion synthesis

Phase 1 の review excludes は次の順で合成する。

1. **Universal baseline**:
   `.git/**`, `**/*.generated.*`, `**/*.lock`, `**/*.log`, `node_modules/**`
2. **`.gitignore` の追加分**:
   `.gitignore` をパースして、その patterns を exclusion set に足す
3. **`_config.yml.project_type` 別 helper excludes**:
   - `web`: `.next/**`, `.turbo/**`, `out/**`, `dist/**`, `build/**`, `coverage/**`
   - `api`: `dist/**`, `build/**`, `coverage/**`, `__pycache__/**`, `target/**`
   - `cli`: `target/**`, `dist/**`, `build/**`
   - `other`: helper layer は持たず `.gitignore` のみ
4. **`docs/review_rules.md` override**:
   `docs/review_rules.md` に `レビュー除外パターン` 節があれば、それを最優先
   override として扱う

これらは review scope を絞るためのものにすぎない。touched file が
scenario に効いているなら、live な契約境界検証を省略する理由にはならない。

## 2. 信頼度ベースの採点制御

- **高信頼 (80+)**: evidence 付きで Findings または Axes に反映する。
- **中信頼 (50-79)**: `Notes for next iteration` に回し、Critical 判定には使わない。
- **低信頼 (49 以下)**: 出力に書かず、先に再検証する。

信頼度は、実行証拠の有無、契約境界へ直接触れたか、Generator の自己申告へ
依存していないかで決める。

## 3. 検証 Phase

### Phase 1: Pattern grep

`docs/review_rules.md` の hotspot と touched files を突き合わせる。
ここは危険信号の抽出フェーズであり、後続の実体確認に必ずつなげる。

### Phase 2: State flow 追跡

`feedback/generator-<iter>-report.json` の `touchedFiles` を頭から末尾まで読み、
state 変換、契約境界に渡る payload、edge case、empty / null / timeout /
auth failure の扱いを mental に trace する。

### Phase 2.5: Project quality gate

Phase 3 の契約境界 integration に入る前に、`docs/issue-to-pr-workflow.md`
の Quality Gate / `品質ゲート` 節に書かれた PR quality gate を実行する。

- 各 command は実行し、stdout/stderr を
  `${SPRINT_DIR}/evidence/iter-<n>/quality-gate-<short-cmd>.log` に保存し、exit code を記録する。
- 1 つでも non-zero exit があれば **Critical** finding とし、その iteration の
  Functionality は pass threshold 未満に cap する。Functionality の pass verdict
  には gate 全体が green であることを必須とする。
- `docs/issue-to-pr-workflow.md` が存在しない場合は、`Improvement` note
  (`no project quality gate wired up`) を出し、gate なしで続行する。

これにより、unit test や contract test だけでは見逃し得る build / lint /
type / packaging など project-level の error を捕捉する。

### Phase 3: 契約境界 integration

`_config.yml.evaluator_tools` の先頭要素を primary tool とみなし、
`.claude/skills/harness-loop/references/evaluator-tooling/<tool>.md` に従う。

- Generator が書いた spec や stub-only test を pass 根拠にしない。
- `page.route`、`addInitScript`、`window.fetch` 上書き、全面 `vi.mock` など
  契約境界 bypass は見つけたら evidence に記録する。
- contract に validation / auth / timeout / empty-state が絡むなら、
  正常系だけでなく異常系または境界値経路も最低 1 本は踏む。

### Phase 4: Audit self-check

最終出力前に yes/no で確認する。

- Phase 1-3 を実行したか
- Phase 2.5 を実行し、すべての project quality-gate command が exit zero で
  終了したことを確認したか
- Generator の test pass を自分の pass 根拠に混同していないか
- 契約境界を自分で踏んだか
- sprint を早く閉じるために甘く採点していないか

1 つでも no なら、verdict を書く前に再実行する。

## 4. 出力構造

`feedback/evaluator-<iter>.md` は少なくとも以下を含む。

- `Verdict`
- `Axes`
- `Evidence`
- `Review findings`（`Critical` / `Improvement` / `Minor`）
- `Notes for next iteration`

`feedback/evaluator-<iter>-report.json` も必須。Orchestrator はこの
機械可読 report を Step 6 で検査し、Phase skip / quality gate 失敗を
自動で fail に降格する。

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
      "cmd": "project quality-gate command as executed",
      "exit": 0,
      "log": "evidence/iter-<n>/quality-gate-command.log",
      "summary": "短い結果要約"
    }
  ],
  "evidence_refs": ["evidence/iter-<n>/quality-gate-command.log"],
  "forced_failure_reason": null
}
```

ルール:

- `phases_executed` は `"1"`, `"2"`, `"2.5"`, `"3"`, `"4"` を必ず含める。
- `phase_2_5_quality_gate_found == true` のとき、
  `phase_2_5_commands` は実行した全 command を含める。
- `phase_2_5_commands[].exit` が 1 つでも non-zero なら `status` は
  `fail` とし、`forced_failure_reason` に `project-quality-gate-failed`
  を入れる。
- `docs/issue-to-pr-workflow.md` に quality gate が存在しない場合のみ
  `phase_2_5_quality_gate_found: false` と `phase_2_5_commands: []` を許可する。
- report が欠落 / JSON 不正 / 必須 field 欠落の場合、Orchestrator は
  `evaluator-report-invalid` として fail に降格する。

`feedback/evaluator-neg-<round>.md` は `Decision`,
`Proposed thresholds`, `Proposed max_iterations`, `Rationale` を含む。
stub-only evidence は feasibility 根拠として使わない。
