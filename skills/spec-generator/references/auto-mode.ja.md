# Auto Mode - GitHub Issue からの無対話生成

## 概要

auto モードは GitHub Issue を入力として、仕様3点セット（requirement.md・
design.md・tasks.md）と test.md を**一切の対話なしで**生成する。標準の full
ワークフローの無対話版であり、ユーザーに質問する代わりに Issue を要求の情報源
として読み、未解決の曖昧さをすべて前提条件として記録する。

呼び出し: `--auto --issue <n>`（別リポジトリの Issue の場合は `--repo <owner/name>`）

**厳守ルール**: auto モードでは、いかなる時点でも AskUserQuestion を呼ばない。
人間はループにいない。曖昧さは質問ではなく前提条件（`ASM-XXX`）を書くことで
解消する。

## 実行手順

### 1. Issue の取得

GitHub CLI で Issue のタイトル・本文・ラベルを取得する:

```bash
gh issue view <n> --json number,title,body,labels
```

対象リポジトリを指定する場合は `--repo <owner/name>` を追加する。

エラーハンドリング:
- `gh` が未認証、または Issue が存在しない場合は停止して失敗を報告する
  （内容を捏造しない）。プロジェクトの git/GitHub アカウント手引きにある
  アカウント確認手順を提示する。

### 2. feature 名の導出

`.specs/{feature}/` ディレクトリ名を **Issue タイトル**から英語ケバブケースに
変換して生成する:

- "Add CSV export to reports" → `add-csv-export-to-reports`
- "ユーザー認証を追加" → 意図を訳してからケバブケース → `user-authentication`
- issue トラッカーのノイズ（先頭の `[Feature]`、絵文字、末尾の句読点）を除去する。

短く説明的な名前にする。タイトルが空なら `issue-{n}` にフォールバックする。

### 3. 4ファイルの生成

full ワークフローの生成ロジックを Issue 本文を要求の情報源として実行する。
順序は requirement.md → design.md → tasks.md → test.md。対話パスと同じ参照
ファイル（`init.md`・`design.md`・`tasks.md`・`test-plan.md` と各 `.ja` 版）を
使う。

**YAGNI 原則**（SKILL.md 参照）を適用する: Issue が求めるものだけを作る。Issue
に書かれていない認証・分析・国際化・インフラを足さない。

### 4. 曖昧さを前提条件として記録（質問の代替）

対話パスなら AskUserQuestion を呼ぶすべての箇所を、代わりに**前提条件**にする。
requirement.md の `## 5. 前提条件` に `ASM-XXX` ID と一行の根拠を添えて書く:

```markdown
## 5. 前提条件
[ASM-001] 技術スタック: Issue はフレームワークを指定していないため、リポジトリの
既存スタック（検出結果: Next.js + PostgreSQL）を前提とする。
[ASM-002] スコープ: 「エクスポート」は CSV のみを指すと前提する。他形式は要求が
あるまでスコープ外。
```

ルール:
- デフォルトを黙って選ばない — 推論した判断はすべて明示的な `ASM` にする。
  これによりレビュアーが各推測を確認・上書きできる。
- 技術選択を推論するときは、リポジトリの既存の慣習を優先する（汎用デフォルトを
  仮定せずコードベースから検出する）。
- Issue が曖昧すぎて一貫した仕様を作れない場合でも、4ファイルは生成し、曖昧さを
  前提条件として可視化する。質問で止めない（仕様 ASM-002: auto モードは十分具体的
  な Issue を前提とする）。

### 5. 出力

```
.specs/{feature}/
├── requirement.md
├── design.md
├── tasks.md
└── test.md
```

言語は Issue の言語に従う（日本語 Issue → 日本語ドキュメント）。SKILL.md の
Language Rules に準拠する。

## 完了後

auto モードは次アクションを尋ねない。生成したファイルパスと書き出した前提条件の
一覧を報告し、呼び出し元（パイプラインを続けるオーケストレーター等）へ制御を返す。

## チェックリスト

1. [ ] AskUserQuestion を一度も呼んでいない
2. [ ] 4ファイルすべて生成（requirement.md・design.md・tasks.md・test.md）
3. [ ] feature 名が Issue タイトル由来のケバブケースになっている
4. [ ] 推論した判断がすべて requirement.md に `ASM-XXX` として記録されている
5. [ ] 出力言語が Issue の言語と一致している
