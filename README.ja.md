# agent-skills

仕様駆動開発のための再利用可能なAIエージェントスキル集。

[English version](README.md)

## スキル一覧

| スキル | 説明 |
|-------|------|
| [spec-generator](skills/spec-generator/) | 会話やプロンプトからプロジェクトの要件定義書・設計書・タスクリストを生成 |
| [spec-inspect](skills/spec-inspect/) | 仕様書の品質を検証し、実装前に問題を検出 |
| [spec-to-issue](skills/spec-to-issue/) | 仕様書から構造化されたGitHub Issueを自動生成 |

## インストール

```bash
# 全スキルをインストール
npx skills add anyoneanderson/agent-skills -g -y

# 個別にインストール
npx skills add anyoneanderson/agent-skills --skill spec-generator -g -y
npx skills add anyoneanderson/agent-skills --skill spec-inspect -g -y
npx skills add anyoneanderson/agent-skills --skill spec-to-issue -g -y
```

## クイックスタート

### 仕様書を生成する

```
> 要件定義を作って
> todo-appの設計書を作成して
> todo-appのタスクリストを作って
> ECサイトの仕様を全部作って
```

### 仕様書の品質を検証する

```
> 仕様書を検査
> 品質チェック
> 仕様を検証
```

### 仕様書からGitHub Issueを作成する

```
> 仕様書をIssueにして
> specからIssue作成
```

## 仕組み

1. **spec-generator** が `.specs/{project}/` に構造化された仕様書を生成:
   - `requirement.md` — 要件定義書
   - `design.md` — 技術設計書
   - `tasks.md` — 実装タスクリスト

2. **spec-inspect** が仕様書の品質を検証:
   - 要件ID整合性の検証
   - 必須セクションや矛盾の検出
   - 曖昧な表現の識別
   - 検査結果を `inspection-report.md` に生成

3. **spec-to-issue** が `.specs/{project}/` を読み取り、チェックリスト・仕様書リンク・完了条件を含むGitHub Issueを作成。

## 互換性

[SKILL.md](https://skills.sh) フォーマット対応の全エージェントで動作:
Claude Code, Cursor, Codex, Gemini CLI, OpenCode など。

## ライセンス

[MIT](LICENSE)
