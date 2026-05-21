# Roadmap 生成ガイド

`product-spec.md` 完了後、Planner は `.harness/<epic>/roadmap.md` を生成する。
これは epic の sprint 分解と sprint 毎の `bundling` フラグを含む。
Issue 起票と sprint ループを駆動するのは product-spec ではなくこのファイル。

## パイプライン

```
product-spec.md  →  Planner  →  roadmap.md  →  sprint 毎 contract.md
                                    │
                                    └─ issue-create.md（次ステップ）
```

Planner は 3 パスで処理:

1. **分解**: What 箇条書きを sprint 候補に（1 capability ≈ 1 sprint）。
2. **bundling 判定**: 下記結合ヒューリスティックで。
3. **順序付け**: 依存関係（prerequisite 優先）と risk（peer 選択時は flaky 優先）。

## 分解ルール

| ルール | 理由 |
|---|---|
| 1 sprint = 1 つの **end-to-end ユーザ可視 capability** | acceptance scenario を曖昧にしない |
| 複数 What 項目にまたがる sprint は分解失敗 | sprint を分割するか、What 項目を統合すべき |
| 「インフラ sprint」禁止 | インフラは手段。必要とする最初の sprint に吸収。**Greenfield 例外**: `harness-plan` Step 3.5 が YELLOW / RED を返した時のみ `n=0` の `type: foundation` sprint を 1 本だけ許容。[foundation-sprint-guide.ja.md](foundation-sprint-guide.ja.md) 参照 |
| 「リファクタ sprint」禁止 | リファクタは内部。capability 提供の道具として行う |
| 最大 sprint 数: 6（目安） | これ以上は initiative 規模 — epic 分割を利用者に提案。`n=0` の foundation-sprint は cap の対象外 |

capability が下準備（例: 認証機能に先立つ auth middleware）を要求する場合、
下準備はその capability の sprint 1 **内部** に含める — 先行する「sprint 0」を作らない。

## Bundling 判定

2 つの sprint が **bundling 候補** になるのは、構造的に結合しており、別 PR で
出すと手戻りが発生する場合。Planner は以下 4 軸を確認し、**いずれか 1 つ** でも
該当すれば `bundled` にマーク:

| 結合軸 | Bundling シグナル |
|---|---|
| **スキーマ / データモデル** | テーブル・ドキュメント形状・コアエンティティを両 sprint が書く |
| **認証 / セッション** | 同じ認証フローやセッション状態遷移を共有 |
| **UI レイアウト / コンポーネントツリー** | レイアウトシェル・ナビ根・コンポーネント階層を両 sprint が変更 |
| **契約面（contract surface）** | 両 sprint が変更する公開 API シグネチャやイベントスキーマを共有 |

デフォルトは `split`。ヒューリスティックが明確な書ける理由とともに発動した時のみ
bundle する — `bundling_reason` フィールドは bundle 時 **必須**。

### 事例

| シナリオ | 判定 | 理由 |
|---|---|---|
| `login` + `signup`（共通 `UserRecord`） | `bundled` | 両方が同じ認証スキーマを書く。別 PR はモデル二重変更 |
| `login` + `user-profile-edit` | `split` | profile は user record を読むだけ。認証フィールドに同時書き込みなし |
| `password-reminder` + `signup`（共通メールテンプレ） | `bundled` | 共通テンプレ契約。分離すると分岐誘発 |
| `billing-page` + `notification-preferences` | `split` | 独立面、異なるデータオーナー |
| `dashboard` + `dashboard-widget-a` | `bundled` | レイアウトシェルと widget は同時に出すしかない |

### bundle group ルール

- bundle は結合グラフの **連結成分**: A⇔B で bundle かつ B⇔C で bundle なら
  {A, B, C} が 1 つの bundle group。
- bundle 内全 sprint は group 内最後の sprint で **1 PR** として出る。
- bundle PR タイトルは全 feature 列挙（`feat: login + signup + password-reminder`）。
- bundle サイズ上限: 3 sprint。それ以上は分解を再検討 — epic が密結合すぎるので
  上流で再設計すべき。

## Backend 推奨判定

各 sprint について、Planner は feature 性質に最適な Generator backend
（`claude` / `codex_cli` / `codex_cmux`）を rubric で判定し、
**単一の primary recommended** を導出する。`interactive` mode の場合は
`AskUserQuestion` で user に確認する。確定値は `roadmap.md` の
`sprints[n].generator_backend` に書込む。

