# Foundation-Sprint ガイド

Greenfield（ほぼ空）のプロジェクトでは harness-loop が前提としている runtime が未構築。`pnpm dev` が起動しない、test runner の config が無い、外部プロバイダに OAuth client が無い、migrate する DB が無い。そのまま `/harness-loop` を回しても Evaluator は何も採点できず、acceptance scenario は rubric 失敗ではなく "command not found" レベルで落ちる。

`harness-plan` はこれを **foundation-sprint** で吸収する。`n=0` に差し込まれる特別なスプリント種別で、**rubric 採点しない** 代わりに human attestation で完了を認定する。

本ガイドで定義するもの:

1. foundation-sprint が挿入される条件
2. `type: foundation` の contract スキーマと deliverables（rubric 代替）
3. `generator_mode` — foundation-sprint に Generator がどこまで関与するか
4. `harness-loop` が foundation-sprint を feature sprint とどう違えて扱うか
5. 既存ルール（bundling / dependencies / sprint cap）との相互作用

## foundation-sprint はいつ挿入されるか

`harness-plan` Step 3.5（Foundation Readiness Check）が severity `YELLOW` or `RED` を返し、**かつ** ユーザが中断せず続行を選んだ時に挿入される。[../SKILL.ja.md §Step 3.5](../SKILL.md) と [../../harness-init/references/scripts.ja.md §foundation-readiness.sh](../../harness-init/references/scripts.ja.md) 参照。

Planner は `_state.json.foundation_sprint_needed == true` でこれを検知する（Step 3.5 が roadmap Planner 起動前に set する）。

1 epic につき foundation-sprint は最大 1 本、常に `n=0`。Step 3.5 が `GREEN` を返せば挿入されず、全スプリントが従来どおり `n=1` から始まる。

## Foundation readiness check（Step 3.5）

`harness-plan` の Step 3.5 は、Planner sub-agent を起動する前に次を実行する:

```bash
.harness/scripts/foundation-readiness.sh --epic <epic>
```

この script は `.harness/<epic>/foundation-readiness.md` を書き、
stdout に JSON summary を出す:

```json
{"severity":"GREEN|YELLOW|RED","verified_at":"<ISO-8601>","ok":[...],"missing":[...],"unknown":[...]}
```

severity 判定は次の通り:

- `GREEN`: 全 probe が ok
- `YELLOW`: missing が 1-2 件で、かつ `package_manifest` は ok
- `RED`: `package_manifest` が missing、または missing が 3 件以上

severity が `RED` の場合、`harness-plan` は次を質問する:

```text
Near-greenfield detected. Harness cannot score sprints without a working dev loop. How do you want to proceed?
```

選択肢:

- `Abort and set up foundation manually (Recommended)`
  `foundation-readiness.md` の missing-probes checklist と、
  product-spec の Constraints から導いた project-appropriate な
  bootstrap outline（例: `pnpm create next-app`, `prisma init`,
  GCP OAuth client setup, `.env.example` など）を表示して clean に終了する。
- `Insert Sprint 0 (foundation-sprint) and continue`
  `foundation_sprint_needed=true` を立てて roadmap 生成へ進む。
  Planner が Step 5 で sprint-0 を挿入する。
- `Cancel`
  `_state.json.current_epic` 以外の state は増やさず終了する。

`--auto-approve-roadmap` が指定されている場合、`RED` は対話せず
`Insert Sprint 0 (foundation-sprint) and continue` を自動選択する。
この flag は interactive approval を避けつつ continue path を選ぶ契約。

check 完了直後に `_state.json.foundation_readiness` へ JSON summary を書く。
`_state.json.foundation_sprint_needed=true` は、severity が `YELLOW` の時、
または severity が `RED` で `Insert Sprint 0 (foundation-sprint) and continue`
を選んだ時に書く。Step 5 の Planner はこの 2 キーを読んで sprint-0 の
挿入要否を判断する。

## スキーマ — `type: foundation` の sprint entry

`roadmap.md.sprints[]` 内:

