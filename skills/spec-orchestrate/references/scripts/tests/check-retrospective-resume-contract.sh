#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/.." && pwd)"
REFERENCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE="$TEST_DIR/fixtures/retrospective-resume-contract.tsv"
PIPELINE_CONFIG="$REFERENCE_DIR/pipeline-config.md"
PIPELINE_CONFIG_JA="$REFERENCE_DIR/pipeline-config.ja.md"
RETROSPECTIVE_FORMAT="$REFERENCE_DIR/retrospective-format.md"
RETROSPECTIVE_FORMAT_JA="$REFERENCE_DIR/retrospective-format.ja.md"
IMPROVE_APPLY="$REFERENCE_DIR/improve-apply.md"
IMPROVE_APPLY_JA="$REFERENCE_DIR/improve-apply.ja.md"
STATE_CHECK="$SCRIPT_DIR/pipeline-state-check.sh"
LEDGER="$SCRIPT_DIR/retrospective-ledger.sh"
RUN_ID="2026-07-22T00:00:00Z-fixture"

fail() {
  printf 'FAIL\tretrospective-resume\t%s\n' "$*" >&2
  exit 1
}

sha256_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    fail "SHA-256 command is unavailable"
  fi
}

extract_contract() {
  awk '
    /<!-- retrospective-resume-contract:start -->/ { inside=1; next }
    /<!-- retrospective-resume-contract:end -->/ { inside=0 }
    inside { print }
  ' "$1"
}

validate_contract() {
  local file="$1" language="$2" field contract_id en_token ja_token token section
  [ "$(grep -c '<!-- retrospective-resume-contract:start -->' "$file")" -eq 1 ] || return 1
  [ "$(grep -c '<!-- retrospective-resume-contract:end -->' "$file")" -eq 1 ] || return 1
  section="$(extract_contract "$file")"
  [ -n "$section" ] || return 1
  case "$language" in en) field=2 ;; ja) field=3 ;; *) return 1 ;; esac
  while IFS=$'\t' read -r contract_id en_token ja_token; do
    [ "$contract_id" = contract_id ] && continue
    if [ "$field" -eq 2 ]; then token="$en_token"; else token="$ja_token"; fi
    printf '%s\n' "$section" | grep -Fq -- "$token" || return 1
  done < "$FIXTURE"
}

assert_contract_mutations_rejected() {
  local file="$1" language="$2" field contract_id en_token ja_token token mutant
  case "$language" in en) field=2 ;; ja) field=3 ;; *) return 1 ;; esac
  while IFS=$'\t' read -r contract_id en_token ja_token; do
    [ "$contract_id" = contract_id ] && continue
    if [ "$field" -eq 2 ]; then token="$en_token"; else token="$ja_token"; fi
    mutant="$tmp/contract-$language-$contract_id.md"
    awk -v token="$token" 'index($0, token) == 0 { print }' "$file" > "$mutant"
    if validate_contract "$mutant" "$language"; then
      fail "$language contract mutation survived: $contract_id"
    fi
  done < "$FIXTURE"
}

report_manifest() {
  local spec_dir="$1"
  find "$spec_dir" -type f \( -name 'report.json' -o -name '*-report.json' \) -print \
    | sed "s#^$spec_dir/##" | LC_ALL=C sort \
    | jq -Rsc 'split("\n") | map(select(length > 0))'
}

