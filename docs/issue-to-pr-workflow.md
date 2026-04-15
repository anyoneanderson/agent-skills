# Issue to PR ワークフローガイド

> spec-workflow-init により自動生成されました。
> 生成日時: 2026-04-08

## ワークフロー概要

```mermaid
graph TB
    A[Issue分析] --> B[ブランチ作成]
    B --> C[環境構築]
    C --> D[段階的実装]
    D --> E[テスト]
    E --> F[品質ゲート]
    F --> G[PR作成]
    G --> H[CI/CD確認]
```

## 開発環境

- **言語 / フレームワーク**: Markdown / Skill definitions
- **パッケージマネージャ**: なし
- **コンテナ**: なし
- **データベース**: なし
- **テストフレームワーク**: なし
- **CI/CD**: なし
- **ブランチ戦略**: Git Flow (feature → develop → main)
- **ブランチ命名**: `feature/{issue}-{slug}`
- **PRターゲット**: `develop`
- **開発スタイル**: Implementation First

## 1. Issue分析とセットアップ

### Issue情報の取得

```bash
gh issue view {issue_number}
```

Issueを注意深く読み、以下を特定する:
- 受け入れ基準
- 技術的な制約
- 関連するIssueやPR

### 仕様書の確認

```bash
ls .specs/{project_name}/
cat .specs/{project_name}/requirement.md
cat .specs/{project_name}/design.md
cat .specs/{project_name}/tasks.md
```

### featureブランチの作成

```bash
git checkout develop
git pull origin develop
git checkout -b feature/{issue_number}-{slug}
```

## 2. 環境構築

特別な環境構築は不要です。

## 3. 段階的実装

### Phase 1: 分析と設計

- 関連するソースコードを読み、既存のパターンを理解する
- 依存関係と影響範囲を特定する
- 実装方針を計画する

### Phase 2: コア実装

コーディングルールに従って機能を実装する。

### Phase 3: コードレビューゲート

coding-rules.md に基づいて実装コードをレビューする。

> review_rules.md が未生成です。`spec-rules-init --with-review-rules` で生成するとレビュー基準が強化されます。

#### レビュー観点
- review_rules.md（または coding-rules.md）に定義された重大度別チェック（セキュリティ、型安全、パターン準拠等）
- coding-rules.md の [MUST] ルール違反がないか
- レビュー対象外ファイル（review_rules.md で定義）はスキップ

#### レビュー結果の判定

| 重大度 | 検出時のアクション |
|--------|-----------------|
| 重大（セキュリティ・バグ） | 即修正 → 再レビュー |
| 改善提案（品質・可読性） | 修正 → 再レビュー |
| 軽微（スタイル等） | ログのみ、続行可 |

#### 修正ループ（最大3回）
1. レビューで問題を検出
2. 問題箇所を修正
3. 修正箇所のみ再レビュー
4. 繰り返し（最大3回まで）
5. 3回目で未解消の改善提案 → 「軽微」に降格して続行
6. 3回目で未解消の重大指摘 → ユーザーに判断を委ねる
7. レビューパス → 次の Phase へ

### Phase 4: テスト実装

実装した機能のテストを作成する。

### Phase 5: テストレビューゲート

テストコードをレビューする。コードレビューゲートと同じ修正ループ構造を適用。

#### テスト固有のレビュー観点
- カバレッジが完了条件を満たしているか
- エッジケース・エラーパスのテストがあるか
- テストの独立性（他のテストに依存していないか）
- AAA パターン（Arrange → Act → Assert）に従っているか

#### レビュー結果の判定・修正ループ

（Phase 3 と同じ判定テーブル・修正ループを適用）

### Phase 6: 品質ゲート

全テストが通過し、Lintチェックがパスすることを確認する。

## 4. テスト

### API E2Eテスト

検証項目:
- 全APIエンドポイントが期待通りのレスポンスを返す
- エラーケースが適切に処理される
- 認証・認可が正しく動作する

## 5. PR作成と品質ゲート

### PR作成前チェックリスト

- [ ] 全テスト通過
- [ ] Lint通過

### PR作成

```bash
gh pr create --base develop --title "feat: {description} (closes #{issue_number})" --body "## 概要
- {summary_points}

## テスト計画
- [ ] ユニットテスト追加・更新
- [ ] API E2Eテスト検証済み

## 関連
- Closes #{issue_number}
- 仕様書: .specs/{project_name}/
"
```

## 6. CI/CD確認

### CIパイプラインの監視

```bash
gh run list --limit 5
gh run watch
```

### エラー復旧

CIが失敗した場合:

1. 失敗したステップを確認:
   ```bash
   gh run view {run_id} --log-failed
   ```
2. ローカルで問題を修正
3. 修正をプッシュ:
   ```bash
   git add -A && git commit -m "fix: CI失敗を修正" && git push
   ```
4. CIを再度監視

## エージェントロール（オプション）

### マルチエージェント役割分担戦略

各工程を専門のエージェントに委任する:

| フェーズ | 実装者 | テスター | レビュアー |
|---------|--------|---------|-----------|
| 分析 | 設計レビュー | テスト計画 | - |
| 実装 | コード作成 | テスト作成 | - |
| レビュー | - | - | コード＋テストレビュー |
| 品質ゲート | - | 全テスト実行 | 最終確認 |

### ロール割り当て

| ロール | エージェント | AI | 責務 |
|--------|-------------|-----|------|
| 実装者 | workflow-implementer | claude | coding-rules.md に従った実装コード作成 |
| レビュアー | workflow-reviewer | claude | coding-rules.md 基準のコードレビュー |
| テスター | workflow-tester | claude | テスト作成・実行、カバレッジ確認 |

### エージェント定義ファイル

- エージェント定義ファイルは生成しません。必要に応じて手動設定してください。

## ディスパッチ戦略

- **方式**: cmux
- **実装・テスト**: cmux-delegate で別ペインの Claude Code に委任
- **レビュー**: cmux-second-opinion で別AI（Codex等）に委任
- **前提条件**: CMUX_SOCKET_PATH が設定されていること

### cmux ディスパッチのフロー

1. `CMUX_SOCKET_PATH` を確認
2. cmux-delegate で実装者/テスターを別ペインに起動
3. 実装/テスト完了を検知
4. cmux-second-opinion でレビューを別AIに委任
5. 結果を統合してPR作成

---

> このワークフローは spec-workflow-init で生成されました。プロジェクトの成長に合わせてカスタマイズしてください。
