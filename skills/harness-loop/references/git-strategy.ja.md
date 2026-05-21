# Harness Git Strategy（日本語版）

このドキュメントは、harness 制御ループの中で **git mutation コマンドを
実行してよいのは誰か**、および **どのファイルが tracked / gitignored
のどちらに属するか** を規定する。各 iteration の前に必ず読むこと。
そうしないと、agent が勝手に commit してしまったり、`git status` を
誤った前提で解釈してしまう。

## 読者

このファイルは harness の全 role が読む。第一の読者は **agent**
（Generator / Evaluator / Planner）であり、下記のルールは「触っては
いけないもの」を agent ごとに明示する。Orchestrator (harness-loop) と
init 時 setup もこのファイルを参照する。

| Role | 読むタイミング | このファイルが伝えること |
|---|---|---|
| Generator (claude / codex_cli / codex_cmux) | 毎 iteration（Boot Sequence） | disk に書くだけ。`git add` / `commit` / `push` を絶対に実行しない |
| Evaluator | 毎 iteration（Boot Sequence） | disk に書くだけ。`git add` / `commit` / `push` を絶対に実行しない |
| Planner | 毎 invocation（interview / roadmap / contract-draft / ruling / mid-impl-replan） | disk に書くだけ。`git add` / `commit` / `push` を絶対に実行しない |
| Orchestrator (harness-loop / harness-plan) | harness-loop Step 7（atomic per-iter checkpoint）/ harness-plan Step 4 + Step 6（product-spec + roadmap commit） | commit 責務を単独で持つ。harness flow 内のすべての git mutation を担当 |
| user / `harness-init` | プロジェクト初期セットアップ時 | 下記 entries を `.gitignore` に追加する |

## Commit 所有ルール（必須）

harness flow 内で git mutation コマンド（`git add`, `git commit`,
`git push`, `git rebase`, `git reset --hard`, ブランチ作成・削除 等）を
実行できるのは、**Orchestrator skill (`harness-plan` と `harness-loop`)
のみ** である。

Generator / Evaluator / Planner は git mutation コマンドを一切実行しては
ならない。具体的には:

- **Generator** はソースコード / テストコード / ドキュメントと、
  必須の `feedback/generator-<iter>.md` + `feedback/generator-<iter>-report.json`
  ペアを disk に書いて exit する。すべての変更は `harness-loop` の
  Step 7 が `git add -A && git commit -m "harness-loop: sprint-<n> iter-<iter>"`
  で一括 capture する。
- **Evaluator** は `${SPRINT_DIR}/evidence/iter-<n>/` の artefact（Playwright
  trace / screenshot / curl log / Python timing JSON / Playwright log）と
  `feedback/evaluator-<iter>.md`（または `evaluator-neg-<round>.md`）を
  disk に書いて exit する。commit は `harness-loop` Step 7 が行う。
- **Planner** は以下を disk に書いて exit する:
  - `harness-plan` 中: `product-spec.md`（interview）/
    `roadmap.md`（roadmap）/ sprint `contract.md` 雛形（contract-draft）
  - `harness-loop` 中: `feedback/planner-ruling.md`（交渉 stalemate
    裁定）または `feedback/planner-ruling-impl-<iter>.md`（mid-impl
    replan）と、ruling phase で必要な `contract.md` 上書き

  commit は dispatch した skill が実行する — `harness-plan` Step 4 が
  `product-spec.md` を、`harness-plan` Step 6 が `roadmap.md` を、
  `harness-loop` Step 7 が他すべて（contract-draft は sprint 初回
  commit に同梱、ruling は影響する iteration commit に同梱）を
  commit する。

なぜ skill ごとに commit を 1 役割に集約するのか: 各 Orchestrator
skill は書き込みを atomic checkpoint にまとめる。`harness-loop`
Step 7 は `_state.json` / `metrics.jsonl` / `progress.md` / git commit
を iter 毎に 1 パスで co-write する。`harness-plan` Step 4 / Step 6 は
担当 Planner sub-agent が exit した後に planning 成果物を commit する。
agent が独立に commit すると (a) 1 つの論理 iteration が複数 commit に
分裂し `shared_state.md` / `metrics.jsonl` が古い状態のまま残る、
(b) resume 時に `progress.md` と `git log` の順序が逆転する、
(c) Orchestrator の commit を包む Tier-A guard hook を bypass する、
という 3 つの問題が起きる。harness モデルは「skill ごとに commit する
役割は 1 つだけ」を前提に組まれている。

実行しようとしているコマンドが `git add ...`, `git commit ...`,
`git push ...`, `git checkout -b ...`, `git rebase ...`,
`git reset --hard ...`, `git stash ...` のように見えたら止める。
Orchestrator が処理する。非自明な git 操作（ブランチ rename 等）が
必要なら、`feedback/<role>-<iter>.md` の narrative で surface して
Orchestrator に判断を委ねる。

## 設計原則（ファイル分類）

`.harness/` 配下のファイルには 2 種類ある:

1. **不変な audit trail** — sprint 意思決定 / 契約 / 成果物。
   **git に track** して、PR レビュアーが `git log` +
   `shared_state.md` だけで sprint の流れを追えるようにする。
2. **per-iter / per-session 生成物** — agent の個別思考、Evaluator が
   毎 iter 再生成する evidence、wrapper の一時状態。**gitignore** して
   PR diff を実コード中心に保ち、main の history も skill 内部状態の
   churn で埋もれさせない。

両者の境界を明確にすることで、PR レビューが feature 差分中心になり、
main の commit log が "sprint-1 iter-3 SHA stamp" のような skill
内部状態の更新で埋もれない。

