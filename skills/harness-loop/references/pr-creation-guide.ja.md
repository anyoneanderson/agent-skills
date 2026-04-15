# PR 作成ガイド

REQ-033 を扱う。sprint が pass すると `harness-loop` は pull request を
開く。PR 本文は実装内容と Evaluator の承認理由を定型化した要約。split と
bundled は同一テンプレートをヘッダ差分のみで使い分ける。

## 事前条件

PR 作成前に確認:

1. `contract.status == "done"`（最終 iteration で全 rubric 軸が threshold 以上）
2. `_state.json.aborted_reason == null`
3. sprint ブランチがローカルに存在し、親ブランチより 1 commit 以上進んでいる
4. `_config.yml.tracker == "github"`（本ガイドは GitHub のみ。gitlab と
   none は末尾で扱う）

どれか満たさない場合は PR 作成せず、理由を `shared_state.md/Decisions` と
`progress.md` に記録し、SKILL flow の Step 9（Sprint Transition）へ戻る。

## ブランチモデル

```
main（または _config.yml.default_branch）
 └── harness/<epic>                 ← epic ブランチ（任意、後述）
      ├── harness/<epic>/sprint-1-<feature>    ← split sprint PR ブランチ
      └── harness/<epic>/sprint-2-<bundle>     ← bundled sprint PR ブランチ
```

有効な 2 形態:

- **Flat**: 各 sprint を `main` から直接分岐。PR 宛先は `main`。
  シンプル。4 sprint 未満の epic 推奨。
- **Epic stacking**: `main` から epic ブランチを 1 本、sprint ブランチは
  epic ブランチから分岐、PR 宛先も epic ブランチ。epic は最後にまとめて
  merge。大きな epic でレビュー文脈を確保したい場合に適する。
  `_config.yml.pr_stack == true` が必要。

epic 開始時にどちらかを選び `_state.json.pr_model` に記録する。epic 内で
混ぜない。

## Split PR（1 sprint = 1 feature = 1 PR）

### `gh pr create` 呼び出し

```bash
gh pr create \
  --base "<base-branch>" \
  --head "harness/<epic>/sprint-<n>-<feature>" \
  --title "feat(<feature>): sprint-<n> — <goal-short>" \
  --body-file /tmp/pr-body-sprint-<n>.md \
  --assignee @me
```

`<base-branch>` は `_config.yml.default_branch`（flat）または
`harness/<epic>`（stacking）。`--draft` は**使わない** — Evaluator の
承認済みなので。

### タイトル書式

`feat(<feature>): sprint-<n> — <goal-short>`

- `<goal-short>`: `contract.goal` の先頭節。55 字で切り詰め
- 非コード成果物（docs, config 等）は `chore(<feature>)` / `docs(<feature>)`
  を使う（最終 iteration の feedback に `change_type` を Generator が記録）

### 本文テンプレート

```markdown
## Summary

<contract.goal をそのまま>

## Acceptance Scenarios

<!-- contract.md から転記。Evaluator が全項目の pass を確認済 -->

- **AS-1**: <given / when / then 1 行> — ✅ pass (iter=<n>)
- **AS-2**: <given / when / then 1 行> — ✅ pass (iter=<n>)
...

## Rubric Verdict (final iteration iter=<n>)

| Axis | Score | Threshold | Verdict |
|---|---|---|---|
| Functionality | 1.00 | 1.0 | ✅ |
| Craft | 0.85 | 0.7 | ✅ |
| Design | 0.80 | 0.7 | ✅ |
| Originality | 0.60 | 0.5 | ✅ |

Evaluator 詳細: `sprints/sprint-<n>-<feature>/feedback/evaluator-<n>.md`

Evidence: `sprints/sprint-<n>-<feature>/evidence/`

## Iteration Count

<n> / <max_iterations>. 経過時間 <HH:MM>. コスト <$X.XX>（この sprint）。

## Closes

Closes #<sprint-issue-number>

<!-- 任意: stacking 時に epic Issue を参照 -->
<!-- Part of #<epic-issue-number>. -->
```

### Issue リンク

- **split**: `Closes #<n>` 行を 1 本（sprint Issue）。
  `_state.json.epic_issue` が非 null なら `Part of #<epic>` を別行で追加
  （**`Closes` ではない**。epic は最終 sprint merge 時に閉じる）
- `_state.json.sprint_issues[<n>]` に Issue 番号/URL が保持される。
  番号を抽出（`gh` が当該リポジトリ内で解決）

## Bundled PR（1 sprint = 複数 feature = 1 PR）

### ブランチとタイトル

```bash
BRANCH="harness/<epic>/sprint-<n>-bundle-<feat1>-<feat2>"
git switch -c "$BRANCH"
# ...commits...
gh pr create \
  --base "<base-branch>" \
  --head "$BRANCH" \
  --title "feat(<epic>): sprint-<n> — <feat1> + <feat2>" \
  --body-file /tmp/pr-body-sprint-<n>.md
```

