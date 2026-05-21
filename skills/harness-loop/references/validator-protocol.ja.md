# Validator Protocol

Step 4 negotiation と Step 6 implementation は同じ post-dispatch contract
を共有する。これらの step は任意ではない。

Generator または Evaluator dispatch の直後に、Orchestrator は必ず次を行う:

1. backend=`claude` では `.harness/scripts/claude-dispatch.sh
   --post-dispatch ...` を実行し、ファイル path / 命名を正規化し、subagent
   が期待出力を残さなかった場合は fallback file を合成する。
   `claude-dispatch.sh` は subagent を起動しない。`Task()` 呼び出しは
   Orchestrator の責務である。また `_state.json` も直接書き込まない。
2. `.harness/scripts/validate-<role>-report.sh ...` を実行し、schema 適合を
   強制する。Evaluator validator は `phases_executed` に `"3"` が含まれる
   場合、Phase 3 evidence の実在も検証する。
   - Generator implementation:
     `.harness/scripts/validate-generator-report.sh --report <sprint>/feedback/generator-<iter>-report.json --narrative <sprint>/feedback/generator-<iter>.md --report-dir <sprint>/feedback --phase impl`
   - Evaluator implementation:
     `.harness/scripts/validate-evaluator-report.sh --report <sprint>/feedback/evaluator-<iter>-report.json --narrative <sprint>/feedback/evaluator-<iter>.md --sprint-dir <sprint> --report-dir <sprint>/feedback --phase impl --strict`
3. validator が non-zero で終了した場合、状態遷移は Orchestrator が担当する:
   - `interactive`: `_state.json.pending_human=true` と `halt_reason` を書き、
     `progress-append.sh` 経由で halt line を残して停止する。
   - `continuous`, `autonomous-ralph`, `scheduled`:
     `consecutive_validator_violations` を増やし、次 iteration へ進めて
     retry する。3 連続違反で `pending_human=true` に escalate する。

`_state.json` と `progress.md` への書き込みは Orchestrator EXCLUSIVELY の
責務である。dispatch / validator script は対象 feedback file の変更、
stdout/stderr 出力、exit code 返却だけを行う。

## Validator-owned fields

Agent は正本 report 例に以下の field を自分で書かない:

- `validator_invoked`: validator が毎回 `true` を書く。
- `schema_version`: validator が現在の machine schema version を書く。
- `validator_violations`: validator が non-null array を書く。pass 時は空配列。
- `phase_3_evidence_status`: evaluator validator が `"present"`,
  `"missing"`, `"n/a"` のいずれかを書く。それ以外の値は invalid。

Phase 3 evidence は `${SPRINT_DIR}/evidence/iter-<n>/` に置く。
`evidence_refs[]` は `evidence/iter-<n>/quality-gate-command.log` のような
sprint-dir 相対 path にする。Evaluator validator は Playwright screenshot、
JSON/JSONL trace、`.spec.ts` に加え、non-UI artifact の `.log`,
`.test.ts`, `.txt`, `.md` も検出する。