set_terminal_basis() {
  local spec_dir="$1" ts="$2" spec_rounds="$3" eval_rounds="$4" pr_status="$5"
  local draft spec_rounds_json eval_rounds_json
  [ "$pr_status" = draft ] && draft=true || draft=false
  spec_rounds_json="$(jq -n --argjson count "$spec_rounds" '[range(0; $count) | {round: (. + 1)}]')"
  eval_rounds_json="$(jq -n --argjson count "$eval_rounds" '[range(0; $count) | {round: (. + 1)}]')"
  if [ -f "$spec_dir/pipeline-state.json" ]; then
    jq --arg ts "$ts" --arg status "$pr_status" --argjson draft "$draft" \
      --argjson spec_rounds "$spec_rounds_json" --argjson eval_rounds "$eval_rounds_json" '
        .phase = "retrospective"
        | .completed_phases = ["intake", "spec_generate", "inspect", "spec_review",
            "approval", "implement", "evaluate", "pr", "retrospective"]
        | .rounds.spec_review = $spec_rounds
        | .rounds.evaluate = $eval_rounds
        | .pr = {url:"https://github.com/example/repo/pull/141", draft:$draft, status:$status}
        | .ts_updated = $ts
      ' "$spec_dir/pipeline-state.json" > "$spec_dir/pipeline-state.json.tmp"
    mv "$spec_dir/pipeline-state.json.tmp" "$spec_dir/pipeline-state.json"
  else
    jq -n --arg run "$RUN_ID" --arg ts "$ts" --arg status "$pr_status" \
      --argjson draft "$draft" --argjson spec_rounds "$spec_rounds_json" \
      --argjson eval_rounds "$eval_rounds_json" '{
        feature:"retrospective-resume-fixture", run_id:$run, mode:"auto", issue:141,
        language:"en", host_runtime:"codex", phase:"retrospective",
        completed_phases:["intake", "spec_generate", "inspect", "spec_review",
          "approval", "implement", "evaluate", "pr", "retrospective"],
        rounds:{spec_review:$spec_rounds, evaluate:$eval_rounds}, threads:{},
        role_overrides:{}, review_fallbacks:[], arbitrations:[],
        pr:{url:"https://github.com/example/repo/pull/141", draft:$draft, status:$status},
        ts_updated:$ts
      }' > "$spec_dir/pipeline-state.json"
  fi
}

finalize_revision() {
  local spec_dir="$1" revision="$2"
  local state manifest report_count state_hash snapshot snapshot_id record_id line
  state="$spec_dir/pipeline-state.json"
  manifest="$(report_manifest "$spec_dir")"
  report_count="$(printf '%s\n' "$manifest" | jq 'length')"
  state_hash="$(jq -cS 'del(.retrospective)' "$state" | sha256_stream)"
  snapshot="$(jq -nc --arg run "$RUN_ID" \
    --argjson completed "$(jq -c .completed_phases "$state")" \
    --argjson rounds_spec "$(jq '(.rounds.spec_review // []) | length' "$state")" \
    --argjson rounds_eval "$(jq '(.rounds.evaluate // []) | length' "$state")" \
    --argjson report_count "$report_count" --argjson report_manifest "$manifest" \
    --arg pr_url "$(jq -r .pr.url "$state")" --arg pr_status "$(jq -r .pr.status "$state")" \
    --arg state_ts "$(jq -r .ts_updated "$state")" --arg state_hash "$state_hash" '{
      run_id:$run, phase:"retrospective", completed_phases:$completed,
      rounds_spec:$rounds_spec, rounds_eval:$rounds_eval,
      report_count:$report_count, report_manifest:$report_manifest,
      pr_url:$pr_url, pr_status:$pr_status, state_ts_updated:$state_ts,
      state_hash:$state_hash
    }')"
  snapshot_id="$(printf '%s\n' "$snapshot" | jq -cS . | sha256_stream)"
  record_id="$RUN_ID:r$revision:$snapshot_id"
  jq --argjson revision "$revision" --arg snapshot_id "$snapshot_id" \
    --arg record_id "$record_id" --argjson snapshot "$snapshot" '
      .retrospective = {
        revision:$revision, snapshot_id:$snapshot_id, metrics_record_id:$record_id,
        snapshot:$snapshot, stale:false, regeneration_required:false,
        action_history:(.retrospective.action_history // [])
      }
    ' "$state" > "$state.final"
  printf '# Retrospective - fixture (%s)\ntype: retrospective\nstate_snapshot: %s\n' \
    "$RUN_ID" "$(printf '%s\n' "$snapshot" | jq -c .)" > "$spec_dir/retrospective.md"
  line="$(jq -nc --arg record_id "$record_id" --argjson revision "$revision" \
    --arg run "$RUN_ID" --arg snapshot_id "$snapshot_id" --argjson snapshot "$snapshot" \
    --argjson rounds_spec "$(jq '(.rounds.spec_review // []) | length' "$state")" \
    --argjson rounds_eval "$(jq '(.rounds.evaluate // []) | length' "$state")" \
    --arg ts "$(jq -r .ts_updated "$state")" '{
      record_type:"metrics", record_id:$record_id, revision:$revision,
      feature:"retrospective-resume-fixture", run_id:$run, mode:"auto",
      snapshot_id:$snapshot_id, snapshot:$snapshot, rounds_spec:$rounds_spec,
      rounds_eval:$rounds_eval, stalls:0, blocker_categories:{},
      applied_improvements:[], ts:$ts
    }')"
  bash "$LEDGER" append-metrics-once "$(dirname "$spec_dir")/pipeline-metrics.jsonl" "$line" >/dev/null
  mv "$state.final" "$state"
}