```yaml
- n: 0
  feature: dev-environment-foundation   # プロジェクト適合の slug
  type: foundation                      # split|bundled に加えて第3の値
  deliverables:                         # rubric の代替
    - package_manifest                  # package.json をコミット済み
    - runtime_boots                     # `pnpm dev` が / で 200 を返す
    - test_runner_configured            # playwright.config.ts / pytest.ini が存在
    - env_example_committed             # .env.example が必要なキーを網羅
    - external_setup_doc                # SETUP.md に GCP/Slack 手順
    - dev_db_available                  # docker-compose up or SQLite ファイル
  human_attestation_required: true      # foundation では常に true
  generator_mode: scaffold              # none | scaffold | optional
  dependencies: []                      # 常に空（foundation が最先頭）
  risk: medium                          # 人間の追跡用、採点はしない
```

フィールド:

| フィールド | 型 | 必須 | 備考 |
|---|---|---|---|
| `type` | literal `"foundation"` | yes | 以下の特別処理すべてを有効化 |
| `deliverables` | string[] | yes | 既知キー（下表）のサブセット |
| `human_attestation_required` | bool | yes | foundation は常に true |
| `generator_mode` | `none` \| `scaffold` \| `optional` | yes | 次節参照 |

`type: foundation` エントリは `rubric` / `acceptance_scenarios` / `bundling` / `bundled_with` を持ってはならない。Planner が生成する `contract.md` もこれらを完全に省略する。

### 既知の deliverable キー

`foundation-readiness.sh` の probe と 1:1 対応。Step 3.5 は missing probe からこのリストを自動生成する:

| キー | Probe | "Done" の意味 |
|---|---|---|
| `package_manifest` | manifest ファイル存在 | 言語対応 manifest がコミット済み |
| `runtime_boots` | runtime command が exit 0 | 例: `pnpm dev` が index を 2xx で返す |
| `test_runner_configured` | config ファイル存在 | `_config.yml.evaluator_tools` に対応する smoke が走る |
| `env_example_committed` | `.env.example` 等が存在 | Constraints が要求する全シークレットに placeholder |
| `external_setup_doc` | `SETUP.md` / `docs/setup.md` が存在 | 外部プロバイダ手順（GCP console / Slack app）が文書化 |
| `dev_db_available` | docker-compose / ローカル DB ファイルが存在 | 後続 sprint の DB 依存 AS が回る |
| `tracker_wired` | `gh auth status` + origin | `tracker=github` のときのみ意味を持つ |

既知キー以外の独自 deliverable も追加可（自動 probe 無しの human-attested チェック項目として扱う）。

## `generator_mode` — Generator の関与度

Generator はコードを書く。foundation-sprint はコードと外部設定（人間のみ可）が混在する。`generator_mode` で Generator が試す範囲を制御:

| Mode | Generator が書く | 人間が担当 |
|---|---|---|
| `none` | 何も書かない | 全部（manifest / scaffolding / 外部設定 / env / doc） |
| `scaffold` | manifest + 最小 scaffolding（`pnpm create next-app` 相当、`.env.example`、`SETUP.md` 骨子） | 外部プロバイダ設定（GCP / Slack）、実シークレットを `.env.local` に入れる、`runtime_boots` 検証 |
| `optional` | `scaffold` の内容 + docker-compose.yml + ORM init（`prisma init` 等） + test runner config 骨子 | 外部設定 / シークレット / 初回 migration（対話必要なら） |

デフォルト: `scaffold`（最も安全な中間。Generator が自動化できる範囲を bootstrap、外部システム access が必要な部分は人間）。

Planner は deliverables が純コード / 純人間のどちら寄りかで `generator_mode` を選ぶ。全 deliverable が外部設定のみ（例: "GCP OAuth client"）なら `none` に降格。

## `harness-loop` の foundation-sprint 時挙動

`harness-loop` は Boot Sequence で `contract.type == "foundation"` を検知し分岐:

1. **Negotiation phase をスキップ** — 交渉する閾値が無い。contract-draft から implementation へ直行
2. **Generator は最大 1 回のみ** — `_config.yml.max_iterations` に関わらず。G⇄E iteration 無し
3. **Evaluator は deliverables verifier に差し替え**:
   - 各 deliverable に対し `foundation-readiness.sh --check <key>` probe を実行
   - deliverable ごとの結果を `feedback/verification-<iter>.md` に記録（iter は 1 回のみ）
   - rubric scoring 無し、`metrics.jsonl` への rubric 軸エントリ無し
