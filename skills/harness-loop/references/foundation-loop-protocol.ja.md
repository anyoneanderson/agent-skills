# Foundation-Sprint ループ実行プロトコル

`harness-loop` が現 sprint の `contract.type == "foundation"` を検出した時に
辿る runtime プロトコル。foundation-sprint を**いつ / なぜ差し込むか**、
スキーマ、`generator_mode` の意味といった plan-side 論拠は
[../../harness-plan/references/foundation-sprint-guide.ja.md](../../harness-plan/references/foundation-sprint-guide.ja.md)
が持つ。本ファイルは「実行中の loop がどう動くか」のみ扱う。

## いつ発火するか

SKILL.md Step 3 が `contract.md` を読み込み、frontmatter に
`type: foundation` があれば Steps 4–7（negotiation + G⇄E rubric iteration）を
skip して本プロトコルに従う。完了後は Step 8 (PR) / Step 9 (sprint transition)
に合流する。

## フェーズ遷移

```
ready-for-loop
  └─ Step 3 (branch setup + contract load)
       └─ foundation-setup
            └─ [generator dispatch (≤1 回) + readiness probe ループ]
                 └─ foundation-attest          ← pending_human=true
                      ├─ Attest  → pr → Step 8
                      ├─ Fix     → foundation-setup (retry、上限 3)
                      └─ Abort   → aborted_reason 設定、halt
```

`foundation-setup` と `foundation-attest` はいずれも stop-guard の
phase allowlist 上にあり、probe 実行や人間 attestation 待ちで loop が
停止しても Principal Skinner に誤発火しない。

## プロトコル（ステップ）

```
1. _state.json.phase = "foundation-setup" をセット。

2. Interactive kickoff gate（mode == "interactive" の時のみ）:
     Foundation scaffolding は副作用が大きい — package install、
     docker pull、外部認証ファイル生成等。dispatch 前に必ず確認:
       AskUserQuestion:
         "Foundation sprint kickoff. Generator will scaffold per
          contract (mode: <contract.generator_mode>). Proceed?"
         options: Proceed / Revise contract / Abort
     非対話モード（continuous / autonomous-ralph / scheduled）は
     このゲートを飛ばす。Revise contract → halt して contract パスを
     surface、/harness-plan --replan に戻る。Abort →
     aborted_reason = "foundation-kickoff-aborted"。

3. contract.generator_mode != "none" なら:
     Step 3.5 の手順で prompt-templates/generator-foundation.md を
     レンダリング（placeholder は {{EPIC_NAME}} / {{SPRINT_NUMBER}} /
     {{SPRINT_FEATURE}} / {{ITERATION}} のみ）。
     Generator を 1 回だけ dispatch。（Non-design rule 適用 — SKILL.md
     §Orchestrator responsibility 参照。）

4. contract.deliverables の各キーに対し:
     `.harness/scripts/foundation-readiness.sh --check <key>` を実行し、
     pass/fail + evidence を deliverable_checks スキーマに従って
     feedback/verification-1.md に記録（
     [shared-state-protocol.ja.md §deliverable_checks スキーマ](shared-state-protocol.ja.md)
     参照）。

5. progress 行を追記:
     `[<ts>] foundation: pass=<N>/<M> deliverables=<list>`

6. _state.json.phase = "foundation-attest"、
   _state.json.pending_human = true をセット。
     AskUserQuestion:
       "Foundation deliverables verified (<N>/<M>). Attest complete?"
       options: Attest / Fix & retry / Abort

7. Attest 選択時:
     `.harness/scripts/foundation-readiness.sh --epic <epic>` を再実行し、
     その JSON summary を `_state.json.foundation_readiness` に書き戻す
     （checker が返した `verified_at` を保持）。
     `_state.json.foundation_sprint_needed = false` をセット。
     その後 `phase = "pr"`、`pending_human = false`。
     最後の durable write として
     `_state.json.pending_worker_exit = true` を立て、autonomous-ralph
     の stop-guard が Step 8 突入前に worker turn の natural exit を
     許可できるようにする。
     foundation 専用の PR body で Step 8 へ進む（下記参照）。

8. Fix & retry 選択時:
     pending_human をクリア、step 3 に戻り Generator を再 dispatch。
     上限: 3 回。4 回目は自動 abort で
     aborted_reason = "foundation-retry-exhausted"。
     autonomous-ralph wrapper 経由の retry の場合は pending_human
     クリア後に `_state.json.pending_worker_exit = true` を立てて
     現 worker turn を終わらせ、wrapper が次 tick で fresh worker を
     起動できるようにする。

9. Abort 選択時:
     aborted_reason = "foundation-attestation-rejected"、halt。
     aborted_reason 書き込みのあと `_state.json.pending_worker_exit = true`
     を立てて current worker を exit させる。wrapper の次 tick は
     abort cursor を観測して新 worker を起動せずに停止する。
```

## Abort 理由

| Reason | 発火箇所 | operator 対応 |
|---|---|---|
| `foundation-kickoff-aborted` | Step 2 で Abort 選択 | `/harness-loop` を再実行し Proceed 選択 |
| `foundation-attestation-rejected` | Step 9 で Abort 選択 | 根本ギャップを解消してから `/harness-loop` で step 1 から再生 |
| `foundation-retry-exhausted` | Step 8 の 4 回目 | `/harness-plan --replan` か deliverables 緩和 |

## PR body（foundation 固有）

Step 8 で pr-creation-guide を呼び出すが、body テンプレは feature sprint と
以下の点で異なる:

- **rubric summary 無し** — 軸も threshold もないので引用しない
- **Deliverable 表** — Orchestrator が `feedback/verification-1.md` に
  組み立てた表（Generator 申告 / probe 判定 / evidence / 一致）をそのまま転記
- **Setup 残タスク list** — `contract.md` §Setup Prerequisites を
  `[ ]` 付きで転載（GCP console / Anthropic key 取得等、リポ外の人間作業）
- **Sprint link** — `_state.json.sprint_issues[0]`

完全な foundation PR テンプレは
[pr-creation-guide.ja.md](pr-creation-guide.ja.md) 参照。

## Metrics 会計

Foundation sprint には rubric 軸がないので、axis 行は
`metrics.jsonl` に書かれない。代わりに accounting 用の 1 行を追記:

```json
{
  "ts": "<ISO>",
  "sprint": 0,
  "iter": 0,
  "agent": "orchestrator",
  "phase": "foundation-attest",
  "deliverables_pass": "<N>/<M>",
  "verdict": "pass" | "abort"
}
```

ファイルは行指向のまま保たれ、feature sprint の行と横比較できる
（shape は違うが line-oriented な点は一致）。

## 非目標

- 本プロトコルはコード品質を評価しない。attestation gate は
  インフラ準備完了の go/no-go を人間が判断する場であり、実装 craft の
  判定ではない。Rubric 採点は sprint-1 から再開。
- Foundation sprint は後続 sprint と branch を共有しない。SKILL.md Step 3
  に従い sprint ごと（foundation / feature 共通）に独立 branch を作る。
