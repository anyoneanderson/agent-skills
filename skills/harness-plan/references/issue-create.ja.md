# Sprint Issue 起票

REQ-023 および ASM-002 のカバー範囲 — `roadmap.md` 承認後に `harness-plan` が
sprint 単位で tracker に Issue を作成する方法。roadmap ドラフト中は起票しない。
起票は承認後に 1 度だけ行う。

## Tracker 分岐

`_config.yml.tracker` で分岐:

| Tracker | 挙動 |
|---|---|
| `github` | sprint 毎に `gh issue create`（主経路） |
| `gitlab` | v1: 起票予定ペイロードを `.harness/<epic>/pending-issues.md`（harness-plan が所有する epic 単位の ledger ファイル）に記録、CLI は呼ばない。v2 で glab 連携追加 |
| `none` | 完全スキップ。sprint 進捗は `.harness/` と git のみで追跡。tracker なしモードを示す 1 行を `progress.md` に記録 |

いずれの経路でも `_state.json.sprint_issues` は更新される（GitHub は Issue URL、
その他は `gitlab:pending` / `none:ledger` のようなプレースホルダ）。

> **shared_state.md は使わない**: `shared_state.md` は sprint 単位で
> `.harness/<epic>/sprints/sprint-<n>-<feature>/` に置かれ、harness-loop が
> Planner ⇄ Generator ⇄ Evaluator の通信 ledger として所有する。
> harness-plan 実行時点では存在せず、書き込み対象でもない。
> harness-plan は epic 単位で動くため `pending-issues.md` を使う。

## GitHub 経路

### Pre-flight

sprint ループ前に検証:

1. `gh auth status` 成功 — 失敗時は案内して中断
2. `github.com` リモートを持つ git リポジトリ配下 —
   `git remote get-url origin` から `owner/repo` を導出
3. **親 epic issue** が存在 — 以下いずれか:
   - `/harness-plan` の `--epic <number>` フラグで指定
   - product-spec 本文を body として新規作成（デフォルトは
     `AskUserQuestion`。`--auto-approve-roadmap` 指定時はデフォルトで
     新規作成し番号を `_state.json.epic_issue` に記録）

**`tracker == github` のうえで `gh` が PATH にない場合** は REQ-023 に従って
skill を **中断** する。`gitlab` や `none` にサイレントフォールバックしては
ならない — tracker 種別が利用者合意なく変わると audit trail が破綻する。
（`tracker ∈ {gitlab, none}` のときは `gh` は不要でこのチェックはスキップ。）

### sprint 毎の作成

roadmap 順に各 sprint で:

```bash
gh issue create \
  --title "[sprint-${n}] ${feature}" \
  --body-file <(generate_body) \
  --label "harness,sprint" \
  --assignee "@me"
```

`generate_body()` の出力:

```markdown
Parent epic: #<EPIC_NUMBER>

## Sprint <n> — <feature>

**Bundling**: <split|bundled>
**Bundled with**: <bundle peer 番号。なければ "—">
**Dependencies**: <先行 sprint 番号。なければ "—">
**Risk**: <low|medium|high>

## Scope（product-spec.md より）

<product-spec.md の該当 What 項目をそのまま引用>

## Out of Scope

<product-spec.md の Out of Scope セクション全体を引用 — sprint negotiation 中の
scope creep を防ぐ>

## Contract

`harness-loop` 内で交渉 — `.harness/<epic>/sprints/sprint-<n>-<feature>/contract.md`

## PR

Split: この sprint は単独 PR で出る。
Bundled: この sprint は sprint `<bundled_with>` の bundle PR の一部として出る。
本 Issue のクローズは bundle PR マージ時。
```

`gh issue create` の stdout から URL / 番号を取得し、
`_state.json.sprint_issues[<n>] = "<url>"` に記録。

### 重複検出（再実行耐性）

`harness-plan` は再入可能。既存 `roadmap.md` での再実行時、各 sprint issue 作成前に:

```
query: gh issue list --label harness,sprint --search "in:title [sprint-${n}] ${feature}"
```

- **マッチなし**: 通常どおり作成
- **open で 1 件マッチ**: その URL を再利用。重複を作らない
- **複数マッチ** または **close 済みのみマッチ**: デフォルトは
  `AskUserQuestion` で停止。`--auto-approve-roadmap` 指定時は
  `progress.md` に `TODO(issue-dup): sprint-${n}` を記録してスキップ。
  いずれにせよ利用者が手動解決

強制作成しない。重複 Issue は audit trail を分断し `sprint_issues` マッピングを壊す。

### Epic リンク構文

GitHub は 2026-04 時点で全リポジトリに対するネイティブ sub-issue 関係を持たない。
2 構文をサポート:

1. **文章参照**（常に）: body 冒頭行を `Parent epic: #<EPIC_NUMBER>` にする。リンク化される。
2. **Sub-issue API**（sub-issue beta リポジトリのみ）: Planner が
   `gh api repos/{owner}/{repo}` で `sub_issues_summary` を確認し、存在すれば
   `gh api /repos/{owner}/{repo}/issues/{epic}/sub_issues` で正式リンクを作成。
   404 / 422 時は文章参照にサイレントフォールバック。

### ラベル衛生

`harness-plan` は以下 2 ラベルを冪等に作成:

- `harness` — 色 `#0E8A16`、説明 "Managed by /harness skill"
- `sprint` — 色 `#1D76DB`、説明 "Per-sprint work unit"

`gh label create --force` を使用。既存ラベルの色・説明は変更しない。

## GitLab 経路（v1）

各 sprint の起票予定ペイロードを `.harness/<epic>/pending-issues.md` に
書く — harness-plan が所有する epic 単位の ledger ファイル。存在しなければ
作成し、各 sprint を追記する:

```markdown
# Pending Issues (tracker=gitlab, v1 — glab 連携待ち)

## PendingIssues

- sprint-1 login: split, risk=medium, deps=[], awaiting glab
- sprint-2 signup: bundled-with=[3], risk=medium, deps=[1], awaiting glab
- sprint-3 password-reminder: bundled-with=[2], risk=low, deps=[2], awaiting glab
```

v2 で `glab issue create` を同じ body 構造で導入予定。上のペイロード形式は
v2 がそのままパースして送信できるよう選定している。

> **なぜ `shared_state.md` ではないか**: `shared_state.md` は sprint 単位
>（`sprints/sprint-<n>-<feature>/shared_state.md`）で、harness-loop が
> Planner ⇄ Generator ⇄ Evaluator の通信 ledger として所有する。
> harness-plan 実行時点では存在せず、harness-plan の責務範囲は epic 単位。
> 責務分離のため epic 単位の `pending-issues.md` を使う。

## None 経路

tracker が `none` の場合、`harness-plan` は 1 行だけ progress に追記:

```
[<ts>] tracker=none: 3 sprints planned, issues skipped. Ledger at .harness/<epic>/roadmap.md
```

API 呼び出しなし、AskUserQuestion なし。sprint の同一性は `roadmap.md` と
sprint 毎ディレクトリ名が担う。

## `_state.json` 更新

Issue 起票ステップの phase 遷移（design §9.2）:

1. **ループ開始時** に `phase = "issues-pending"` を設定。ループ途中で失敗した
   場合に resume でこのステップに復帰できるようにする。
2. **`gh issue create` 成功ごと** に `sprint_issues[<n>]` を atomic に追記する。
   バッチしない — 各書き込みは単独で resume 安全。
3. **全 sprint 作成完了（または tracker に応じてスキップ完了）後** に
   `phase = "ready-for-loop"` を設定。これが `harness-loop` への受け渡し信号。

最終状態の例:

```json
{
  "epic_issue": 142,
  "sprint_issues": {
    "1": "https://github.com/org/repo/issues/143",
    "2": "https://github.com/org/repo/issues/144",
    "3": "https://github.com/org/repo/issues/145"
  },
  "phase": "ready-for-loop",
  "next_action": "harness-loop:negotiate-sprint-1"
}
```

`harness-loop` は Boot Sequence でこれを読み、sprint イベント（開始・negotiation
ラウンド・evaluation・PR 作成）時にどの Issue にコメントすべきかを知る。

## リカバリ

Issue 作成がループ途中で失敗した場合（ネットワーク、rate limit、権限）:

- 作成済み URL は `_state.json.sprint_issues` に保持
- 失敗 sprint 番号は `progress.md` に記録: `issue-create: sprint-${n} failed: <error>`
- resume 時、重複検出（上記）で成功済み sprint は再利用、失敗分のみリトライ
- 復旧不能な部分状態は残らない — `roadmap.md` が正本、Issue は派生ビュー

## エラーハンドリング

| 状況 | 応答 |
|---|---|
| `gh` 未インストール かつ tracker=github | インストール手順とともに中断。サイレントに `none` にダウングレードしない |
| `gh auth` 無効 | `gh auth login` 案内で中断 |
| Epic issue が見つからない | 新規作成 or `--epic` 指定を問う |
| Rate limit | 60s バックオフでリトライ。3 回失敗で停止し部分状態を書く |
| 利用者が承認段階で roadmap を拒否 | Issue は 1 件も作成しない。`roadmap.md` は draft のまま |
| 同 epic 内の sprint 名衝突 | Planner が曖昧性解消された feature 名で再生成しフラグ立て |
