# Pipeline Config テンプレート — .specs/pipeline.yml

このファイルは spec-workflow-init が書き出す既定の `.specs/pipeline.yml` と、その
生成規則を定義する。`pipeline.yml` は spec-orchestrate が読む担当割り・アプリ起動
レシピの設定であり、完全なスキーマは spec-orchestrate の
`references/pipeline-config.ja.md` にある。

English: [pipeline-yml-template.md](pipeline-yml-template.md)

## 生成規則

1. `.specs/pipeline.yml` が既にあれば**上書きしない**。既存パスを報告して先へ進む
   （ワークフローファイルと同じ冪等ルール）。
2. `.specs/` ディレクトリが無ければ先に作る。
3. 下記テンプレートをそのまま書き出す。単体で完結しており、対話やプロジェクト固有の
   質問は不要。プロジェクトはファイルを編集して調整する。

## テンプレート

以下の内容をそのまま `.specs/pipeline.yml` に書き出す:

```yaml
# .specs/pipeline.yml — spec-orchestrate の担当割りとアプリ起動レシピ。
# 運転記録とは違い、これはコミットしてよい設定ファイル（.specs/.gitignore の運転記録
# パターンには一致しない）。下の role 値を編集すれば担当が変わる — 例えば全 role を
# `claude` にすれば軽量運用になる。

roles:
  spec_author: claude       # requirement / design / tasks / test.md を書く
  spec_reviewer: codex      # 生成した仕様の敵対的レビュー
  impl_ui: claude           # 利用者向け画面・コンポーネントを作る
  impl_backend: codex       # API・ビジネスロジック・データアクセスを作る
  impl_test: codex          # テストコードと fixture を書く
  e2e_runner: claude        # 受け入れテスト計画を実行する（spec-evaluate）

# app: 受け入れテスト用の起動レシピ。test.md に playwright 項目があるときだけ必須。
# 使うときにコメントを外して埋める。
# app:
#   start: "npm run dev"          # アプリを起動するコマンド
#   url: "http://localhost:3000"  # evaluator が操作する基底 URL
#   ready_pattern: "ready in"     # 起動完了を示すログ行
#   stop: "auto"                  # auto = 起動したプロセスを kill。他は停止コマンド
#   auth: none                    # none、または認証手順を書いた references パス

limits:
  role_swap_max: 1          # draft 着地までに許す裁定のロール入れ替え上限

# improve: retrospective の自動改善。パイプラインに自身の学びを適用させたいときに
# 有効化する。未設定なら改善は Issue 起票に縮退する。
# improve:
#   skills_repo: "~/path/to/agent-skills"
#   auto_apply: true
#   line_budget: 300
```

## 値の説明

- **roles** — 各値は `claude` か `codex`。6キーは仕様作成・仕様レビュー・実装3種
  （`ui` / `backend` / `test`）・受け入れ実行をカバーする。値を編集すればその作業の
  担当が変わり、他に変更は要らない。
- **app** — spec-evaluate が `playwright` 項目を駆動する起動レシピ。多くのプロジェクト
  は最初 UI 項目が無いため全行コメントで出す。spec-orchestrate は `app` 不在を「起動
  レシピなし」として扱う。
- **limits.role_swap_max** — 裁定のロール入れ替え上限（既定 1）。
- **improve** — retrospective の自己改善ブロック。コメントで出す。未設定なら
  retrospective の改善は Issue 起票に縮退する。

## awk 読み取りとの互換

spec-orchestrate は YAML パーサを使わず、フラットな `roles:` ブロックを起点にした
awk 流儀で role を読む（`pipeline-config.ja.md` 参照）:

```bash
awk '/^roles:/{f=1;next} f&&/^[a-z]/{exit} f&&/spec_reviewer:/{print $2}' "$pipeline"
```

テンプレートはこれと互換を保つ:

- role 行はインデントされ、値が空白区切りの2番目のフィールドにあるため、末尾に `#`
  コメントが付いても `print $2` は値を返す。
- 各キーの注記は同一行の**末尾**コメントにし、`role_key:` トークンを繰り返すコメント
  行は作らない（パターンが誤って一致するため）。
- ブロックは次の非インデントキーで終わる。`app:` はコメントアウトされているため、
  awk は非インデントの `limits:` まで読んでそこで抜ける — 6つの role をすべて読んだ後。
