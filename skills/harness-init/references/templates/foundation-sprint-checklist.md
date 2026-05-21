<!--
  foundation-sprint-checklist.md — type: foundation sprint contract template

  harness-plan が Step 3.5 で foundation_sprint_needed=true を検知した時のみ
  この形で contract.md を生成する。通常 sprint は sprint-contract.md を使う。

  違いの要点:
    - rubric / acceptance_scenarios の代わりに deliverables + setup_prerequisites
    - threshold / max_iterations / max_negotiation_rounds は **書かない**
    - bundling / bundled_with は **書かない**（foundation は常に独立 PR）
    - status は pending-attestation（通常 sprint は pending-negotiation）
-->

---
sprint: 0
feature: <dev-environment-foundation 等のプロジェクト適合 slug>
type: foundation
goal: |
  <harness-loop が回る前提となる dev 基盤を整える。
   人間が GCP / Slack 等の外部設定を行い、Generator が自動化可能な
   scaffolding を書き、deliverables 全件が verifier probe で ok を返す状態に到達する>
deliverables:
  - <foundation-readiness.md の missing probe をそのまま列挙>
generator_mode: scaffold   # none | scaffold | optional
human_attestation_required: true
dependencies: []
risk: medium
status: pending-attestation
---

# Sprint 0 Contract — <feature>

## Goal

<1〜2 段落。harness-loop が sprint 1 以降を回すため何を確立するか。
rubric 採点対象ではないことを明記し、完了判定は deliverables 全 ok + human attestation と書く>

## Deliverables

foundation-readiness probe の missing 項目と 1:1 対応。各項目は harness-loop
の verifier が `foundation-readiness.sh --check <key>` で ok を返せば完了。

| Key | Done の意味 | 担当 |
|---|---|---|
| package_manifest | package.json / pyproject.toml / go.mod 等がコミット済み | Generator (scaffold mode) |
| runtime_boots | `pnpm dev` / `uvicorn app:app` 等が 2xx を返す | Generator + 人間（env 記入） |
| test_runner_configured | `_config.yml.evaluator_tools` に対応する config が存在 | Generator |
| env_example_committed | Constraints が要求する全シークレットに placeholder | Generator |
| external_setup_doc | `SETUP.md` / `docs/setup.md` に GCP / Slack 等の手順 | Generator (skeleton) + 人間 (refinement) |
| dev_db_available | docker-compose.yml / local DB ファイル | Generator (scaffold) |
| tracker_wired | `gh auth status` 成功 | 人間 |

<プロジェクト特有の deliverable がある場合はここに追記>

## Setup Prerequisites（人間のみ可）

script で自動化できない外部プロバイダ設定。Generator は行わない。人間が
事前または並行して完了させ、`.env.local` に反映する:

- [ ] <例: GCP console でプロジェクト作成、OAuth consent screen を Internal で構成、OAuth client (Web app) を作成、redirect URI を http://localhost:3000/api/auth/callback/google に設定>
- [ ] <例: Slack API で App 作成、Events API URL を登録、Signing Secret をコピー>
- [ ] <例: Anthropic console で API Key を作成>
- [ ] `.env.local` に実シークレットを記入（`.env.example` を参照）

## Generator 作業範囲（generator_mode による）

### `generator_mode: scaffold`（デフォルト）

- 言語対応 manifest (package.json 等) の生成
- フレームワーク雛形（`pnpm create next-app` 相当、`uvicorn` 雛形 等）
- `.env.example` の生成（全必須キーを placeholder で列挙）
- `SETUP.md` の骨子（セクションヘッダと TODO コメント）
- （`optional` ならさらに）docker-compose.yml、ORM init、test runner config 骨子

### `generator_mode: none`

Generator は起動しない。人間がすべてを書く。harness-plan は contract と
Issue checklist を用意して終わり、人間が別 PR でセットアップして merge
→ `/harness-loop` が sprint 1 から開始。

### `generator_mode: optional`

`scaffold` + DB / test runner の初期化まで Generator が踏み込む。外部設定と
secrets 注入のみ人間。

## Verification Protocol（harness-loop 側）

`harness-loop` は foundation-sprint に入ると:

1. Generator を最大 1 回起動（`generator_mode: none` なら起動しない）
2. Evaluator の代わりに `foundation-readiness.sh --check <key>` を各
   deliverable に対して実行し、`feedback/verification-1.md` に結果を記録
3. 全 deliverable が ok なら `_state.json.phase = "foundation-attest"` に
   遷移し、人間に AskUserQuestion で attestation を求める
4. 人間が Attest を選択したら PR を作成、`current_sprint` を 1 に進める
5. Fix & retry なら Generator を再起動、または人間が直接修正するまで待機

rubric / threshold / max_iterations は無視される（宣言されていない）。

## Sprint Outcome

<Orchestrator が attestation 完了時に記入>

- **Deliverables verified**: <N/M, date>
- **Human attestation by**: <user / ts>
- **Final commit**: <sha>
- **PR**: <url>
- **Abort reason**（あれば）:
