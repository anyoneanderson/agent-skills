# 改善の適用 — Tier 判定・自動適用・巻き戻し

retrospective が提案を生成し（`retrospective-format.ja.md`）、このファイルがそのうち
どれを自動適用してよいか・どう適用するかを決める。指針: 自動編集も人の変更と同じ
監査線（ブランチ → PR）に乗せること。そしてセキュリティ上重要な判断 —「このファイルは
自動マージして安全か」— は、提案が書いた文字列ではなく **canonical で symlink を経由
しないパス** から下す。

English version: [improve-apply.md](improve-apply.md)

## 前提（完全にスキップする条件）

- **この実行で pr 未到達** → 自動適用しない。retrospective はレポートを書き Issue を
  起票してよいが、clean な完了とのメトリクス比較が成立しない（`phases/retrospective.ja.md`
  の実行タイミング参照）。
- **`improve.skills_repo` 未設定 or 書き込み不可** → Issue 起票のみに縮退（下記
  「縮退」）。改善はスキルの **ソースリポジトリ** のみに適用し（既定
  `improve.skills_repo`）、インストール済みコピーには適用しない（§7）。
- **`improve.auto_apply: false`** → Tier 1 の提案も PR を人間レビュー待ちで残し、
  自動マージはしない。

## Tier 判定

各提案の対象パスを Tier に対応づける。Tier 1 は自動マージ、Tier 2 は人間に委ねる。
判定は生の文字列ではなく **正規化した** パス（次節）に対して行う。

| 正規化後の対象パス | Tier | 適用方法 |
|-------------------|------|---------|
| `skills/*/references/**`（下記の行を除く） | 1 | 改善ブランチ → PR → 自動マージ |
| `skills/*/references/contract*.md`（公開契約） | 2 | PR を人間レビュー待ちで残す |
| `skills/*/references/lessons.md`（lessons ファイル） | 1 | 改善ブランチ → PR → 自動マージ |
| `skills/*/SKILL.md` | 2 | PR を人間レビュー待ちで残す |
| `skills/*/references/scripts/**` | 2 | PR を人間レビュー待ちで残す |
| `docs/coding-rules.md`, `docs/review_rules.md` | 2 | PR を人間レビュー待ちで残す |

`contract*.md` は `references/` 配下でも **常に** Tier 2。他スキルが公開契約に依存する
ため、自動書き換えはそれらを壊しうる（§7）。SKILL.md と scripts はスキルの実行面
なので Tier 2。提案が1つでも Tier 2 パスに触れたら PR 全体を Tier 2 とする。

**評価順が重要:** 個別の Tier 2 行（`contract*.md`・`SKILL.md`・`scripts/**`・
`docs/*`）を、`references/**` の Tier 1 catch-all **より先に** 照合すること。さもないと
`references/` 配下の Tier 2 ファイルが Tier 1 に落ちてしまう。

### パス正規化（セキュリティ境界）

文字列マッチだけではすり抜けられる: `skills/foo/references/../SKILL.md`、symlink、
大小文字差が、Tier 2 対象を Tier 1 規則に潜り込ませて自動マージしうる。自動マージは
信頼境界なので、マッチの **前** に正規化・検証する:

`$target` は **リポジトリ相対** パス（例: `skills/foo/references/g.md`）であり、
cwd ではなく `repo_root` にアンカーする必要がある。オーケストレーターは通常、対象
*プロジェクト* を cwd に実行し `skills_repo` は別ディレクトリ（§7）のため、cwd に
アンカーすると正当な適用先も (2) の repo-root 配下チェックで全拒否される
（fail-closed なのでセキュリティ穴ではないが、REQ-020 の自動適用が機能しない）。