### 適性 rubric

| Feature 性質 | 推奨 primary | 備考 / secondary 候補 |
|---|---|---|
| UI-heavy: frontend / component / CSS / design system / micro-interaction / page layout | `claude` | 審美判断 / UX copy / ブランド tone |
| Backend logic: API / schema / auth / validation / DB | `codex_cli` | 型厳密性 / 防御的実装で rubric を pass しやすい。design 重視 sprint なら secondary として `claude` を AskUserQuestion options に追加（primary は `codex_cli` 固定）|
| Infra / CI/CD / docker / shell / workflow yaml / cloud deploy | `codex_cli` | pipeline / config 系の運用配慮 |

primary は常に **単一値** — `claude` または `codex_cli`（`codex_cli (or claude)`
のような複数値は禁止）。`codex_cmux` は rubric primary には **含めず**、
AskUserQuestion の選択肢として常に user に提示する（hybrid: UI + backend
同等重視 や cross-check 用途で user が選ぶ）。

### user 確認フロー（interactive mode）

各 sprint について Planner は `AskUserQuestion` を組み立てる:

```
sprint n の options:
  1. <primary recommended> (Recommended) — <rubric 根拠>
  2. <_config.yml.generator_backend> — harness-init で選択した epic default
  3. <secondary or 残り enum 値> — （重複は除去）
```

`recommended == epic default` のときは item 2 を省略（重複排除）。
bundle peer は primary peer の選択を継承するため、bundle 単位で 1 質問
（peer 毎には聞かない）。`sprints > 4` の epic では複数 round に分割する
（AskUserQuestion は 1 round 4 質問まで）。

### non-interactive mode

`continuous` / `autonomous-ralph` / `scheduled` mode では Planner は
`AskUserQuestion` を **呼ばない**。rubric primary を auto-confirm して
`roadmap.md` に直接書込む。user は後から `roadmap.md` を編集 +
`/harness-plan --replan` で変更可能。

### legacy bypass

`_config.yml.sprint_level_generator_override == false` の場合、Planner は
rubric 判定と AskUserQuestion を **完全 skip** する。各 sprint は
`generator_backend: null` で書込まれ、`harness-loop` 実行時は
`_config.yml.generator_backend` に fallback する（現行挙動を維持、
後方互換）。

## `roadmap.md` 出力形式

Planner は frontmatter ベースの markdown を 1 ファイル書く。YAML が正本、
本文は補助。

```markdown
---
epic: auth-suite
generated_at: 2026-04-15T12:00:00Z
planner_model: claude-opus-4-6
sprints:
  - n: 1
    feature: login
    bundling: split
    bundling_reason: "独立 UI、書き込み共有スキーマなし"
    dependencies: []
    risk: medium
    generator_backend: claude
    generator_backend_reason: "UI / UX 重視 sprint（rubric 推奨を user 確認後採用）"
  - n: 2
    feature: signup
    bundling: bundled
    bundling_reason: "UserRecord スキーマと password hashing を login と共有"
    bundled_with: [3]
    dependencies: [1]
    risk: medium
    generator_backend: codex_cli
    generator_backend_reason: "schema + auth heavy。primary peer の選択で peer 全体を統一"
  - n: 3
    feature: password-reminder
    bundling: bundled
    bundling_reason: "email テンプレ契約を signup と共有"
    bundled_with: [2]
    dependencies: [2]
    risk: low
    generator_backend: codex_cli
    generator_backend_reason: "bundle peer（sprint 2 と同 backend を継承）"
---

# Roadmap: auth-suite

## Sprint Summary

| # | Feature | Bundling | 依存 | Risk |
|---|---|---|---|---|
| 1 | login | split | — | medium |
| 2 | signup | bundled (with 3) | 1 | medium |
| 3 | password-reminder | bundled (with 2) | 2 | low |

## Bundle Groups

- **Bundle A**: sprint 2 + 3 → sprint 3 完了時に単一 PR
- Sprint 1 → 独立 PR

## Rationale

<自明でない決定について 1 段落ずつ。`bundled` には必ず結合軸を引用。
利用者期待と逆の bundling 判断を下した場合はここに記録 — roadmap 承認
AskUserQuestion で明示できるように。>
```

### sprint エントリ必須フィールド

