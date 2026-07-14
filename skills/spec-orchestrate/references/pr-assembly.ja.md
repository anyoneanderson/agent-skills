# PR 組み立て — 証跡付き pull request

pr フェーズは pull request を作成する。ブランチ・コミット・ベースの仕組みは
spec-implement から来る。このファイルは、オーケストレーターが追加する本文セクション
（敵対的レビュー履歴と受け入れ証跡）で PR に自らの証明を持たせる方法と、停滞した実行
が draft で着地する扱いを規定する。

English version: [pr-assembly.md](pr-assembly.md)

## ベース: spec-implement + ワークフロー規約

PR は spec-implement の最終ステップが作成する。オーケストレーターはブランチや PR
規約を作り直さない:

- `issue-to-pr-workflow.md` があれば、そのブランチ命名・PR 規約が優先。
  spec-implement が既にこれを playbook として読む。
- `coding-rules.md` があれば spec-implement に引き継ぐ（spec-implement が spec-code
  に渡す）。オーケストレーター自身はコーディングルールを適用しない。
- オーケストレーターの追加は、下記の本文セクションをワークフローの PR テンプレートに
  付け足すことだけ。

## 本文セクション（記憶ではなく state から生成）

3セクションはすべて `pipeline-state.json` と結果ファイルから機械的に生成する。
オーケストレーターの記憶からは決して作らない。

### `## Adversarial Review History`

`state.rounds`（`spec_review` とタスク別の実装レビュー）から:

- ループごと: ラウンド数と最終ゲート（PASS / FAIL のまま着地）。
- 先送りした findings を段階付きで列挙: `fix_before: trial` / `required_check` /
  `follow_up` で持ち越したすべての finding と、未解決の **Minor** findings。ゲートは
  これらで止まらないため、浮上する場所は PR 本文である — 先送りであって、黙って
  捨てられることはない。`trial` / `required_check` / `follow_up` の finding は PR
  作成時に後続 issue にしてここへリンクする。
- ロール入れ替えや裁定があれば `state.arbitrations` の各エントリを1行（シグナル +
  裁定）。読み手が、なぜ担当が入れ替わったか / なぜ draft 着地したかを分かるように。

```markdown
## Adversarial Review History
- Spec review: 3 rounds, final Gate PASS
- Implementation review (T003): 2 rounds, final Gate PASS
- Deferred findings:
  - [ ] **Critical / fix_before: required_check** design.md §5.1 — stale success can be re-issued; fix before the check becomes required (#124)
  - [ ] **Improvement / fix_before: follow_up** `CR-STYLE-004` design.md §4.2 — naming nit (#125)
  - Minor: `CR-STYLE-002` design.md §3.1 — wording nit, deferred
- Arbitration: S1 at spec_review round 4 → reviewer swapped codex→claude
```

### `## Acceptance Evidence`

最終 `evaluate-{n}.md`（その Evidence Manifest を含む）から:

- 要件ID別の合否表（項目・要件・検証方法・判定）。
- 各証跡ファイルの証跡マニフェスト — ファイル名・バイトサイズ・sha256 — を結果
  ファイルのマニフェストから転記する。
- 証跡ファイル自体は運転記録であり、**コミットも添付もしない**（`pipeline-config.ja.md`
  の「成果物の分類」を参照）。PR はバイナリではなくマニフェストを載せる: ハッシュに
  より、スクリーンショットやログを git 履歴に入れずに「実行後に証跡が差し替えられて
  いない」ことをレビュアーが確認できる。スクリーンショットやレビュー生ファイルを PR
  本文に埋め込まない — レビューラウンドは上の Adversarial Review History に要約済み。

```markdown
## Acceptance Evidence
| Case | Requirement | Verify | Verdict |
|------|-------------|--------|---------|
| T-A01 | REQ-001 | playwright | PASS |
| T-A02 | NFR-001 | command | PASS |

### Evidence Manifest
| File | Bytes | sha256 |
|------|-------|--------|
| evidence/2/T-A01-login.png | 51384 | a1b2c3d4… |
| evidence/2/T-A02-latency.log | 892 | d4e5f6a7… |
```

### `## Unresolved`（draft 着地時のみ）

裁定経由で着地した（解決できなかった停滞）ときだけ付ける。未解決の
**修正ループ対象の findings**（spec review: `fix_before: implementation`。
evaluate: 不合格ケース）を列挙し、draft を引き取る人に残作業を正確に伝える。

```markdown
## Unresolved
- [ ] **Critical** T-A05 [REQ-007] export fails for empty datasets — 2 rounds, not converged
- [ ] **Improvement** design.md §4.4 — retry policy still unspecified
```

## draft か ready か

| 結果 | PR 状態 | 内容 |
|------|--------|------|
| evaluate Gate PASS（全項目合格） | ready | Review History + Acceptance Evidence |
| 裁定の draft 着地（停滞） | **draft** | 上記 + `## Unresolved`（未解決の修正ループ対象 findings） |

受け入れ項目が不合格・blocked の間は ready（非 draft）PR を開かない — ready PR は
evaluate ゲート通過を主張する。停滞した実行は常に draft で着地し、無人パイプラインが
未検証の作業を merge 可能として ready にしないようにする。

## state 更新（pr フェーズ）

PR 作成後、PR URL と draft フラグを `pipeline-state.json` に記録し、retrospective に
進む（`phases/pr.md` 参照）。
