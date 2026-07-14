# フェーズ: spec_generate

spec-generator を planner として起動し、仕様3点セットと受け入れテスト計画を生成
（または修正）する。初回に走り、inspect・spec_review・approval が修正のため差し戻す
たびに再度走る。

## 入力

- 初回: intake の出力（manual の要求、または auto の整形済み Issue）。
- 再入（修正）: 差し戻しの原因となった findings — inspect の findings、spec_review
  の `fix_before: implementation` findings（または裁定からの構造変更の指令）、
  manual の承認フィードバック — と、直前ラウンドまでの変更概要。
- `spec_author` ロール → バックエンド解決（`../role-dispatch.ja.md`）。

## アクション

1. spec-generator を planner として起動（`spec_author` バックエンド）。
   - auto: spec-generator の auto モード（`--auto --issue <N>`）を使う。
     AskUserQuestion を呼ばず、曖昧箇所は ASM として記録する。
   - 再入: findings を修正指示として渡す（新規生成ではない）。
2. planner が `requirement.md` / `design.md` / `tasks.md` / `test.md` を
   `.specs/{feature}/` に書く。オーケストレーターはこれらを書かない。

**並行性・順序性の規範（planner への指示に必ず含める）:** 並行実行や実行順序に関わる
振る舞いは、**守るべき不変条件を短く定義**し（例:「新しいレビューの開始後は、過去の
成功判定をマージ条件として使わない」）、実装とテストにその不変条件を守らせる形で仕様化
する。**実行順序の全列挙を仕様書に書かない。** レビューで順序の穴が指摘されたら、状態や
決定表を1つ足すのではなく、不変条件の定義を見直す。順序を列挙するほど仕様が伸び、伸びた
仕様が新しい不整合を生む — この規範はその肥大の連鎖を止めるためにある。

## 出力

- `.specs/{feature}/` の仕様3点セット（`requirement.md` / `design.md` /
  `tasks.md`）と `test.md`。planner が書く。

## 検証

- 4ファイルすべてが存在し非空である。
- `test.md` が `type: test-plan` を持ち、各項目に検証方法がある。
- `tasks.md` の各タスクに `kind:` ラベル（ui / backend / test）がある。
- いずれか欠落はワーカー失敗: 1回再実行し、なお欠落なら blocked とする。

## state 更新

- `phase` を `inspect` にする。
- `completed_phases` に `spec_generate` を追加（再入をまたいで冪等）。
- findings 起点の再入では、修正のきっかけとなったラウンド結果を記録する（後続
  フェーズの停滞検知が履歴を読めるように）。

## 遷移

- 仕様セット + test.md を書き検証済み → **inspect**