| フィールド | 型 | 必須 | 備考 |
|---|---|---|---|
| `n` | int | ○ | 1 始まりの sprint 番号 |
| `feature` | string（kebab-case） | ○ | ディレクトリ名 `sprint-<n>-<feature>/` に使用 |
| `bundling` | `split` \| `bundled` | ○ | デフォルト `split` |
| `bundling_reason` | string | bundled 時必須 | 結合軸を引用 |
| `bundled_with` | int[] | bundled 時必須 | 同 bundle の peer sprint。相互参照必須 |
| `dependencies` | int[] | ○（`[]` 可） | 先行完了が必要な sprint |
| `risk` | `low` \| `medium` \| `high` | ○ | Evaluator 閾値の厳しさに反映 |
| `generator_backend` | `claude` \| `codex_cli` \| `codex_cmux` \| `null` | optional | interactive mode では AskUserQuestion で確定、non-interactive では auto-confirm。`null` の場合は実行時に `_config.yml.generator_backend` へ fallback。`## Backend 推奨判定` を参照 |
| `generator_backend_reason` | string | `generator_backend` が non-null 時必須 | この backend を選んだ根拠を記録（rubric primary 採用 / epic default 採用 / 手動 override）。free-form。audit と `harness-rules-update` の入力になる |

**相互参照チェック**: sprint 2 に `bundled_with: [3]` があれば、sprint 3 にも
`bundled_with: [2]` が必須。Planner は書き出し前に検証する。

## Sprint 順序付け

bundling 後、Planner は以下順序で:

1. **トポロジカル**: `dependencies` を尊重。依存元が `status: done` の sprint
   のみ起動。
2. **peer 間は risk 優先**: 依存関係が同等の 2 sprint は `high` risk を先に。
   根拠 — 不確実性が安い段階で早く失敗させる。
3. **bundle 近接**: 同 bundle peer は連続実行。group 内最終 peer の末尾で
   1 コミット範囲として PR 化。

## 承認ゲート

`harness-plan` は Sprint Summary 表と bundle groups を `AskUserQuestion` で
提示する。このゲートは **常時 interactive 固定**。
`harness-loop` の `mode`（continuous / autonomous-ralph / scheduled）は
後続で決まるため、mode を根拠に承認スキップしてはならない。

選択肢:

- **そのまま承認**: contract 生成と Issue 起票に進む
- **変更を要求**: 利用者が変更を入力 → Planner が再生成 → ループ
- **キャンセル**: 部分状態を progress.md に書き、終了

唯一の回避手段は `/harness-plan` に対する明示的な `--auto-approve-roadmap`
フラグのみ。指定時は AskUserQuestion をスキップし監査行を `progress.md` に
追記する。利用者は事前に生成済み `roadmap.md` をレビューしたうえで
フラグを付ける責任を負う。事後修正が必要な場合は手動で `roadmap.md` を編集し、
対象 sprint が `harness-loop` の negotiation に入る前に
`/harness-plan --replan` を再実行する。

## contract 生成への受け渡し

承認後、`harness-plan` は sprint リストを順に回して各エントリについて:

1. `.harness/templates/sprint-contract.md` を
   `.harness/<epic>/sprints/sprint-<n>-<feature>/contract.md` にコピー
2. YAML frontmatter（`sprint`, `feature`, `bundling`, `max_iterations`,
   `max_negotiation_rounds`）を `_config.yml` と roadmap エントリから事前記入
3. **`generator_backend` と `generator_backend_reason`** を roadmap sprint
   entry から contract frontmatter にそのまま copy。roadmap 値が `null`
   （legacy bypass や未設定）なら contract も `null` のままにし、
   `harness-loop` 実行時に `_config.yml.generator_backend` へ fallback
4. `acceptance_scenarios` と `rubric` は空スタブのまま — これらは
   `harness-loop` の sprint negotiation で埋まる
5. `status: negotiating` を設定

contract の rubric はここでは事前記入 **しない**。閾値調整は sprint の risk と
`_config.yml.rubric_preset` の rubric プリセットに依存するため。
[rubric-presets.md](../../harness-init/references/rubric-presets.ja.md) 参照。

## リカバリ

product-spec 完了後、roadmap 承認前に `harness-plan` が中断された場合:

- `.harness/<epic>/roadmap.md` は draft として存在（または不在）
- `_state.json.phase = "roadmap-draft"` または `"product-spec-draft"`
- resume 時、Planner は product-spec.md を再読し、draft roadmap があれば差分を取り、
  利用者に継続か再生成かを問う
