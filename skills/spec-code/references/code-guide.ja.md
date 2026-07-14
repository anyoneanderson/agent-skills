# spec-code リファレンスガイド

## フィードバックファイル形式

`--feedback` オプションはレビュー結果とテスト結果の両方を受け付ける。ファイル形式は自動検出される：

### ヘッダ判定
- 最初のメタデータ行で `type: review` / `type: test` / `type: evaluate` のいずれかを宣言する
- `type: review` は spec-review の契約に従うことを意味する
- `type: test` は spec-test の契約に従うことを意味する
- `type: evaluate` は spec-evaluate の契約（受け入れ試験結果）に従うことを意味する
- ヘッダがない場合のみ、互換性維持のため見出しベースの判定にフォールバックする

### レビュー結果（spec-review から）
- `## Findings` セクションに `### Critical` / `### Improvement` / `### Minor` がある
- 各指摘は `**{rule-id}** {file}:{line} — {description}` 形式。Critical /
  Improvement の指摘には `fix_before` タグも付く
- 指摘に `fix_before` タグがある場合、修正するのは `implementation` の指摘だけ
  （Critical を優先し、次に Improvement）。`trial` / `required_check` /
  `follow_up` の指摘は先送りで、呼び出し側が持ち越す — ここでは修正しない
- `fix_before` タグの無い旧形式ファイル: Critical を優先的に修正し、次に
  Improvement に対応

### テスト結果（spec-test から）
- `## Test Cases` セクションにパス/フェイルの状態がある
- `## Completion Criteria Coverage` テーブルがある
- 失敗テストと未カバーの完了条件の修正に集中

### 受け入れ試験結果（spec-evaluate から）
- レビュー結果と同じ `## Findings` 構造（`### Critical` / `### Improvement` / `### Minor`）を使う — Critical を優先的に修正し、次に Improvement に対応。受け入れ試験の指摘に `fix_before` タグは付かず、全件が修正対象（不合格の受け入れケースは先送りできない）
- `## Blocked` セクションは無視する。blocked はセットアップ不足（例: アプリ起動レシピの欠落）であり実装の不具合ではないため、修正対象にしない

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
