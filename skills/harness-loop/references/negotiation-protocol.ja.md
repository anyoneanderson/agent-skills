# Negotiation Protocol（交渉プロトコル）

各 sprint は Generator と Evaluator の有限交渉から始まり、contract の
rubric・閾値・`max_iterations` を合意する。3 往復で合意に至らない場合は
Planner が強制裁定する。

## 参加者と書き込み権限

| Agent | 読み取り | 交渉中の書き込み |
|---|---|---|
| Generator | `contract.md`, `shared_state.md`, `feedback/evaluator-neg-<r>.md` | `feedback/generator-neg-<r>.md` |
| Evaluator | `contract.md`, `shared_state.md`, `feedback/generator-neg-<r>.md` | `feedback/evaluator-neg-<r>.md` |
| Planner | 上記すべて | `feedback/planner-ruling.md` → `contract.md` の ruling セクション |
| Orchestrator (harness-loop) | すべて | `shared_state.md/Negotiation`, `contract.md` frontmatter 凍結 |

`shared_state.md` への書き込みは Orchestrator のみ。ラウンド要約を台帳に転記
することで、sprint に対する単一の監査証跡を保持する
（詳細は [shared-state-protocol.ja.md](shared-state-protocol.ja.md)）。

## ラウンド構造

1 ラウンド = Generator 発話 → Evaluator 発話。ラウンド番号は 1 起点。
上限は `contract.max_negotiation_rounds`（デフォルト 3、`_config.yml` で上書き可）。
ただし例外として、Generator が `accept` を signal した時点でその round は
即座に resolve し、Evaluator turn は省略する。採択されるのは Evaluator の
直近提案である。

### Round N のスキーマ

各側が提案ドキュメントを出す。Orchestrator は**順次**（並列禁止）で
dispatch する。後攻は先攻の提案を参照する必要があるため。

**Generator ラウンドファイル** (`feedback/generator-neg-<r>.md`):

```yaml
---
round: <r>
role: generator
ts: <ISO-8601-UTC>
---

## Proposed contract delta

<!--
  ドラフトから変更したいフィールドのみ記述。
  変更なしなら `unchanged` と書くか省略。
-->

rubric:
  - axis: Functionality
    threshold: 0.95   # was 1.0
    reason: "login リダイレクトの flakiness。1.0 の代わりに retry harness を提案"
max_iterations: 8     # unchanged

## Trade-offs acknowledged

<!--
  delta と引き換えに Generator が譲歩する内容。
-->

- Craft 側で明示的な retry + a11y snapshot 差分検証を追加する

## Open risks

<!--
  Generator が不確実で、Evaluator に解消してほしい点。
-->

- login モーダルで Playwright a11y snapshot が決定論的か不確か。
  Evaluator の意見を仰ぎたい

## Decision

`accept` | `counter` | `escalate`
```

**Evaluator ラウンドファイル** (`feedback/evaluator-neg-<r>.md`):
同じスキーマで `role: evaluator`。

合意シグナル:

- `accept` — 相手の直近提案を明示的に受諾
- `counter` — 交渉継続。counter-proposal を同一ファイルに含める
- `escalate` — この round では合意できない。上限到達時に Planner
  裁定へ進めるためのシグナル

### ラウンド結果マトリクス

| Generator シグナル | Evaluator シグナル | 結果 |
|---|---|---|
| `accept` | skipped | Evaluator の直近提案が採択、交渉終了 |
| any | `accept` | Generator の直近提案が採択、交渉終了 |
| `counter` | `counter` | Round + 1（上限内なら）、上限なら Planner 裁定 |
| `escalate` | any | 同上 |
| any | `escalate` | 同上 |

Generator が `accept` を signal した round では、その時点で解決済みとなり、
Evaluator は同一 round で追加発話しない。採択される contract delta は
Evaluator の直近提案であり、これは上記「Generator → Evaluator の対称 pair」
原則の明示的な例外である。

両者が同一ラウンドで同じ提案を `accept` した場合、Orchestrator は
相互合意として扱う。

### Orchestrator サマリ行

各ラウンド後、Orchestrator は `shared_state.md/Negotiation` に**2 行**
（speaker 毎）を追記する:

```
- [<ts>] round=<r> agent=generator signal=<accept|counter|escalate> delta=<短い要約> file=feedback/generator-neg-<r>.md
- [<ts>] round=<r> agent=evaluator signal=<accept|counter|escalate> delta=<短い要約> file=feedback/evaluator-neg-<r>.md
```

