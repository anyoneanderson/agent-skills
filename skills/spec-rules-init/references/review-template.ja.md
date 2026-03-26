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
- **重大（セキュリティ・バグ）**: 必ず対処が必要
- **改善提案（品質・可読性）**: 対処を推奨
- **軽微（スタイル等）**: 対処は任意

### 用途別の出力
- **CI レビュー（GitHub Actions）**: インラインは高確信度のみ（QUICK: 最大5件、DEEP: 最大10件）。行特定が曖昧ならまとめコメントへ
- **レビューゲート（spec-implement）**: 重大・改善提案を検出し、修正ループで解消する。投稿ではなく自己修正
- **セカンドオピニオン（cmux-second-opinion）**: 構造化レポートとして親セッションに報告

### レビューモード
- **QUICK**: 高影響のみ
- **DEEP**: 軽微な改善提案も含む

## 8. ドキュメント更新チェック

コード変更時に、関連ドキュメントの更新漏れがないかを確認する。

チェック対象:
- **README.md** — 新機能追加時にインストール手順・使用例・仕組みの説明が更新されているか
- **CLAUDE.md / AGENTS.md** — プロジェクトルールやスキル設定の変更が反映されているか
- **coding-rules.md** — 新しいルールやパターンが追加されているか
- **issue-to-pr-workflow.md** — ワークフロー変更が反映されているか
- **API ドキュメント** — エンドポイント追加・変更時に更新されているか
- **.specs/ 内の仕様書** — 設計変更が requirement.md / design.md / tasks.md に反映されているか

{auto_detected_doc_targets}
