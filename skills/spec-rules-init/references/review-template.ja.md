# レビュー基準クイックリファレンス

> coding-rules.md から自動抽出・要約。判断に迷う場合は coding-rules.md を参照。
>
> spec-rules-init により自動生成

## 1. セキュリティ（最優先）

{extracted_from_coding_rules: security category}

## 2. 型安全・データモデル

{extracted_from_coding_rules: code quality - type related}

## 3. フレームワークパターン

{extracted_from_coding_rules: framework specific rules}

## 4. コード品質

{extracted_from_coding_rules: code quality - general}

## 5. テスト

{extracted_from_coding_rules: testing standards}

## 6. レビュー対象外（コメント抑制可）

{auto_detected_exclusions}

## 7. レビュー出力方針

### 共通ルール
- 高影響の指摘を優先し、軽微なスタイル指摘は抑制する
- 既存コード（変更されていない行）への指摘は原則しない
- 根拠（差分、ルール、コマンド出力）がない指摘は断定しない

### 重大度判定
- **重大（セキュリティ・バグ・ドキュメント更新漏れ）**: 必ず対処が必要。修正ループで軽微に降格されない
- **改善提案（品質・可読性）**: 対処を推奨
- **軽微（スタイル等）**: 対処は任意

### 用途別の出力
- **CI レビュー（GitHub Actions）**: インラインは高確信度のみ（QUICK: 最大5件、DEEP: 最大10件）。行特定が曖昧ならまとめコメントへ
- **レビューゲート（spec-implement）**: 重大・改善提案を検出し、修正ループで解消する。投稿ではなく自己修正
- **セカンドオピニオン（cmux-second-opinion）**: 構造化レポートとして親セッションに報告

### レビューモード
- **QUICK**: 高影響のみ
- **DEEP**: 軽微な改善提案も含む

## 8. ドキュメント更新チェック — 重大度: 重大（Critical）

ドキュメント更新漏れは**重大（Critical）**指摘として扱う。修正ループで軽微に降格されず、レビューゲートを通過するにはドキュメントの更新が必須。

新機能追加・既存機能変更時に、関連ドキュメントの更新漏れがないかを確認する。

### Step 1: 主要ドキュメントファイルのチェック

まず、多くのプロジェクトに存在する主要ドキュメントを確認する:

- `README.md` および多言語版（`README.ja.md`, `README.*.md`）
- `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`
- `coding-rules.md`, `review_rules.md`
- `issue-to-pr-workflow.md`
- `docs/`, `doc/` ディレクトリ内のファイル

存在する各ファイルについて、コード変更に伴う更新が必要かを判定する。

### Step 2: 追加ドキュメントのスキャン

主要ファイル以外にも、プロジェクトをスキャンして追加のドキュメントを検出する:

```bash
# 全 Markdown ファイル（多言語版、ネストされたドキュメント、カスタムガイドも検出）
find . -maxdepth 4 -name "*.md" -not -path "*/node_modules/*" -not -path "*/.git/*" -not -path "*/vendor/*" -not -path "*/dist/*" -not -path "*/build/*" -not -path "*/.specs/*" 2>/dev/null

# API ドキュメント（OpenAPI, Swagger 等）
find . -maxdepth 4 \( -name "openapi.*" -o -name "swagger.*" -o -name "*.openapi.*" \) -not -path "*/node_modules/*" 2>/dev/null

# ドキュメントディレクトリ
find . -maxdepth 2 -type d \( -name "docs" -o -name "doc" -o -name "documentation" -o -name "wiki" \) -not -path "*/node_modules/*" 2>/dev/null
```

### Step 3: 分類とチェック

検出された各ドキュメントについて、コード変更に伴う更新が必要かを判定する:

| カテゴリ | 更新が必要なケース |
|---------|-----------------|
| プロジェクト README | 新機能追加、インストール手順変更、使用例の陳腐化 |
| プロジェクトルール | プロジェクト規約やスキル設定の変更 |
| コーディング規約 | 新ルール・パターン・ライブラリの導入 |
| ワークフロー | 開発プロセスの変更 |
| API ドキュメント | エンドポイントの追加・変更・削除 |
| 仕様書 | アーキテクチャや設計判断の変更 |
| ガイド・チュートリアル | 機能の挙動変更 |

### Step 4: 報告

変更セットに含まれていないが更新すべきドキュメントファイルを指摘する。