adopt_active_projection() {
  local spec_dir="$1" state active snapshot
  state="$spec_dir/pipeline-state.json"
  active="$(bash "$LEDGER" active "$(dirname "$spec_dir")/pipeline-metrics.jsonl" "$RUN_ID")"
  snapshot="$(printf '%s\n' "$active" | jq -c .snapshot)"
  jq --argjson active "$active" '
    .phase = $active.snapshot.phase
    | .completed_phases = $active.snapshot.completed_phases
    | .ts_updated = $active.snapshot.state_ts_updated
    | .retrospective = {
        revision:$active.revision, snapshot_id:$active.snapshot_id,
        metrics_record_id:$active.record_id, snapshot:$active.snapshot,
        stale:false, regeneration_required:false,
        action_history:(.retrospective.action_history // [])
      }
  ' "$state" > "$state.tmp"
  mv "$state.tmp" "$state"
  printf '# Retrospective - fixture (%s)\ntype: retrospective\nstate_snapshot: %s\n' \
    "$RUN_ID" "$snapshot" > "$spec_dir/retrospective.md"
}

assert_checker_fails() {
  local spec_dir="$1" expected="$2" output
  if output="$(bash "$STATE_CHECK" "$spec_dir" 2>&1)"; then
    fail "checker accepted mutation: $expected"
  fi
  printf '%s\n' "$output" | grep -Fq -- "$expected" ||
    fail "checker failed for an unrelated reason; expected '$expected': $output"
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/retrospective-resume.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

validate_contract "$PIPELINE_CONFIG" en || fail "English resume contract is incomplete"
validate_contract "$PIPELINE_CONFIG_JA" ja || fail "Japanese resume contract is incomplete"
assert_contract_mutations_rejected "$PIPELINE_CONFIG" en
assert_contract_mutations_rejected "$PIPELINE_CONFIG_JA" ja
for file in "$RETROSPECTIVE_FORMAT" "$RETROSPECTIVE_FORMAT_JA"; do
  grep -Fq 'state_snapshot:' "$file" || fail "$file lacks the report snapshot contract"
  grep -Fq 'list-active' "$file" || fail "$file lacks active-only comparison"
done
for file in "$IMPROVE_APPLY" "$IMPROVE_APPLY_JA"; do
  grep -Fq 'action_key' "$file" || fail "$file lacks external-action deduplication"
done
printf 'PASS\tcontract\tretrospective resume bilingual fixture and mutations\n'

legacy_metrics="$tmp/legacy-metrics.jsonl"
printf '%s\n' \
  '{"feature":"legacy","run_id":"legacy-run","rounds_spec":1}' \
  '{"feature":"legacy","run_id":"legacy-run","rounds_spec":2}' \
  > "$legacy_metrics"
if bash "$LEDGER" list-active "$legacy_metrics" >/dev/null 2>&1; then
  fail "duplicate legacy rows were silently selected"
fi
legacy_ids="$(bash "$LEDGER" list-metrics "$legacy_metrics" legacy-run | jq -r .record_id)"
[ "$(printf '%s\n' "$legacy_ids" | wc -l | tr -d ' ')" -eq 2 ] ||
  fail "legacy rows were not assigned synthetic ids"
legacy_oldest="$(printf '%s\n' "$legacy_ids" | head -1)"
legacy_newest="$(printf '%s\n' "$legacy_ids" | tail -1)"
legacy_event="$(jq -nc --arg id "supersede:$legacy_oldest:legacy_migration" \
  --arg target "$legacy_oldest" '{record_type:"supersede",event_id:$id,
    run_id:"legacy-run",supersedes:$target,reason:"legacy_migration"}')"
bash "$LEDGER" supersede-once "$legacy_metrics" "$legacy_event" >/dev/null
[ "$(bash "$LEDGER" active "$legacy_metrics" legacy-run | jq -r .record_id)" = "$legacy_newest" ] ||
  fail "legacy migration did not preserve the newest row"
legacy_event="$(jq -nc --arg id "supersede:$legacy_newest:legacy_migration" \
  --arg target "$legacy_newest" '{record_type:"supersede",event_id:$id,
    run_id:"legacy-run",supersedes:$target,reason:"legacy_migration"}')"
