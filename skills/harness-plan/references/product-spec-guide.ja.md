# Product Spec 対話ガイド

このガイドは `harness-plan` の対話フローが `.harness/<epic>/product-spec.md`
をセクション単位で埋めるための手引きです。対象読者は Planner sub-agent（利用者ではない）。
目的は2つ:

1. Planner が roadmap を生成するのに必要な **最小限** の情報を集める。
2. **"How" の混入を防ぐ** — 仕様は価値と制約を書くものであり、実装方針を書くものではない。

テンプレートは `.harness/templates/product-spec.md`（`harness-init` が配置）。
記入順: Why → What → Out of Scope → Constraints → Success Signals。

## 基本原則 — "What, not How"

product-spec は **ユーザが体験すること** と **なぜ重要か** を書く。以下は書かない:

- フレームワーク・ライブラリ（React, Django, Prisma, Tailwind 等）
- ストレージ・スキーマ形状・テーブル名
- ファイルパス・モジュール名・クラス名
- プロトコル（REST vs GraphQL）・認証方式（JWT vs Cookie）
- デプロイ先（Vercel, AWS, on-prem）

利用者がこれらを口にしたら、Planner はこう問い直す:
「それは外部由来の強制事項（法令・既存システム・組織方針）ですか？ YES なら **Constraints** に移動。
NO なら記入しない — Implementation Loop が決めます。」

## セクション別の質問

### Why（1〜3 文）

問いかけ:
- 「我々が何もしない場合、何が壊れたまま／手が届かないままになりますか？」
- 「誰の痛みを解消するのか、そして現状どう観察できますか？」
- 「この epic 完了後、コードの外から見て何が変わりますか？」

**拒否するべき出力**: 活動の記述（「ログインページを追加する」）→ 成果に書き換え
（「一度入れた買い物カゴにメールを再入力せず戻れる」）。

### What（capability の箇条書き）

問いかけ:
- 「この epic 完了後、ユーザ／外部システムが今できないことで何ができるようになりますか？」
- 「最短の成功パスを端から端まで歩かせてください」
- 「ユーザは成功直前に何を見ますか？ 失敗時は？」

**拒否するべき出力**: UI 部品の列挙（「2 入力欄があるモーダル」）→ capability に書き換え
（「パスワードを忘れたユーザがサポートに連絡せず自力でリセットできる」）。

箇条書き目安: 3〜7 個。少なすぎると曖昧、多すぎると epic を分割すべきサイン。

### Out of Scope（明示的な除外）

問いかけ:
- 「関連するが含まれないと思う隣接機能は？」
- 「追加したい誘惑があるけれど遅延要因になるものは？」
- 「別 epic や将来四半期に属するものは？」

このセクションは sprint 分解時の scope creep に対する Planner の盾。
除外漏れは計画外 sprint に直結する。

### Constraints（外部由来の強制のみ）

問いかけ:
- 「コンプラ・法務・セキュリティ上満たすべき要件は？」
- 「連携必須・置換必須の既存システムは？」
- 「期日・予算・人員の上限は？」
- 「この領域について組織がすでに指定した技術選定は？」

**Constraints に該当しないもの**: 好み・趣味・「X が好き」。それらは
Implementation Loop 内で決めるべき事項。Planner は問い直す:
「引用元のドキュメント・チケット・ステークホルダーはありますか？」

### Success Signals（任意。成果指標）

問いかけ:
- 「本番でこれが機能していると、どうやって分かりますか？」
- 「コードは出たが epic は失敗した、と言える数値／イベントは？」

**成果** 指標（例: 「新規ユーザの 95% が 30 秒以内にサインアップ完了」）を、
**output** 指標（「PR を 3 本マージ」）より優先。成果指標は sprint 毎 rubric
の閾値設定に反映される。

このセクションは空でも構わないが、その場合は frontmatter に
`success_signals: unspecified` と明記する。Planner は閾値を保守的に（全軸 ≥ 0.7）設定する。

## 拒否すべきアンチパターン

| 症状 | 例 | 誘導 |
|---|---|---|
| How の混入 | 「Postgres で `users` テーブル」 | 削除。外部強制なら Constraints に限定的に移動 |
| UI 部品列挙 | 「青いボタンに 'Sign Up' ラベル」 | capability に書き換え（「新規訪問者がアカウント作成できる」） |
| output 指標 | 「今スプリントで PR 5 本」 | 成果指標に書き換え（「サインアップ成功率 95%」） |
| 曖昧な scope | 「onboarding 改善」 | 最短成功パスを聞く |
| 混合 epic | 「ログイン + 請求 + メール」 | product-spec を分割 |
| 否定のみ What | 「ユーザがロックアウトされない」 | 肯定形に書き換え（「60 秒以内に復旧」） |

## Planner の cross-check（spec 完成宣言前に自問）

roadmap 作成前、Planner は自問する:

1. **Why** は活動でなく具体的な問題を述べているか？
2. **What** は箇条書きごとに観察可能なユーザ成果を名指しているか？
3. **What** の各項目に対し、追加情報なしで acceptance scenario を想像できるか？
4. **Out of Scope** はこの領域で最も起こりやすい scope creep を 2〜3 件列挙しているか？
5. **Constraints** はすべて外部由来（法・既存・命令）を引用しているか？ 単なる好みはないか？
6. **Success Signals** が空なら、意図的な空欄（`unspecified` 明記）か、
   インタビュー漏れか？
7. 各セクションは自己完結しているか？ 別 Planner に渡して同じ roadmap を期待できるか？

ひとつでも NO があれば、interactive モードでは `AskUserQuestion` で再インタビュー。
非対話モードでは `.harness/progress.md` に `TODO(product-spec):` 行を追記し、
sprint 1 開始前に人間レビューを要求するフラグとして残す。

## 出力契約

最終的な `product-spec.md`:

- `.harness/<epic-name>/product-spec.md` に配置
- `.harness/templates/product-spec.md` の構造に一致
- **HTML コメントブロックは削除**（authoring 足場なので残さない）
- `harness-plan` フロー内で git commit される（sprint 前でも checkpoint commit）
- 次ステップで Planner が `roadmap.md` を生成する際に読む唯一の根拠

## リカバリ

`harness-plan` がインタビュー途中で中断された場合:

- すでに `product-spec.md` に書かれた部分回答は保持
- `_state.json.phase` は `product-spec-draft` のまま
- resume 時（Boot Sequence）に Planner が現ファイルを読み、
  `^-\s*$` で空セクションを識別し、最初の未完了セクションから再開

[resilience-schema.md](../../harness-init/references/resilience-schema.md) の
3 点復元セットと整合する設計。
