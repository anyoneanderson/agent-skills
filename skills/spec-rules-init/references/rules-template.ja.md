# コーディングルール

> spec-rules-init により自動生成。
> 出典: {source_files}
> 生成日時: {timestamp}

## テスト基準

### [MUST] カバレッジ閾値
- ユニットテストカバレッジは {coverage_target}% 以上を維持すること
- 出典: {source_file}

### [MUST] テストフレームワーク
- すべてのテストに {test_framework} を使用すること
- 出典: {source_file}

### [SHOULD] テスト命名規則
- 実装ではなく振る舞いを記述する
- パターン: `{期待される振る舞い} when {条件}`

### [MAY] E2Eテスト
- 重要なユーザーフローにはE2Eテストを実施する
- フレームワーク: {e2e_framework}

## コード品質

### [MUST] Lint・型チェック
- コミット前に `{lint_command}` がパスすること
- コミット前に `{typecheck_command}` がパスすること
- 出典: {source_file}

### [MUST] 命名規則
- ファイル名: {file_naming_convention}（例: kebab-case, camelCase）
- 変数・関数: {variable_naming_convention}
- クラス: PascalCase
- 出典: {source_file}

### [SHOULD] 未使用importの禁止
- コミット前にすべての未使用importを削除すること

### [SHOULD] import形式
- {import_style} 形式のimportを使用する（例: パスエイリアス `@/`、相対パス `./`）
- 出典: {source_file}

## エラーハンドリング

### [MUST] エラーログ出力
- すべてのサービスメソッドで構造化されたエラーログを使用すること
- エラー出力には {logger} を使用する
- 出典: {source_file}

### [SHOULD] 例外メッセージ
- 例外メッセージは{exception_language}で記述する
- エラーコンテキスト（操作名、入力概要）を含める

### [MAY] カスタムエラークラス
- 異なるエラーカテゴリにはドメイン固有のエラークラスを定義する

## ドキュメント

### [MUST] 公開APIのドキュメント
- すべてのパブリックメソッドに {doc_format}（例: JSDoc, TSDoc, GoDoc）を記述すること
- @param, @returns, @throws を含める
- 出典: {source_file}

### [SHOULD] コードコメント
- コメント言語: {comment_language}
- 「何を」ではなく「なぜ」をコメントする

### [MAY] アーキテクチャ判断記録
- 重要な設計判断をADR形式で記録する

## セキュリティ

### [MUST] ログへの秘密情報出力禁止
- パスワード、トークン、APIキー、client_secretをログに出力しないこと
- 出典: {source_file}

### [MUST] 入力バリデーション
- システム境界ですべての外部入力をバリデーションすること
- ランタイムバリデーションには {validation_library} を使用する

### [SHOULD] HTTPS強制
- リダイレクトURIがHTTPSを使用していることを検証する（localhost を除く）

### [MAY] 依存関係の監査
- 依存パッケージの脆弱性チェックを定期的に実行する

## Git

### [MUST] コミットメッセージ形式
- 言語: {commit_language}
- 形式: {commit_format}（例: Conventional Commits、自由形式）
- 出典: {source_file}

### [MUST] ブランチ戦略
- 常にフィーチャーブランチで作業し、{main_branch} に直接コミットしない
- ブランチ命名: {branch_naming}（例: `feature/xxx`, `fix/xxx`）

### [SHOULD] アトミックコミット
- 各コミットは1つの論理的な変更を表すこと

---

## 出典

| ファイル | 抽出ルール数 |
|---------|-------------|
| {source_file_1} | {count_1} |
| {source_file_2} | {count_2} |

---

## プロジェクト種別ごとの推奨ルール

プロジェクトが特定のフレームワークを使用している場合、以下のルールの追加を検討してください:

### NestJS
- `[MUST]` console.log の代わりに NestJS Logger を使用する
- `[SHOULD]` モジュールベースのアーキテクチャ（機能モジュール）に従う
- `[SHOULD]` DTO バリデーションには class-validator を使用する
- `[SHOULD]` @ApiProperty には日英併記の説明を記述する

### Next.js
- `[MUST]` App Router の規約に従う（layout.tsx, page.tsx, loading.tsx）
- `[SHOULD]` デフォルトで Server Components を使い、必要な場合のみ `'use client'` を使用する
- `[SHOULD]` 最適化のため Next.js の Image, Link コンポーネントを使用する
- `[MAY]` フォーム処理に Server Actions を使用する

### React（一般）
- `[SHOULD]` 関数コンポーネントとhooksを優先する
- `[SHOULD]` コンポーネントは小さく焦点を絞る（単一責任）
- `[MAY]` 再利用可能なロジックにはカスタムhooksを使用する

### Go
- `[MUST]` コミット前に `go vet` と `golint` を実行する
- `[SHOULD]` Go の標準プロジェクトレイアウトに従う
- `[SHOULD]` すべてのエラーを明示的にハンドリングする（error戻り値を `_` で無視しない）
- `[MAY]` テーブル駆動テストを使用する

### Python
- `[MUST]` `ruff` または `flake8` の lint をパスすること
- `[SHOULD]` すべてのパブリック関数に型ヒントを使用する
- `[SHOULD]` PEP 8 の命名規則に従う
- `[MAY]` データモデルには dataclasses または Pydantic を使用する

### Express / Fastify
- `[SHOULD]` 横断的関心事にはミドルウェアを使用する
- `[SHOULD]` エラーハンドリングをエラーミドルウェアに集約する
- `[MAY]` ルートレベルのバリデーションには Zod または Joi を使用する