bash "$LEDGER" supersede-once "$legacy_metrics" "$legacy_event" >/dev/null
legacy_versioned='{"record_type":"metrics","record_id":"legacy-run:r1:snapshot","revision":1,"run_id":"legacy-run","snapshot_id":"snapshot"}'
bash "$LEDGER" append-metrics-once "$legacy_metrics" "$legacy_versioned" >/dev/null
[ "$(bash "$LEDGER" active-count "$legacy_metrics" legacy-run)" -eq 1 ] ||
  fail "legacy migration did not produce one versioned active record"
versioned_legacy_event='{"record_type":"supersede","event_id":"bad-legacy-migration","run_id":"legacy-run","supersedes":"legacy-run:r1:snapshot","reason":"legacy_migration"}'
if bash "$LEDGER" supersede-once "$legacy_metrics" "$versioned_legacy_event" >/dev/null 2>&1; then
  fail "legacy_migration accepted a versioned metrics record"
fi
printf 'PASS\tmigration\tduplicate legacy metrics normalized append-only\n'

root="$tmp/run"
spec_dir="$root/.specs/retrospective-resume-fixture"
metrics="$root/.specs/pipeline-metrics.jsonl"
mkdir -p "$spec_dir"
printf '{"status":"ok"}\n' > "$spec_dir/implement-report.json"
printf '{"status":"ok"}\n' > "$spec_dir/review-report.json"
set_terminal_basis "$spec_dir" "2026-07-22T00:10:00Z" 1 1 draft
finalize_revision "$spec_dir" 1
bash "$STATE_CHECK" "$spec_dir" >/dev/null || fail "valid revision 1 was rejected"
bash "$STATE_CHECK" "$spec_dir/" >/dev/null || fail "checker rejected a trailing-slash spec path"

crash_root="$tmp/finalization-crash"
cp -R "$root" "$crash_root"
jq 'del(.retrospective)' \
  "$crash_root/.specs/retrospective-resume-fixture/pipeline-state.json" > "$crash_root/state.tmp"
mv "$crash_root/state.tmp" "$crash_root/.specs/retrospective-resume-fixture/pipeline-state.json"
adopt_active_projection "$crash_root/.specs/retrospective-resume-fixture"
bash "$STATE_CHECK" "$crash_root/.specs/retrospective-resume-fixture" >/dev/null ||
  fail "active metrics projection could not be adopted after a finalization crash"

record_one="$(jq -r .retrospective.metrics_record_id "$spec_dir/pipeline-state.json")"
line_count="$(wc -l < "$metrics" | tr -d ' ')"
bash "$LEDGER" append-metrics-once "$metrics" "$(bash "$LEDGER" active "$metrics" "$RUN_ID")" >/dev/null
[ "$(wc -l < "$metrics" | tr -d ' ')" = "$line_count" ] || fail "same metrics record appended twice"