ラウンド終了毎に `progress.md` に 1 行:

```
[<ts>] negotiation: round=<r> generator=<signal> evaluator=<signal>
```

## 3 ラウンド上限と Planner 裁定

`round == max_negotiation_rounds` に達してもどちらも `accept` を出していない場合、
Orchestrator は Planner に全交渉パケットを渡して拘束力のある裁定を依頼する。

### Planner 入力パケット

Orchestrator は Planner に以下を含む単一プロンプトを渡す:

1. `contract.md` の現ドラフト（frontmatter + acceptance scenarios）
2. 各 `feedback/generator-neg-<r>.md`（round 1..3）
3. 各 `feedback/evaluator-neg-<r>.md`（round 1..3）
4. 該当する rubric プリセット
   (`../../harness-init/references/rubric-presets.ja.md#<project-type>`)
5. 固定指示:

```
あなたは停滞した交渉を裁定する Planner です。最終 contract delta を
feedback/planner-ruling.md に書き出してください。論理的・拘束的・
軸毎に 1 つの rubric。さらなる交渉提案はしてはいけません。
```

### Planner 裁定ファイル (`feedback/planner-ruling.md`)

```yaml
---
role: planner
ts: <ISO-8601-UTC>
---

## Ruling

rubric:
  - axis: Functionality
    weight: high
    threshold: 1.0
  - axis: Craft
    weight: std
    threshold: 0.8    # redirect リスクを踏まえ 0.7 から引き上げ
  - axis: Design
    weight: std
    threshold: 0.7
  - axis: Originality
    weight: low
    threshold: 0.5
max_iterations: 10     # retry 分を吸収するため 8 から引き上げ

## Reasoning

Generator の retry harness 論は妥当。Evaluator の Craft 水準引き上げは
トレードとして受諾。

## Applies to

sprint: <N>
feature: <feature-name>
```

### 裁定後の contract 凍結

Orchestrator は:

1. 裁定内容を `contract.md` frontmatter に書き込む
2. Planner の `## Ruling` セクションを `contract.md` の
   `## Negotiation Log > ### Ruling` セクションへ逐語転記
3. `contract.status: active` に設定
4. commit: `git commit -m "harness-loop: sprint-<n> Planner ruling"`
5. `progress.md` に追記:
   ```
   [<ts>] decision: sprint-<n> negotiation ruled by Planner (rounds=3)
   ```

## 交渉中のアンチパターン（却下対象）

- **交渉ファイル内でのコード提案** — 交渉対象は rubric / threshold /
  `max_iterations` / scenario 数のみ。実装選択は SKILL flow Step 6 の領域
- **rubric 軸の勝手な追加** — v1 はプロジェクト種別のプリセット固定
- **Functionality の threshold 0.5 未満** — Principal Skinner の
  rubric-stagnation を空振りで起こす。スコープ分割を要求して却下
- **`max_cost_usd` / `max_wall_time_sec` の交渉** — これらは
  `_config.yml` の Principal Skinner caps であり sprint スコープ外。
  `/harness-init` 再構成で変更
- **`Decision` 未記載** — `Decision` 行を欠く提案は `counter` 扱い
  だが malformed としてログ

## Resume 挙動

交渉中にスキルが再起動された場合、Orchestrator は
`_state.json.phase == "negotiation"` と最大番号の
`feedback/{generator-neg|evaluator-neg}-<r>.md` ペアを読む。次のアクションは
欠けている側の発話、両者揃っていれば Round N+1、N が上限なら Planner 裁定。

すべてのラウンドファイルは書き込み後不可侵（in-place 編集禁止）。
修正が必要なら round 番号を増やして追加する（progress.md の
append-only 原則と一致）。

## テストレシピ

```bash
# 試走: Generator counter → Evaluator accept
claude -p --agent generator "counter round 1 for sprint-1/contract.md"
# → feedback/generator-neg-1.md（signal=counter）

claude -p --agent evaluator "review feedback/generator-neg-1.md and signal"
# → feedback/evaluator-neg-1.md（signal=accept）

# Orchestrator が contract 凍結
jq '.phase="impl"' .harness/_state.json > /tmp/s && mv /tmp/s .harness/_state.json
```

成功条件: `contract.md.status == "active"`、`contract.md` の
`Negotiation Log / Round 1` に両メッセージ、`shared_state.md/Negotiation`
に Orchestrator サマリ 2 行が揃う。