4. **Human attestation gate** — 検証後、`_state.json.phase = "foundation-attest"` + `pending_human = true` を set。検証レポートを `AskUserQuestion` でユーザに提示:
   - `"Foundation deliverables verified (N/M probes pass). Attest complete?"` options: `Attest / Fix & retry / Abort`
5. **Attest 時** — `foundation-readiness.sh --epic <epic>` を再実行し、fresh な summary を `_state.json.foundation_readiness` に書き戻し、`_state.json.foundation_sprint_needed=false` をセットしてから `_state.json.current_sprint` を 1 に進め、次の通常 sprint の negotiation へ移る
6. **PR 作成** — foundation-sprint 単独 PR、タイトル先頭は `[sprint-0] foundation:`。body は rubric スコアでなく deliverables と検証結果を列挙

### `_state.json` に追加される phase

foundation-sprint 用に 2 つの新 phase を追加:

- `foundation-setup` — Generator 作業中 / 人間が外部設定中
- `foundation-attest` — 検証完了、human attestation 待ち

両方とも stop-guard の non-loop phase allowlist に入る（[../../harness-init/references/scripts.ja.md §stop-guard 判定マトリクス](../../harness-init/references/scripts.ja.md) 参照）。

## 既存ルールとの相互作用

### Sprint cap

`roadmap-guide` は epic を ≤6 sprints に制限するが、foundation-sprint は cap の対象外（インフラであり feature delivery ではない）。6 上限は feature sprints `n≥1` にのみ適用。

### Dependencies

foundation-sprint は常に `n=0` かつ `dependencies: []`。他に明示的 dependency が無い全 feature sprint は、Planner が foundation-sprint を挿入した後に暗黙的に `dependencies: [0]` を追加する（Planner が自動書き換え）。

### Bundling

foundation-sprint は他 sprint と bundle できない。常に独立 PR。Planner が foundation 作業を feature sprint と bundle したくなった場合は、それは foundation-sprint のスコープが間違っている signal — feature sprint 1 が bootable baseline から始まるよう再 scope する。

### Replan

foundation-sprint が既に merge 済みの epic に対して `/harness-plan --replan` を走らせても foundation-sprint は再挿入されない。Step 3.5 が readiness probe を再実行し、foundation-sprint の merge 済み PR により `runtime_boots` が pass するので `GREEN` 判定になる。probe が退行した時（依存破壊など）は Planner が **remediation sprint** を現在の `n` に挿入（`n=0` ではなく）。`foundation-remediation` と名付け、accounting は feature sprint 扱いだが `type: foundation` を付けて rubric scoring はスキップ。

## Contract テンプレート

[../../harness-init/references/templates/foundation-sprint-checklist.md](../../harness-init/references/templates/foundation-sprint-checklist.md) に `type: foundation` 用の `contract.md` 全体形を記載。

## Planner 側 authoring チェックリスト

foundation-sprint contract を書く時、Planner は:

1. `foundation-readiness.md` を読み、missing probe を `deliverables` にそのままコピー
2. deliverables の内訳で `generator_mode` を決定（上表参照）
3. contract body に "Setup prerequisites" 節を書き、script で自動化できない手動外部手順（GCP console / ドメイン verification / Slack app 作成 等）を列挙
4. `human_attestation_required: true` を常時 set
5. `acceptance_scenarios` / `rubric` / `bundling` / `bundled_with` を **書かない**
6. `max_iterations` / `threshold` プレースホルダを **書かない**（iteration loop 無し）

## Issue 側 authoring チェックリスト

foundation-sprint の tracker Issue body は feature sprint と異なる形式。[issue-create.ja.md §Sprint-0 body テンプレ](issue-create.ja.md) に正本を記載（deliverables チェックリスト / 外部設定節 / human attestation 節）。

## まとめ

foundation-sprint は:

- オプショナル、greenfield 検出時のみ挿入
- `type: foundation` で識別
- `rubric` / `acceptance_scenarios` の代わりに `deliverables`
- 1 回のみ走り、G⇄E loop 無し
- 完了は human attestation 必須
- 完了後 harness-loop が検証済 baseline から feature sprint に進む
