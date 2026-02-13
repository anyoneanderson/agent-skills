# Issue テンプレート・抽出ルール詳細

## Issue本文テンプレート

以下のテンプレートに従いIssue本文を組み立てる。
`{...}` は仕様書から抽出した値で置換する。セクションが存在しない場合はそのセクションごと省略する。

```markdown
## 概要

**⚠️ 重要: 実装を開始する前に、必ず以下の仕様書を熟読してください。**

{requirement.mdの概要セクション}

## 仕様書

`.specs/{FEATURE_DIR}/` ディレクトリ参照

- [要件定義書](../blob/{BRANCH}/.specs/{FEATURE_DIR}/requirement.md)
- [設計書](../blob/{BRANCH}/.specs/{FEATURE_DIR}/design.md)
- [タスクリスト](../blob/{BRANCH}/.specs/{FEATURE_DIR}/tasks.md)

## 主な機能

{requirement.mdから主要機能を箇条書きで抽出}
- 機能1
- 機能2
- 機能3

## 実装チェックリスト

{tasks.mdのフェーズごとにグループ化}

### フェーズ1: {フェーズ名}（{期間}）
- [ ] タスク1
- [ ] タスク2

### フェーズ2: {フェーズ名}（{期間}）
- [ ] タスク1
- [ ] タスク2

## 技術スタック

{requirement.mdの技術要件から抽出}
- 技術1
- 技術2

## 完了条件

{tasks.mdの「完了の定義」から抽出。なければ以下のデフォルト}
- [ ] すべての必須機能が実装されている
- [ ] テストが通過している
- [ ] コードレビューが完了している

## 注意事項

{tasks.mdの「注意事項」から抽出。なければ省略}
```

## Issueタイトル

```
[Feature] {FEATURE_NAME}
```

`FEATURE_NAME` の決定:
1. requirement.md の最初の `# ` 行から抽出
2. 「要件定義書」「要件定義」「Requirements」等の接尾辞を除去
3. 先頭・末尾の空白をトリム

例:
- `# メンバー管理機能 要件定義書` → `[Feature] メンバー管理機能`
- `# Authentication System Requirements` → `[Feature] Authentication System`

## 抽出ルール

### タイトル抽出

requirement.md の最初の `# ` で始まる行を取得し、以下のパターンを除去:
- `要件定義書`, `要件定義`, `仕様書`
- `Requirements`, `Specification`, `Spec`

### 概要抽出

requirement.md で `## 概要` または `## Overview` から次の `## ` までの内容を取得。
見出し行自体は除外する。

### 主要機能抽出

requirement.md から以下のパターンにマッチする行を収集:
- `### 1.`, `### 2.` ... のような番号付きセクション → セクション名を箇条書き化
- `### 機能名` のようなセクション → セクション名を箇条書き化

例: `### 1. メンバー一覧画面` → `- メンバー一覧画面`

### フェーズ・タスク抽出

tasks.md から以下の構造を解析:

```
## フェーズ1: 基盤構築（1-2日）  ← フェーズ見出し
### 1.1 型定義の作成             ← タスク見出し（チェックリスト項目に）
- [ ] サブタスク1               ← 無視（粒度が細かすぎる）
```

抽出方法:
- `## フェーズ` または `## Phase` で始まる行 → フェーズ見出し
- フェーズ内の `### ` で始まる行 → チェックリスト項目 `- [ ] {タスク名}`
- `- [ ]` のサブタスクは含めない（Issue本文の肥大化を防ぐ）

### 技術スタック抽出

requirement.md で以下のセクションを検索（優先順）:
1. `## 技術要件`
2. `## 技術スタック`
3. `## Technology Stack`
4. `## Technical Requirements`

セクション内の箇条書き項目をそのまま使用。

### 完了条件抽出

tasks.md で `## 完了の定義` または `## Definition of Done` セクションを検索。
見つからない場合はデフォルト値を使用:

```markdown
- [ ] すべての必須機能が実装されている
- [ ] テストが通過している
- [ ] コードレビューが完了している
```

### 注意事項抽出

tasks.md で `## 注意事項` または `## Notes` セクションを検索。
見つからない場合はこのセクションを省略。

## gh issue create コマンド構築

```bash
gh issue create \
  --title "[Feature] {FEATURE_NAME}" \
  --body "$(cat <<'EOF'
{組み立てたIssue本文}
EOF
)" \
  ${LABELS:+--label "$LABELS"} \
  ${ASSIGNEE:+--assignee "$ASSIGNEE"}
```

ラベルが指定されている場合: `--label "feature,spec-generated"`
担当者が指定されている場合: `--assignee "username"`

## Projectへの追加

Issue作成後、`--project` が指定されている場合:

```bash
gh project item-add {PROJECT_NUMBER} --owner {ORG} --url {ISSUE_URL}
```

`{ORG}` は `gh repo view --json owner -q '.owner.login'` で取得。

## 仕様書リンクのブランチ

仕様書へのリンクは以下の形式:
```
../blob/{BRANCH}/.specs/{FEATURE_DIR}/requirement.md
```

`{BRANCH}` の決定順:
1. `--branch` 引数
2. `.specs/.config.yml` の `default-branch`
3. CLAUDE.md のGitワークフロー設定
4. デフォルト: `main`