wrong_run_event="$(jq -nc --arg target "$record_one" '{
  record_type:"supersede", event_id:"wrong-run", run_id:"different-run",
  supersedes:$target, reason:"run_resumed"
}')"
if bash "$LEDGER" supersede-once "$metrics" "$wrong_run_event" >/dev/null 2>&1; then
  fail "supersede accepted a metrics record from another run"
fi

event="$(jq -nc --arg event "supersede:$record_one:run_resumed" --arg run "$RUN_ID" \
  --arg target "$record_one" '{record_type:"supersede",event_id:$event,run_id:$run,
    supersedes:$target,reason:"run_resumed",ts:"2026-07-22T00:20:00Z"}')"
bash "$LEDGER" supersede-once "$metrics" "$event" >/dev/null
bash "$LEDGER" supersede-once "$metrics" "$event" >/dev/null
[ "$(jq -cs '[.[] | select(.record_type == "supersede")] | length' "$metrics")" -eq 1 ] ||
  fail "resume event was not idempotent"
jq '.phase = "approval"
    | .retrospective.stale = true
    | .retrospective.regeneration_required = true
    | .ts_updated = "2026-07-22T00:20:00Z"' \
  "$spec_dir/pipeline-state.json" > "$spec_dir/pipeline-state.json.tmp"
mv "$spec_dir/pipeline-state.json.tmp" "$spec_dir/pipeline-state.json"
bash "$STATE_CHECK" "$spec_dir" >/dev/null || fail "valid stale resume state was rejected"
[ "$(bash "$LEDGER" active-count "$metrics" "$RUN_ID")" -eq 0 ] ||
  fail "superseded revision remained active"

revision_mutant="$tmp/revision-ledger.jsonl"
cp "$metrics" "$revision_mutant"
jump_line="$(bash "$LEDGER" list-metrics "$revision_mutant" "$RUN_ID" | head -1 \
  | jq -c '.record_id += ":jump" | .revision = 3')"
if bash "$LEDGER" append-metrics-once "$revision_mutant" "$jump_line" >/dev/null 2>&1; then
  fail "ledger accepted a non-monotonic revision jump"
fi

stale_mutant="$tmp/stale-mutant"
cp -R "$root" "$stale_mutant"
jq -c 'select(.record_type != "supersede")' "$stale_mutant/.specs/pipeline-metrics.jsonl" \
  > "$stale_mutant/.specs/pipeline-metrics.jsonl.tmp"
mv "$stale_mutant/.specs/pipeline-metrics.jsonl.tmp" "$stale_mutant/.specs/pipeline-metrics.jsonl"
assert_checker_fails "$stale_mutant/.specs/retrospective-resume-fixture" "not superseded exactly once"

printf '{"status":"ok"}\n' > "$spec_dir/revision-two-report.json"
set_terminal_basis "$spec_dir" "2026-07-22T00:30:00Z" 2 3 ready
finalize_revision "$spec_dir" 2
bash "$STATE_CHECK" "$spec_dir" >/dev/null || fail "valid revision 2 was rejected"
[ "$(bash "$LEDGER" active-count "$metrics" "$RUN_ID")" -eq 1 ] ||
  fail "revision 2 did not become the only active record"
[ "$(bash "$LEDGER" active "$metrics" "$RUN_ID" | jq -r .revision)" -eq 2 ] ||
  fail "active selector did not choose revision 2"

rounds_mutant="$tmp/rounds-mutant"
cp -R "$root" "$rounds_mutant"
jq '.rounds.spec_review += [{round:3}]' \
  "$rounds_mutant/.specs/retrospective-resume-fixture/pipeline-state.json" \
  > "$rounds_mutant/state.tmp"
mv "$rounds_mutant/state.tmp" "$rounds_mutant/.specs/retrospective-resume-fixture/pipeline-state.json"
assert_checker_fails "$rounds_mutant/.specs/retrospective-resume-fixture" "spec_review rounds differ"

report_mutant="$tmp/report-mutant"
cp -R "$root" "$report_mutant"
rm "$report_mutant/.specs/retrospective-resume-fixture/revision-two-report.json"
assert_checker_fails "$report_mutant/.specs/retrospective-resume-fixture" "report.json count differs"