タイトルは主要 feature を `+` 区切りで列挙。3 を超える場合は
`feat(<epic>): sprint-<n> — <feat1> + <feat2> + N others` 形式。

### 本文テンプレート（split と差分あり）

```markdown
## Summary

<contract.goal をそのまま — これら feature をまとめて出す理由を記載>

## Bundled features

- **<feat1>**: <1 行 goal>
- **<feat2>**: <1 行 goal>
...

## Acceptance Scenarios

<!-- feature 毎にグルーピング。Evaluator 全項目確認済 -->

### <feat1>
- **AS-1**: ... — ✅ pass
...

### <feat2>
- **AS-1**: ... — ✅ pass
...

## Rubric Verdict (final iteration iter=<n>)

| Axis | Score | Threshold | Verdict |
|---|---|---|---|
| Functionality | 1.00 | 1.0 | ✅ |
...

Evaluator 詳細: `sprints/sprint-<n>-<bundle>/feedback/evaluator-<n>.md`

## Iteration Count

<n> / <max_iterations>. 経過時間 <HH:MM>. コスト <$X.XX>（この sprint）。

## Closes

Closes #<feat1-issue>
Closes #<feat2-issue>
<!-- bundled sprint Issue 毎に 1 行 -->
```

### 複数 Closes

bundle 内各 feature には `harness-plan` が sprint Issue を作成済
（`issue-create.md` 参照）。feature 毎に `Closes #N` を出力 — PR merge 時に
GitHub が各 Issue を close。

bundle が `roadmap.md` で定義されているが sprint Issue が作られていない
（plan 時に tracker が `none` で後から切替など）場合は、`Closes` 行を出さず
サマリリストのみとし、`shared_state.md/Decisions` に不整合を記録する。

## Reviewers / Labels / Milestones

v1 はシンプルに:

- **Reviewers**: デフォルト無し。レビュー経路を望むユーザは
  `_config.yml.pr_reviewers: [user1, user2]` を設定、harness-loop が
  `--reviewer user1 --reviewer user2` を追加
- **Labels**: 常に `harness-loop` を付与。sprint の `roadmap.md` に
  `labels:` があれば pass-through
- **Milestone**: `_state.json.epic_issue` があり、その milestone が
  非 null なら継承。無ければ省略

## `gh pr create` 成功後

成功時 `gh` は PR URL を stdout に出す。Orchestrator は:

1. stdout から URL を抽出
2. `_state.json.sprint_issues[<n>].pr` に保存
3. `shared_state.md/Decisions` に 1 行追記:
   ```
   [<ts>] PR opened: sprint-<n> <pr-url> (bundling=<split|bundled>)
   ```
4. `progress.md` に 1 行追記:
   ```
   [<ts>] decision: sprint-<n> PR opened <pr-url>
   ```
5. `_state.json` の更新を commit（PR 自体は GitHub 側の所有）

`gh pr create` が失敗した場合（auth / network / branch-未 push）、エラーを
ログして 1 回リトライ。2 回目失敗時は `pending_human=true`、
`aborted_reason: "pr-create-failed: <gh stderr>"` にして halt。

## 非 GitHub tracker

### `tracker: gitlab`

v1 は `glab` を呼び出さない。代わりに sprint pass 後:

1. 同テンプレートで本文を構築
2. `.harness/<epic>/sprints/sprint-<n>-*/pr-body.md` に書き出す
3. `.harness/<epic>/pending-prs.md`（epic レベル台帳）に追記:
   ```
   - sprint-<n>: branch=<branch> body=sprints/sprint-<n>-*/pr-body.md
   ```
4. ユーザ向け表示: "pending-prs.md 台帳から手動で MR を開いてください"
5. `_state.json.sprint_issues[<n>].pr = "gitlab:pending"` に設定

### `tracker: none`

PR 作成をスキップ。sprint 完了は git 履歴（iter 毎 commit）と
`shared_state.md` に残る。`progress.md` に追記:

```
[<ts>] decision: sprint-<n> completed (tracker=none, no PR)
```

## Dry-run

`harness-loop --dry-run-pr` は
`.harness/<epic>/sprints/sprint-<n>-*/pr-body.preview.md` に本文を書き出し、
`gh pr create` コマンドを実行せず表示する。初 sprint でテンプレートをまだ
信頼しきれていないユーザ向け。

## 本ガイドの非対象

- PR レビューコメント対応 — 人間の活動。merged-PR のレビュー知見からの
  ルール更新は将来 `/harness-rules-update` で提案する可能性あり
- レビュー後の force-push — harness-loop スコープ外
- Auto-merge — v1 スコープ外。明示的な人間 merge のみ
- リリース tagging — harness パイプライン範囲外
