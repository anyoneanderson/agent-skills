# spec-code リファレンスガイド

## フィードバックファイル形式

`--feedback` オプションはレビュー結果とテスト結果の両方を受け付ける。ファイル形式は自動検出される：

### ヘッダ判定
- 最初のメタデータ行で `type: review` または `type: test` を宣言する
- `type: review` は spec-review の契約に従うことを意味する
- `type: test` は spec-test の契約に従うことを意味する
- ヘッダがない場合のみ、互換性維持のため見出しベースの判定にフォールバックする

### レビュー結果（spec-review から）
- `## Findings` セクションに `### Critical` / `### Improvement` / `### Minor` がある
- 各指摘は `**{rule-id}** {file}:{line} — {description}` 形式
- Critical を優先的に修正し、次に Improvement に対応

### テスト結果（spec-test から）
- `## Test Cases` セクションにパス/フェイルの状態がある
- `## Completion Criteria Coverage` テーブルがある
- 失敗テストと未カバーの完了条件の修正に集中

## コミット規約

コミット時のメッセージ形式の優先順位：
1. `coding-rules.md` のコミットルール（定義されている場合）
2. `CLAUDE.md` のコミット規約（定義されている場合）
3. デフォルト: `feat(scope): {task-id} — {概要}`

## タスクの特定

`tasks.md` のタスクは以下のパターンに従う：
```markdown
- [ ] T-007: タスク説明
  - [ ] サブ条件 1
  - [ ] サブ条件 2
```

タスク ID プレフィックス（例: `T-007`, `T001`, `T-7`）で照合する。
