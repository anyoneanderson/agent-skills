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

## 7. 投稿方針

- インラインは高確信度のみ（行・根拠・修正案が揃う場合）
- 行特定が曖昧ならまとめコメントへ回す
- 高影響の指摘を優先し、軽微なスタイル指摘は抑制する
- 既存コード（変更されていない行）への指摘は原則しない

### 信頼度ベースの投稿制御

- **高（80+）**: インラインコメントとして投稿可
- **中（50-79）**: まとめコメントに含める（「確認をお勧めします」の表現）
- **低（50未満）**: 投稿しない

### レビューモード

- **QUICK**: 高影響のみ。インライン最大5件
- **DEEP**: 軽微な改善も含む。インライン最大10件