```bash
repo_root="$(git -C "$skills_repo" rev-parse --show-toplevel)"

# 移植性のある正規化（BSD realpath は -m/--no-symlinks 非対応。python3 を使う）。
# $target は cwd ではなく repo_root にアンカーする。
#   physical = ../ と symlink を実体の on-disk パスへ解決
#   lexical  = ../ のみ解決、symlink は展開しない
physical="$(python3 -c 'import os,sys; print(os.path.realpath(os.path.join(sys.argv[1], sys.argv[2])))' "$repo_root" "$target")"
lexical="$(python3 -c 'import os,sys; print(os.path.normpath(os.path.join(sys.argv[1], sys.argv[2])))' "$repo_root" "$target")"

# (1) 上記で両方を算出。
# (2) リポジトリルート配下であること
case "$physical/" in
  "$repo_root"/*) : ;;
  *) echo "reject: outside repo root"; exit 1 ;;
esac

# (3) symlink を経由しないこと（physical ≠ lexical なら経路に symlink）
[ "$physical" = "$lexical" ] || { echo "reject: symlink in path"; exit 1; }

# 正規化した repo 相対パスで Tier 表に照合
rel="${physical#$repo_root/}"
```

(1)〜(3) のいずれかに失敗したパスは **適用拒否**（Tier 1 に既定しない）。`rel` を
上の Tier 表に照合する。

## 行数バジェット検査（REQ-021）

LLM の自己改善は指示を追加する方向へ偏る。Tier 1 の各対象を守る: 編集後、ファイル
行数が `improve.line_budget`（既定300）を超え、**かつ** diff がほぼ純増（削除行 <
追加行 ÷ 2）なら、自動適用を拒否する。提案は置き換え/削除を伴う編集に作り直すか、
Tier 2（人間レビュー）へ降格する。

```bash
lines_after="$(wc -l < "$target")"
if [ "$lines_after" -gt "$line_budget" ] && [ "$removed" -lt $((added / 2)) ]; then
  echo "reject: 超過かつ追加のみ — 置き換え型に作り直すか Tier 2 へ降格"
fi
```

## 適用手順（REQ-020）

オーケストレーターは git/PR のみを行い、ファイル編集は **ワーカーのサブエージェント**
が行う（REQ-002 — オーケストレーターはスキルファイルを自分で編集しない）。

1. `improve.skills_repo` で改善ブランチ `improve/{feature}-{run-id}` を作る。
2. ワーカーのサブエージェントがそのブランチで提案の編集を適用する。
3. コミットする。コミット本文は **`retrospective.md` を参照**（パス + run_id）し、
   すべての自動変更を、それを正当化した証拠へ監査線でつなぐ。
4. PR を開く:
   - **Tier 1 のみ**（変更パスがすべて Tier 1、バジェット検査も通過）→ PR を自動
     マージ。
   - **Tier 2 を含む** → PR を人間レビュー待ちで残し、マージしない。

Tier 1 もブランチ → PR → マージを通す（直接 push しない）。監査の形を Tier 2 と揃え、
改悪は `git revert` 一発で戻せる（§7）。

## 縮退（書き込み可能な skills リポジトリがない）

`improve.skills_repo` 未設定 or 書き込み不可なら、何も適用しない。代わりに提案（対象・
Tier・根拠）を含む Issue を agent-skills リポジトリに起票する。書き込み権限なしでも
学びを残す。

## 巻き戻し（REQ-022）

実行ごとに機能も難度も異なるため、単発の worse 比較はノイズ。それで自動 revert すると
改善と巻き戻しが振動する。そこで revert は確信度で段階分けする:

- **自動 revert（自動マージまで）:** **同一スキル** への自己適用改善の後、**同系の
  退行**（同じ `blocker_category` 系列 **かつ** 同じフェーズ）が **2実行連続** で
  観測された場合のみ。かつ **このパイプラインが自動適用した** コミットに限る。適用と
  同じ方法（ブランチ → PR → 自動マージ）で戻す。
- **revert PR（人間承認）:** 単発の退行は revert PR の作成までに留め、人間が判断する。
- **Issue のみ:** 人間がマージした変更は自動 revert しない — revert を提案する Issue
  を起票する。

退行シグナルは `pipeline-metrics.jsonl` から読む（`retrospective-format.ja.md` の
Step 4）。このファイルはシグナルが何を許可するかだけを定義する。
