# Design Phase - 設計書の生成

## 概要

技術設計書（design.md）を生成するフェーズ。
requirement.md を入力として、アーキテクチャ・クラス設計・データフローを作成する。

## 実行手順

### 1. 要件ファイルの特定

```bash
find .specs -name "requirement.md" -type f
```

要件ファイルから以下を抽出:
- 機能要件（REQ-XXX）
- 非機能要件（NFR-XXX）
- 制約事項（CON-XXX）

### 2. 既存資産マップの作成

新規実装前に既存資産を確認（車輪の再発明を防止）:

```bash
# 共通コンポーネント
find . -type d \( -name "shared" -o -name "common" -o -name "components" \) -not -path "*/node_modules/*"

# 既存サービス/モジュール
find . -type f \( -name "*Service*" -o -name "*Repository*" -o -name "*Controller*" \) -not -path "*/node_modules/*"

# 認証・認可関連
find . -type f \( -name "*auth*" -o -name "*Auth*" \) -not -path "*/node_modules/*"

# データモデル
find . -type d \( -name "models" -o -name "types" -o -name "entities" \) -not -path "*/node_modules/*"
```

コード解析ツールが利用可能な場合は、シンボル・クラス・モジュール間の関係をより深く分析するために活用する。

### 3. 設計判断（AskUserQuestion 活用）

requirement.md だけでは判断できない技術的選択がある場合、AskUserQuestion で確認する。

**アーキテクチャ選択（複数パターンが妥当な場合）:**
```
Q1: "アーキテクチャパターンは？"
header: "Architecture"
options:
  - "モノリス（シンプル、小〜中規模向け）"
  - "モジュラーモノリス（将来の分離に備える）"
  - "マイクロサービス（大規模、チーム分散）"

Q2: "API設計スタイルは？"
header: "API Style"
options:
  - "REST API (Recommended)"
  - "GraphQL"
  - "tRPC（フルスタックTypeScript）"
```

**状態管理（フロントエンド）:**
```
Q1: "状態管理のアプローチは？"
header: "State"
options:
  - "サーバー状態中心（TanStack Query等）(Recommended)"
  - "グローバル状態管理（Zustand, Redux等）"
  - "フレームワーク標準のみ（Context API等）"
```

**注意:** requirement.md で技術選択が明記されている場合はスキップ。

### 4. 設計書の生成

#### 出力構造

```markdown
# 技術設計書 - [プロジェクト名]

## 1. 要件トレーサビリティマトリックス

| 要件ID | 要件内容 | 設計項目 | 既存資産 | 新規理由 |
|--------|---------|---------|---------|---------|
| REQ-001 | ユーザー認証 | AuthService | ✅既存利用 | - |
| REQ-002 | データ管理 | DataAPI | ❌新規 | 特殊要件 |

## 2. アーキテクチャ概要

### 2.1 システム構成図
[Mermaid図]

### 2.2 コンポーネント相互作用
[シーケンス図]

## 3. 技術スタック

- 言語: [言語 vX.X]
- フレームワーク: [FW vX.X]
- データベース: [DB vX.X]
- その他依存関係

## 4. モジュール・クラス設計

### [REQ-001] 機能名
> 📌 要件: "requirement.mdからの引用"

設計内容:
- クラス/モジュール構造
- パブリックインターフェース
- 依存関係

## 5. データ設計

### 5.1 データモデル
[ER図またはスキーマ定義]

### 5.2 データフロー
[データフロー図]

## 6. 技術的決定事項

| 決定項目 | 選択 | 理由 |
|---------|------|------|
| 認証方式 | JWT | ステートレス性 |
| DB | PostgreSQL | ACID保証 |

## 7. 実装ガイドライン

- コーディング規約
- テスト戦略
- デプロイ考慮事項
```

### 5. 複数視点レビュー（--personas）

7つの専門視点から設計を評価:

| ペルソナ | レビュー観点 |
|---------|-------------|
| アーキテクト | システム一貫性、拡張性、技術的負債 |
| バックエンド | API設計、データ処理、エラーハンドリング |
| フロントエンド | コンポーネント再利用性、状態管理 |
| セキュリティ | 認証認可、暗号化、脆弱性対策 |
| DevOps | デプロイ容易性、監視、スケーラビリティ |
| DBエンジニア | スキーマ最適化、インデックス、トランザクション |
| QAエンジニア | テスタビリティ、カバレッジ、自動化 |

### 6. ビジュアル設計（--visual）

生成するダイアグラム:

```mermaid
# システムアーキテクチャ
graph TB
    Client --> API
    API --> Service
    Service --> DB

# クラス図
classDiagram
    class Service {
        +method()
    }

# シーケンス図
sequenceDiagram
    User->>API: Request
    API->>Service: Process
    Service-->>API: Response

# ER図
erDiagram
    User ||--o{ Order : has
```

### 7. 保存先

```
.specs/[project-name]/design.md
```

## 設計原則

### 要件トレーサビリティ必須

- すべての設計項目は要件IDと紐付け
- 要件にない機能は設計に含めない
- 既存資産を最大限活用

### YAGNI チェック

以下は要件に明記がない限り**含めない**:

- [ ] モニタリング・監視機能
- [ ] ログ収集・分析システム
- [ ] キャッシュ層
- [ ] 非同期処理
- [ ] 管理画面・ダッシュボード
- [ ] バックアップ・リストア機能
