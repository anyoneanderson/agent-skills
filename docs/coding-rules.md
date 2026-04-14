# コーディングルール

> spec-rules-init により自動生成。
> 出典: AGENTS.md, docs/skill-style-guide.md
> 生成日時: 2026-04-08

## テスト基準

### [MUST] SKILL.md プレサブミットチェック
- `SKILL.md` フロントマターの `name` がディレクトリ名と一致すること
- 参照されているすべてのファイルが存在すること
- ハードコードされた MCP ツール名がないこと（例: `mcp__serena__`, `Context7`）
- SKILL.md が 500 行以下であること
- 出典: AGENTS.md (L70-75)

### [SHOULD] テスト命名規則
- 実装ではなく振る舞いを記述する
- パターン: `{期待される振る舞い} when {条件}`

## コード品質

### [MUST] ディレクトリ命名規則
- スキルディレクトリ名は kebab-case を使用すること
- 出典: AGENTS.md (L21)

### [MUST] SKILL.md フロントマター形式
- `name`: ディレクトリ名と完全一致すること
- `description`: 1024 文字以下。トリガーフレーズを英語・日本語で含めること
- `license`: 特段の理由がなければ `MIT` を使用すること
- 出典: AGENTS.md (L26-48)

### [MUST] SKILL.md 本文は英語で記述
- セクションヘッダー、チェック/ステップ説明、検出パターン、コードコメントすべて英語
- 出典: AGENTS.md (L55), docs/skill-style-guide.md (L7-14)

### [MUST] セクションヘッダーは英語
- すべてのヘッダーを英語で記述する（`## Execution Flow`, not `## 実行フロー`）
- 出典: docs/skill-style-guide.md (L90-101)

### [MUST] Language Rules セクション必須
- すべての SKILL.md に `## Language Rules` セクションを含めること
- 自動言語検出 → 同一言語で出力するルールを定義
- 出典: docs/skill-style-guide.md (L33-43)

### [MUST] AskUserQuestion はバイリンガル
- すべての AskUserQuestion テキストを英語 / 日本語の両方で記述すること
- 形式: `"English text" / "日本語テキスト"`
- 出典: docs/skill-style-guide.md (L48-55)

### [MUST] MCP ツール名のハードコード禁止
- ツール名や MCP サーバー参照をハードコードしない
- 汎用的な説明を使用すること
- 出典: AGENTS.md (L62)

### [MUST] SKILL.md は 500 行以下
- SKILL.md のファイル行数を 500 行以下に保つこと
- 出典: AGENTS.md (L63)

### [MUST] AskUserQuestion を使用
- 対話的な判断には AskUserQuestion を使用し、自由記述プロンプトは使用しないこと
- 出典: AGENTS.md (L64)

## エラーハンドリング

### [SHOULD] エラーメッセージ
- エラーメッセージは英語で記述する
- エラーコンテキスト（操作名、入力概要）を含める

### [SHOULD] エッジケースの考慮
- 配列が空、ファイルが存在しない、パスが不正等の場合を考慮する

## ドキュメント

### [MUST] バイリンガルパターン
- `*.md` — 英語版（プライマリ）
- `*.ja.md` — 日本語版
- 出典: AGENTS.md (L50-53)

### [MUST] リファレンスファイルのパターン
- `references/*.md` / `references/*.ja.md` パターンに従うこと
- 出典: docs/skill-style-guide.md (L66-68)

### [MUST] タイトル形式
- 形式: `# skill-name — Short Description`
- kebab-case のスキル名、em ダッシュ、簡潔な英語の説明
- 出典: docs/skill-style-guide.md (L74-78)

### [SHOULD] セクション順序
1. フロントマター (`---`)
2. タイトル (`# skill-name — Description`)
3. 簡単な紹介（1-2文）
4. `## Language Rules`
5. コアセクション (`## Execution Flow`, `## Options` 等)
6. `## Error Handling`
7. `## Usage Examples`（任意）
- 出典: docs/skill-style-guide.md (L82-88)

### [MUST] README 更新
- 新しいスキルを追加した場合、`README.md` と `README.ja.md` のスキルテーブルを更新すること
- 出典: AGENTS.md (L24)

### [SHOULD] コードコメント
- コメント言語: 英語
- 「何を」ではなく「なぜ」をコメントする

## セキュリティ

### [MUST] MCP ツール名のハードコード禁止
- ハードコードされた MCP ツール名はセキュリティ・互換性リスクとなる
- `mcp__serena__`, `Context7` 等の直接参照を避け、汎用的な説明を使用する
- 出典: AGENTS.md (L62, L74)

## Git

### [MUST] コミットメッセージ形式
- 形式: Conventional Commits（`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`）
- 言語の決定順序:
  1. CLAUDE.md / AGENTS.md / issue-to-pr-workflow.md に言語指定がある場合はそれに従う
  2. 上記に指定がない場合は、該当 .specs/ ディレクトリ内の仕様書の記述言語に合わせる
  3. いずれもない場合: 英語

### [MUST] ブランチ戦略
- 常にフィーチャーブランチで作業し、develop に直接コミットしない
- ブランチ命名: `feature/{issue}-{slug}`（例: `feature/42-add-auth`）

### [SHOULD] アトミックコミット
- 各コミットは1つの論理的な変更を表すこと

---

## 出典

| ファイル | 抽出ルール数 |
|---------|-------------|
| AGENTS.md | 12 |
| docs/skill-style-guide.md | 8 |