## Track 対象（git に残す）

| path | 役割 |
|---|---|
| `.harness/_config.yml` | skill 設定（backend / hook_level / mid_impl_replan / ...） |
| `.harness/_state.json` | machine cursor、resume 必須 |
| `.harness/progress.md` | human-readable 作業ログ（append-only） |
| `.harness/metrics.jsonl` | per-iter metrics、Principal Skinner 監視ソース |
| `.harness/tier-a-patterns.txt` | Tier-A guard regex 一覧（hook config） |
| `.harness/scripts/*` | hook scripts（progress-append / tier-a-guard / stop-guard / ralph-loop / ...） |
| `.harness/templates/*` | skill template（review 対象） |
| `.harness/<epic>/product-spec.md` | epic 計画成果物 |
| `.harness/<epic>/roadmap.md` | sprint 分解 |
| `.harness/<epic>/sprints/sprint-*/contract.md` | **契約本体** — accept criteria / rubric / negotiation log / Sprint Outcome |
| `.harness/<epic>/sprints/sprint-*/shared_state.md` | **sprint 台帳** — Plan / Negotiation / WorkLog / Evaluation / Decisions の要約 |
| `.harness/sprint-durations.md`（オプション） | duration ledger を維持するチームのみ |

## Gitignore 対象（track しない）

| path | 役割 / 除外理由 |
|---|---|
| `.harness/*.backup-*` | 旧 state スナップショットの一時ファイル |
| `.harness/.mcp-wildcard-warned` | 1 回限りの warning marker |
| `.harness/<epic>/sprints/sprint-*/feedback/` | per-iter agent 思考（`generator-*.md` / `evaluator-*.md` / `planner-ruling-*.md` / `*-neg-*.md`） |
| `.harness/<epic>/sprints/sprint-*/feedback/codex-exec-*.jsonl` | codex_cli 内部 raw 出力 |
| `.harness/<epic>/sprints/sprint-*/feedback/codex-exec-*.stderr` | 同上 |
| `.harness/<epic>/sprints/sprint-*/feedback/codex-last-*.txt` | 同上 |
| `.harness/<epic>/sprints/sprint-*/feedback/*-report.json` | Generator dispatch 報告（touchedFiles 等）/ Evaluator compliance report |
| `.harness/<epic>/sprints/sprint-*/evidence/**` | Playwright trace / screenshot / curl log / Python timing JSON |
| `.harness/ralph.log` | wrapper stdout（transient） |
| `.harness/ralph.pid` | wrapper pid（consume-and-delete） |
| `.harness/NEXT_SESSION_PROMPT.md` | session handoff（consume-and-delete） |

### feedback / evidence を gitignore してよい根拠

- **`feedback/*.md`** は agent の個別思考の記録。Orchestrator が毎 iter
  終了時に `shared_state.md` の WorkLog / Evaluation / Negotiation /
  Decisions sections に **要約をコピー** するので、cross-session でも
  `shared_state.md` だけで sprint の流れを再構成できる
  （`shared-state-protocol.md` 参照）。Planner の mid-impl replan
  dispatch は **現 session で生成された disk 上の feedback file** を
  読むため、cross-session で保存しておく必要は無い。
- **`${SPRINT_DIR}/evidence/iter-<n>/`** は Evaluator が各 iter で live verification を
  再走させて再生成する性質のもの。歴史的 evidence は source of truth
  ではなく、最新 iter の evidence が常に最新の verification 結果。
- **`codex-exec*` / `codex-last*`** は codex_cli の内部 raw 出力で
  機密性（内部 prompt / reasoning）と巨大なサイズの両面で git に乗せる
  価値が薄い。

## 既存 project の migration

既存 project で `feedback/` や `evidence/` が既に tracked になっている
場合、以下を実行して untrack する（working tree のファイルは残す）:

```bash
git rm --cached -r \
  .harness/*/sprints/*/feedback/ \
  .harness/*/sprints/*/evidence/

# 単体ファイル
git rm --cached .harness/ralph.log 2>/dev/null || true
git rm --cached .harness/ralph.pid 2>/dev/null || true
git rm --cached .harness/NEXT_SESSION_PROMPT.md 2>/dev/null || true

git add .gitignore
git commit -m "chore(harness): untrack feedback/evidence/runtime artifacts per harness git-strategy"
```

進行中の sprint branch がある場合、各 branch で同じ操作を行うか、
main 側で行ってから rebase / merge で取り込む。force-push で履歴
書き換えはしない（Tier-A guard が block する想定）。

この migration は、harness state に関連する git mutation を **Orchestrator
ではなく人間が** 実行する唯一のケース。1 回限りの cleanup であり
per-iter loop の一部ではないため、「agent は commit しない」というルールは
そのまま維持される。

## upstream (agent-skills) への反映

本ドキュメントを upstream に反映するときは:

1. harness-init skill の Step 10 は `.gitignore` entries の追記指示と、
   本ドキュメントへの link だけを残す。
2. `.claude` / `.codex` の mirror は md5 一致を維持する（md5-sync policy
   は `.claude/skills/harness-loop/references/git-strategy.md` ↔
   `.codex/skills/harness-loop/references/git-strategy.md` および
   `.ja.md` ペアの両方に適用される）。
3. 将来的には harness-init を新規 project で実行した時、`.gitignore` に
   上記 entries を **自動追記** するロジックを skill に組み込む（現状は
   user に手動編集を促す形）。新 project はデフォルトで clean PR に
   なる。