pr_mutant="$tmp/pr-mutant"
cp -R "$root" "$pr_mutant"
jq '.pr = {url:.pr.url,draft:true,status:"draft"}' \
  "$pr_mutant/.specs/retrospective-resume-fixture/pipeline-state.json" > "$pr_mutant/state.tmp"
mv "$pr_mutant/state.tmp" "$pr_mutant/.specs/retrospective-resume-fixture/pipeline-state.json"
assert_checker_fails "$pr_mutant/.specs/retrospective-resume-fixture" "PR status differs"

hash_mutant="$tmp/hash-mutant"
cp -R "$root" "$hash_mutant"
jq '.mode = "manual"' \
  "$hash_mutant/.specs/retrospective-resume-fixture/pipeline-state.json" > "$hash_mutant/state.tmp"
mv "$hash_mutant/state.tmp" "$hash_mutant/.specs/retrospective-resume-fixture/pipeline-state.json"
assert_checker_fails "$hash_mutant/.specs/retrospective-resume-fixture" "state hash differs"

snapshot_id_mutant="$tmp/snapshot-id-mutant"
cp -R "$root" "$snapshot_id_mutant"
jq '.retrospective.snapshot_id = "corrupt"' \
  "$snapshot_id_mutant/.specs/retrospective-resume-fixture/pipeline-state.json" \
  > "$snapshot_id_mutant/state.tmp"
mv "$snapshot_id_mutant/state.tmp" \
  "$snapshot_id_mutant/.specs/retrospective-resume-fixture/pipeline-state.json"
assert_checker_fails "$snapshot_id_mutant/.specs/retrospective-resume-fixture" \
  "snapshot_id differs from the canonical snapshot hash"

report_snapshot_mutant="$tmp/report-snapshot-mutant"
cp -R "$root" "$report_snapshot_mutant"
mutant_spec="$report_snapshot_mutant/.specs/retrospective-resume-fixture"
mutant_snapshot="$(sed -n 's/^state_snapshot: //p' "$mutant_spec/retrospective.md" \
  | jq -c '.rounds_eval += 1')"
printf '# Retrospective - fixture (%s)\ntype: retrospective\nstate_snapshot: %s\n' \
  "$RUN_ID" "$mutant_snapshot" > "$mutant_spec/retrospective.md"
assert_checker_fails "$mutant_spec" "state_snapshot differs"

action_mutant="$tmp/action-mutant"
cp -R "$root" "$action_mutant"
jq '.retrospective.action_history = [{action_key:"same"},{action_key:"same"}]' \
  "$action_mutant/.specs/retrospective-resume-fixture/pipeline-state.json" > "$action_mutant/state.tmp"
mv "$action_mutant/state.tmp" "$action_mutant/.specs/retrospective-resume-fixture/pipeline-state.json"
assert_checker_fails "$action_mutant/.specs/retrospective-resume-fixture" "unique action-history metadata"

duplicate_mutant="$tmp/duplicate-mutant"
cp -R "$root" "$duplicate_mutant"
active_line="$(bash "$LEDGER" active "$duplicate_mutant/.specs/pipeline-metrics.jsonl" "$RUN_ID")"
printf '%s\n' "$(printf '%s\n' "$active_line" | jq -c '.record_id += ":duplicate"')" \
  >> "$duplicate_mutant/.specs/pipeline-metrics.jsonl"
if bash "$LEDGER" list-active "$duplicate_mutant/.specs/pipeline-metrics.jsonl" >/dev/null 2>&1; then
  fail "active selector accepted multiple records for one run"
fi
assert_checker_fails "$duplicate_mutant/.specs/retrospective-resume-fixture" "exactly one active metrics record"

last_byte="$(tail -c 1 "$FIXTURE" | od -An -t u1 | tr -d '[:space:]')"
[ "$last_byte" = 10 ] || fail "$FIXTURE must end with a newline"
printf 'PASS\truntime\tretrospective revision resync and state mutations\n'
