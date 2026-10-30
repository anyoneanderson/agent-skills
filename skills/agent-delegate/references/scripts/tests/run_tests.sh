#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(cd "$TEST_DIR/.." && pwd)/agent-delegate.sh"
HARNESS="$TEST_DIR/heartbeat_harness.sh"
QUALITY="$TEST_DIR/check_skill_quality.sh"
QUALITY_CONTRACT="$TEST_DIR/check_skill_quality_contract.sh"
STUB_DIR="$TEST_DIR/stubs"
JSON_TOOL="$(cd "$TEST_DIR/.." && pwd)/json-tool.mjs"
if command -v cygpath >/dev/null 2>&1; then JSON_TOOL="$(cygpath -m "$JSON_TOOL")"; fi
json_tool() { MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' node "$JSON_TOOL" "$@"; }
json_file() { local file="$1"; shift; [ -f "$file" ] && [ -r "$file" ] || return 2; json_tool "$@" < "$file"; }
FIXTURE_DIR="$TEST_DIR/fixtures"
REPO_ROOT="$(git -C "$TEST_DIR" rev-parse --show-toplevel)"
MANIFEST="$FIXTURE_DIR/case-manifest.tsv"
RUN_CASE=""
LIST=0
DRY_RUN=0
RUN_ALL=0
REPEAT=1
CURRENT_REPEAT_DIR=""
CURRENT_HEARTBEATS=0
CURRENT_TERMINALS=0

usage() {
  printf '%s\n' \
    'Usage: run_tests.sh --list-cases' \
    '       run_tests.sh [--dry-run] --case <case-name>' \
    '       run_tests.sh --all [--repeat N]'
}

die() { printf 'TEST_FAIL\t%s\n' "$*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"; }
sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --list-cases) LIST=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --case) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; RUN_CASE="$2"; shift 2 ;;
    --all) RUN_ALL=1; shift ;;
    --repeat) [ "$#" -ge 2 ] || { usage >&2; exit 2; }; REPEAT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'run-tests: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$REPEAT" in ''|*[!0-9]*|0) printf 'run-tests: --repeat must be a positive integer\n' >&2; exit 2 ;; esac
[ "$LIST" -eq 0 ] || { awk -F '\t' 'NR>1 {print $2}' "$MANIFEST"; exit 0; }
if [ "$RUN_ALL" -eq 1 ] && [ -n "$RUN_CASE" ]; then printf 'run-tests: choose --all or --case\n' >&2; exit 2; fi
if [ "$RUN_ALL" -eq 0 ] && [ -z "$RUN_CASE" ]; then usage >&2; exit 2; fi

manifest_line() { awk -F '\t' -v wanted="$1" 'NR>1 && $2==wanted {print; found=1} END{if(!found)exit 1}' "$MANIFEST"; }

dry_validate_case() {
  local case_name="$1" row fixture kind expected
  row="$(manifest_line "$case_name")" || die "unknown case: $case_name"
  kind="$(printf '%s\n' "$row" | cut -f3)"
  fixture="$(printf '%s\n' "$row" | cut -f5)"
  expected="$(printf '%s\n' "$row" | cut -f6)"
  case "$kind" in suite|meta) : ;; *) die "$case_name has invalid kind: $kind" ;; esac
  [ -n "$expected" ] || die "$case_name has no expected artifact"
  [ -f "$FIXTURE_DIR/$fixture" ] || die "$case_name fixture does not exist: $fixture"
  /bin/bash -n "$SCRIPT" "$HARNESS" "$QUALITY" "$QUALITY_CONTRACT" "$TEST_DIR/run_tests.sh" "$STUB_DIR/codex" "$STUB_DIR/claude"
  if grep -En '(^|[[:space:]])sleep([[:space:]]|$)|https?://|(^|[[:space:]])(curl|wget)([[:space:]]|$)' \
      "$HARNESS" "$QUALITY_CONTRACT" "$STUB_DIR/codex" "$STUB_DIR/claude" >/dev/null; then
    die "$case_name depends on sleep, network, or a real peer"
  fi
  [ -x "$HARNESS" ] && [ -x "$QUALITY" ] && [ -x "$QUALITY_CONTRACT" ] && [ -x "$STUB_DIR/codex" ] && [ -x "$STUB_DIR/claude" ] ||
    die "$case_name requires executable harness/checker/stubs"
  printf 'DRY_RUN_OK\t%s\t%s\t%s\n' "$case_name" "$fixture" "$expected"
}

new_work_dir() {
  local root
  root="$(cd "${TMPDIR:-/tmp}" && pwd)"
  mktemp -d "$root/agent-delegate-case.XXXXXX"
}

run_harness() {
  local out="$1" label="$2" target="$3" scenario="$4" result
  result="$(bash "$HARNESS" --out-dir "$out" --label "$label" --target "$target" --scenario "$scenario")"
  [ -f "$result" ] || die "harness did not return a result for $label"
  printf '%s' "$result"
}

check_harness_core() {
  local result="$1" min_beats="$2" expected_status="$3" run report heartbeat label out
  json_file "$result" -e --argjson min "$min_beats" --arg status "$expected_status" 'eq((type(d?.run_id)), "string") && (len(d?.run_id)) > 0 && eq((type(d?.launcher_pid)), "number") && eq((type(d?.monitor_pid)), "number") && !eq(d?.launcher_pid, d?.monitor_pid) && eq(d?.launcher_exit, 0) && eq(d?.peer_calls, 0) && d?.beat_count >= $.min && eq(d?.report_status, $.status) && eq(d?.handoff_removed, true)' >/dev/null || return 1
  run="$(json_file "$result" -r 'd?.run_id')"; report="$(json_file "$result" -r 'd?.report_path')"
  out="$(dirname "$result")"; label="$(basename "$result" -harness-result.json)"
  [ -f "$report" ] || return 1
  json_file "$report" -e --arg run "$run" --arg status "$expected_status" 'eq(d?.meta?.run_id, $.run) && eq(d?.status, $.status) && eq((type(d?.summary)), "string") && eq((type(d?.touchedFiles)), "array") && eq((type(d?.artifacts)), "object") && eq((type(d?.meta?.direction)), "string")' >/dev/null || return 1
  if [ "$min_beats" -gt 0 ]; then
    heartbeat="$(json_file "$result" -r 'd?.heartbeat_path')"
    [ -f "$heartbeat" ] || return 1
    json_file "$heartbeat" -e --arg run "$run" --arg state "$expected_status" 'eq(d?.run_id, $.run) && eq(d?.state, $.state) && eq((type(d?.pid)), "number") && eq((type(d?.monitor_pid)), "number") && eq((type(d?.started_at)), "string") && eq((type(d?.last_beat)), "string") && eq((type(d?.report_path)), "string")' >/dev/null || return 1
    [ -f "$out/$label-heartbeat-1.json" ] && [ -f "$out/$label-owner-1.json" ] || return 1
    json_file "$out/$label-owner-1.json" -e --argjson heartbeat "$(cat "$out/$label-heartbeat-1.json")" --arg run "$run" 'eq(d?.run_id, $.run) && eq(d?.runner_pid, d?.monitor_pid) && eq(d?.worker_pid, $.heartbeat?.pid) && eq(d?.monitor_pid, $.heartbeat?.monitor_pid) && eq(d?.lease_at, $.heartbeat?.last_beat)' >/dev/null || return 1
  fi
  [ -f "$out/$label-owner-before-worker.json" ] && [ -f "$out/$label-pid-before-worker.txt" ] &&
    [ -f "$out/$label-sentinel-ready.json" ] || return 1
  json_file "$out/$label-owner-before-worker.json" -e --arg run "$run" 'eq(d?.run_id, $.run) && eq(d?.run_kind, "detach") && eq(d?.runner_pid, d?.monitor_pid) && eq(d?.worker_pid, null) && eq(d?.handoff_phase, "not_started")' >/dev/null || return 1
  json_file "$out/$label-sentinel-ready.json" -e --arg run "$run" 'eq(d?.run_id, $.run) && eq(d?.state, "fifo_ready") && eq(d?.handoff_phase, "not_started") && eq((len(d?.created_fifos)), 4) && eq((len(d?.control_fifos)), 2)' >/dev/null || return 1
  [ -f "$out/$label-handoff-sentinel-cleanup.json" ] || return 1
  json_file "$out/$label-handoff-sentinel-cleanup.json" -e --arg run "$run" 'eq(d?.run_id, $.run) && eq(d?.state, "cleanup_pending")' >/dev/null || return 1
  [ ! -e "$out/$label-owner.json" ] && [ ! -e "$out/$label.pid" ] || return 1
}

check_harness_positive_and_negative() {
  local result="$1" min_beats="$2" expected_status="$3" bad_result bad_report original_report
  check_harness_core "$result" "$min_beats" "$expected_status" || die "raw harness artifacts rejected: $result"
  bad_result="${result%.json}.negative.json"; bad_report="${result%.json}.negative-report.json"
  original_report="$(json_file "$result" -r 'd?.report_path')"
  json_file "$original_report" '({...d, meta: {...d?.meta, run_id: "corrupted-run"}})' > "$bad_report"
  json_file "$result" --arg report "$bad_report" '({...d, report_path: $.report})' > "$bad_result"
  if check_harness_core "$bad_result" "$min_beats" "$expected_status"; then
    die "harness checker accepted corrupted run relation"
  fi
  rm -f "$bad_result" "$bad_report"
  CURRENT_HEARTBEATS=$((CURRENT_HEARTBEATS + min_beats))
  CURRENT_TERMINALS=$((CURRENT_TERMINALS + 1))
}

run_basic_harness_case() {
  local case_name="$1" scenario="$2" status="$3" beats="$4" dir result
  dir="$(new_work_dir)"; result="$(run_harness "$dir" "$case_name" claude "$scenario")"
  check_harness_positive_and_negative "$result" "$beats" "$status"
  rm -rf "$dir"
}

state_decision() {
  local report="$1" status="$2" owner="$3" heartbeat="$4" worker_source="$5"
  local monitor="$6" worker="$7" launch_age="$8" death_for="$9"
  if [ "$report" = valid ] && [ "$status" = done ]; then printf TERMINAL_DONE; return; fi
  if [ "$report" = valid ] && [ "$status" = blocked ]; then printf TERMINAL_BLOCKED; return; fi
  if [ "$owner" = other ]; then printf SUPERSEDED; return; fi
  if [ "$monitor" = absent ]; then
    if [ "$worker_source" = none ] || [ "$worker" = absent ]; then
      [ "$death_for" -ge 30 ] && printf DEAD || printf DEATH_CANDIDATE
    else
      printf ORPHANED_WORKER
    fi
    return
  fi
  if [ "$worker_source" != none ] && [ "$worker" = absent ]; then printf FINALIZING; return; fi
  if [ "$report" = invalid ] || [ "$report" = wrong-run ]; then printf REPORT_INVALID_PENDING; return; fi
  if [ "$heartbeat" = absent ]; then
    [ "$launch_age" -le 90 ] && printf STARTING || printf DEGRADED_NO_HEARTBEAT
  elif [ "$heartbeat" = unreadable ]; then printf DEGRADED_UNREADABLE
  elif [ "$heartbeat" = stale ]; then printf DEGRADED_STALE
  else printf RUNNING
  fi
}

check_state_fixture() {
  local file="$1" case_id report status owner heartbeat worker_source monitor worker launch_age death_for expected actual count=0
  while IFS=$'\t' read -r case_id report status owner heartbeat worker_source monitor worker launch_age death_for expected; do
    [ "$case_id" = case_id ] && continue
    count=$((count + 1))
    case "$report" in valid|absent|invalid|wrong-run) : ;; *) return 1 ;; esac
    case "$owner" in expected|other) : ;; *) return 1 ;; esac
    case "$heartbeat" in any|absent|unreadable|fresh|stale) : ;; *) return 1 ;; esac
    case "$worker_source" in none|owner|heartbeat) : ;; *) return 1 ;; esac
    case "$monitor" in any|alive|absent|unknown) : ;; *) return 1 ;; esac
    case "$worker" in alive|absent|unknown|unpublished) : ;; *) return 1 ;; esac
    case "$launch_age" in ''|*[!0-9]*) return 1 ;; esac
    case "$death_for" in ''|*[!0-9]*) return 1 ;; esac
    if [ "$worker_source" = none ]; then
      [ "$worker" = unpublished ] || return 1
    else
      [ "$worker" != unpublished ] || return 1
    fi
    actual="$(state_decision "$report" "$status" "$owner" "$heartbeat" "$worker_source" \
      "$monitor" "$worker" "$launch_age" "$death_for")"
    [ "$actual" = "$expected" ] || return 1
  done < "$file"
  [ "$count" -gt 0 ]
}

check_missing_heartbeat_contract_docs() {
  grep -Fq '| heartbeat not generated, worker PID either unpublished or published with worker alive or unknown, monitor alive or unknown, launch age at most 90 seconds | `STARTING` |' \
    "$REPO_ROOT/skills/agent-delegate/references/contract.md" &&
    grep -Fq '| heartbeat not generated after 90 seconds, worker PID either unpublished or published with worker alive or unknown, monitor alive or unknown | `DEGRADED_NO_HEARTBEAT` |' \
      "$REPO_ROOT/skills/agent-delegate/references/contract.md" &&
    grep -Fq '| heartbeat が未生成、worker PID が未公開、または公開済みでworkerが生存・不明、monitor が生存または不明、起動から90秒以内 | `STARTING` |' \
      "$REPO_ROOT/skills/agent-delegate/references/contract.ja.md" &&
    grep -Fq '| 起動から90秒を超えて heartbeat が未生成、worker PID が未公開、または公開済みでworkerが生存・不明、monitor が生存または不明 | `DEGRADED_NO_HEARTBEAT` |' \
      "$REPO_ROOT/skills/agent-delegate/references/contract.ja.md"
}

wait_decision() {
  local elapsed="$1" state="$2" owner="$3" monitor="$4" stop_age="$5" terminal="$6"
  case "$terminal" in done) printf TERMINAL_DONE; return ;; blocked) printf TERMINAL_BLOCKED; return ;; esac
  if [ "$owner" = other ]; then printf SUPERSEDED; return; fi
  if [ "$state" = DEAD ]; then printf DEAD; return; fi
  if [ "$elapsed" -ge 7200 ]; then
    if [ "$stop_age" -gt 0 ]; then
      [ "$stop_age" -lt 90 ] && printf WAIT_TERMINAL || printf ESCALATE_STOP_WAITING
    elif [ "$monitor" = alive ]; then
      printf TERM_MONITOR
    else
      printf ESCALATE_STOP_WAITING
    fi
    return
  fi
  if [ "$elapsed" -gt 0 ] && [ $((elapsed % 1800)) -eq 0 ]; then
    printf REEVALUATE_CONTINUE
  else
    printf WAIT
  fi
}

check_wait_fixture() {
  local file="$1" case_id elapsed state owner monitor stop_age terminal expected actual count=0
  while IFS=$'\t' read -r case_id elapsed state owner monitor stop_age terminal expected; do
    [ "$case_id" = case_id ] && continue
    count=$((count + 1))
    case "$elapsed" in ''|*[!0-9]*) return 1 ;; esac
    case "$stop_age" in ''|*[!0-9]*) return 1 ;; esac
    case "$state" in RUNNING|STARTING|DEGRADED_*|ORPHANED_WORKER|FINALIZING|REPORT_INVALID_PENDING|DEAD) : ;; *) return 1 ;; esac
    case "$owner" in expected|other) : ;; *) return 1 ;; esac
    case "$monitor" in alive|absent|unknown) : ;; *) return 1 ;; esac
    case "$terminal" in none|done|blocked) : ;; *) return 1 ;; esac
    actual="$(wait_decision "$elapsed" "$state" "$owner" "$monitor" "$stop_age" "$terminal")"
    [ "$actual" = "$expected" ] || return 1
  done < "$file"
  [ "$count" -gt 0 ]
}

artifact_recovery_decision() {
  local report="$1" status="$2" blocker_category="$3" run_relation="$4" mode="$5"
  local artifact_path="$6" fresh="$7" correlation="$8" structure="$9" tags="${10}"
  local gate="${11}" readonly_evidence="${12}" validator="${13}"
  if [ "$report" != valid ] || [ "$status" != blocked ] || [ "$blocker_category" != env_error ] ||
     [ "$run_relation" != expected ] || [ "$artifact_path" != declared ] ||
     [ "$fresh" != yes ] || [ "$correlation" != yes ]; then
    printf REJECT_RECOVERY
    return
  fi
  case "$mode" in
    review)
      if [ "$structure" = valid ] && [ "$tags" = valid ] && [ "$gate" = consistent ] &&
         [ "$readonly_evidence" = clean ]; then
        printf ACCEPT_RECOVERY
      else
        printf REJECT_RECOVERY
      fi
      ;;
    delegate)
      [ "$validator" = pass ] && printf ACCEPT_RECOVERY || printf REJECT_RECOVERY
      ;;
    *) printf REJECT_RECOVERY ;;
  esac
}

check_artifact_recovery_fixture() {
  local file="$1" case_id report status blocker_category run_relation mode artifact_path fresh
  local correlation structure tags gate readonly_evidence validator expected actual count=0
  while IFS=$'\t' read -r case_id report status blocker_category run_relation mode artifact_path fresh \
    correlation structure tags gate readonly_evidence validator expected; do
    [ "$case_id" = case_id ] && continue
    count=$((count + 1))
    case "$report" in valid|absent|invalid) : ;; *) return 1 ;; esac
    case "$status" in done|blocked|none) : ;; *) return 1 ;; esac
    case "$blocker_category" in env_error|timeout|none) : ;; *) return 1 ;; esac
    case "$run_relation" in expected|wrong) : ;; *) return 1 ;; esac
    case "$mode" in review|delegate) : ;; *) return 1 ;; esac
    case "$artifact_path" in declared|other) : ;; *) return 1 ;; esac
    case "$fresh" in yes|no) : ;; *) return 1 ;; esac
    case "$correlation" in yes|no) : ;; *) return 1 ;; esac
    actual="$(artifact_recovery_decision "$report" "$status" "$blocker_category" "$run_relation" \
      "$mode" "$artifact_path" "$fresh" "$correlation" "$structure" "$tags" "$gate" \
      "$readonly_evidence" "$validator")"
    [ "$actual" = "$expected" ] || return 1
  done < "$file"
  [ "$count" -ge 20 ]
}

check_artifact_recovery_docs() {
  local file="$1" case_id relative token expected count=0
  awk -F '\t' '
    NR==1 {if ($0!="case_id\trelative_path\ttoken\texpected") exit 1; next}
    NF!=4 || $1=="" || $2=="" || $3=="" || $4=="" || seen[$1]++ {exit 1}
    END {if (NR<2) exit 1}
  ' "$file" || return 1
  while IFS=$'\t' read -r case_id relative token expected; do
    [ "$case_id" = case_id ] && continue
    count=$((count + 1))
    [ -f "$REPO_ROOT/$relative" ] || return 1
    check_contract_section "$REPO_ROOT/$relative" "$token" "$expected" || return 1
  done < "$file"
  [ "$count" -ge 16 ]
}

corrupt_fixture_expectation() {
  local source="$1" case_id="$2" replacement="$3" destination="$4"
  awk -v id="$case_id" -v replacement="$replacement" 'BEGIN{FS=OFS="\t"} $1==id{$NF=replacement} {print}' \
    "$source" > "$destination"
}

check_wait_contract_docs() {
  local fixture="$FIXTURE_DIR/document-contract.tsv" id en ja en_expected ja_expected
  while IFS=$'\t' read -r id en ja en_expected ja_expected; do
    case "$id" in
      reevaluation|hard-stop|termination-grace|automatic-force)
        grep -Fq -- "$en" "$REPO_ROOT/skills/agent-delegate/references/contract.md" || return 1
        grep -Fq -- "$ja" "$REPO_ROOT/skills/agent-delegate/references/contract.ja.md" || return 1
        grep -Fq -- "$en" "$REPO_ROOT/skills/spec-orchestrate/references/role-dispatch.md" || return 1
        grep -Fq -- "$ja" "$REPO_ROOT/skills/spec-orchestrate/references/role-dispatch.ja.md" || return 1
        ;;
    esac
  done < "$fixture"
  grep -Fq '2 hours' "$REPO_ROOT/skills/agent-delegate/SKILL.md" &&
    grep -Fq '2 hours' "$REPO_ROOT/skills/spec-implement/SKILL.md" &&
    grep -Fq '2 hours' "$REPO_ROOT/skills/spec-evaluate/SKILL.md"
}

stale_decision() {
  local alive="$1" age="$2" runs="$3" pids="$4" launcher="$5"
  if [ "$alive" = no ] && [ "$age" -gt 90 ] && [ "$runs" = yes ] && [ "$pids" = yes ] && [ "$launcher" = yes ]; then
    printf remove
  else
    printf retain
  fi
}

check_ownership_fixture() {
  local file="$1" id alive age runs pids launcher expected actual
  while IFS=$'\t' read -r id alive age runs pids launcher expected; do
    [ "$id" = case_id ] && continue
    actual="$(stale_decision "$alive" "$age" "$runs" "$pids" "$launcher")"
    [ "$actual" = "$expected" ] || return 1
  done < "$file"
}

check_shared_run_files() {
  local dir="$1" run="$2"
  json_file "$dir/report.json" -e --arg run "$run" 'eq(d?.meta?.run_id, $.run)' >/dev/null &&
    json_file "$dir/heartbeat.json" -e --arg run "$run" 'eq(d?.run_id, $.run)' >/dev/null &&
    json_file "$dir/owner.json" -e --arg run "$run" 'eq(d?.run_id, $.run)' >/dev/null &&
    [ "$(awk -F ': ' '$1=="run_id"{print $2;exit}' "$dir/pid")" = "$run" ]
}

absent_test_pid() {
  local pid=999999
  while kill -0 "$pid" 2>/dev/null; do pid=$((pid + 1)); done
  printf '%s' "$pid"
}

stale_reaper_removed_artifacts() {
  local handoff="$1" owner="$2" pid_file="$3"
  [ ! -e "$handoff" ] && [ ! -L "$handoff" ] &&
    [ ! -e "$handoff/launcher-to-monitor.fifo" ] &&
    [ ! -e "$handoff/monitor-to-launcher.fifo" ] &&
    [ ! -e "$handoff/handoff-sentinel.json" ] &&
    [ ! -e "$owner" ] && [ ! -e "$pid_file" ]
}

check_live_stale_reaper_result() {
  local action="$1" diagnostic="$2" fifo_state="$3" handoff="$4" owner="$5" pid_file="$6" stderr_file="$7"
  case "$action" in
    remove)
      stale_reaper_removed_artifacts "$handoff" "$owner" "$pid_file" &&
        ! grep -q 'stale-reaper retained' "$stderr_file"
      ;;
    retain)
      [ -d "$handoff" ] && [ ! -L "$handoff" ] && [ -f "$owner" ] && [ -f "$pid_file" ] || return 1
      case "$diagnostic" in
        invalid_sentinel) grep -q 'stale-reaper retained invalid_sentinel' "$stderr_file" || return 1 ;;
        unknown_entry) grep -q 'stale-reaper retained handoff directory with unknown entry: outside-link' "$stderr_file" || return 1 ;;
        *) return 1 ;;
      esac
      case "$fifo_state" in
        present) [ -p "$handoff/launcher-to-monitor.fifo" ] && [ -p "$handoff/monitor-to-launcher.fifo" ] ;;
        absent) [ ! -e "$handoff/launcher-to-monitor.fifo" ] && [ ! -e "$handoff/monitor-to-launcher.fifo" ] ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

check_live_stale_reaper_fixture() {
  local file="$1" prefix="$2" id sentinel_variant expected_action expected_diagnostic expected_fifo_state
  local dir root handoff new_handoff outside_file label run_id sentinel_run launcher_pid monitor_pid owner pid_file
  local stderr_file rc owner_hash pid_hash outside_hash case_ok
  root="$(cd "${TMPDIR:-/tmp}" && pwd)"
  while IFS=$'\t' read -r id sentinel_variant expected_action expected_diagnostic expected_fifo_state; do
    [ "$id" = case_id ] && continue
    case_ok=1
    dir="$(new_work_dir)"; label="$prefix-$id"; printf 'prompt\n' > "$dir/prompt.md"
    launcher_pid=101; monitor_pid="$(absent_test_pid)"; run_id="stale-$id"
    handoff="$(mktemp -d "$root/agent-delegate-handoff.${launcher_pid}.XXXXXX")"
    new_handoff="$(mktemp -d "$root/agent-delegate-heartbeat-handoff.XXXXXX")"
    chmod 700 "$handoff" "$new_handoff"
    mkfifo "$handoff/launcher-to-monitor.fifo" "$handoff/monitor-to-launcher.fifo"
    outside_file=""
    case "$sentinel_variant" in
      valid|run_id_mismatch)
        sentinel_run="$run_id"
        [ "$sentinel_variant" != run_id_mismatch ] || sentinel_run="mutated-$run_id"
        json_tool -n --arg run_id "$sentinel_run" --argjson launcher_pid "$launcher_pid" \
          --argjson monitor_pid "$monitor_pid" --arg handoff_dir "$handoff" '
            ({run_id:$.run_id,launcher_pid:$.launcher_pid,monitor_pid:$.monitor_pid,
             handoff_dir:$.handoff_dir,
             created_fifos:["launcher-to-monitor.fifo","monitor-to-launcher.fifo"]})
          ' > "$handoff/handoff-sentinel.json"
        ;;
      absent_with_external_symlink)
        outside_file="$dir/outside-protected.txt"
        printf 'must survive stale reaping\n' > "$outside_file"
        ln -s "$outside_file" "$handoff/outside-link"
        ;;
      *) case_ok=0 ;;
    esac
    owner="$dir/$label-owner.json"; pid_file="$dir/$label.pid"; stderr_file="$dir/$label.err"
    json_tool -n --arg run_id "$run_id" --argjson launcher_pid "$launcher_pid" \
      --argjson monitor_pid "$monitor_pid" --arg handoff_dir "$handoff" '
        ({run_id:$.run_id,run_kind:"detach",runner_pid:$.monitor_pid,
         launcher_pid:$.launcher_pid,monitor_pid:$.monitor_pid,worker_pid:null,
         started_at:"2000-01-01T00:00:00Z",lease_at:"2000-01-01T00:00:00Z",
         handoff_dir:$.handoff_dir,handoff_phase:"not_started"})
      ' > "$owner"
    printf 'pid: %s\nrun_id: %s\n' "$monitor_pid" "$run_id" > "$pid_file"
    owner_hash="$(sha256_file "$owner")"; pid_hash="$(sha256_file "$pid_file")"
    outside_hash=""; [ -z "$outside_file" ] || outside_hash="$(sha256_file "$outside_file")"

    [ -p "$handoff/launcher-to-monitor.fifo" ] && [ -p "$handoff/monitor-to-launcher.fifo" ] || case_ok=0
    set +e
    AGENT_DELEGATE_TEST_MODE=heartbeat AGENT_DELEGATE_TEST_HANDOFF_DIR="$new_handoff" \
      AGENT_DELEGATE_TEST_FAIL_STAGE=new_pid \
      bash "$SCRIPT" --mode delegate --prompt-file "$dir/prompt.md" --out-dir "$dir" --label "$label" \
        --target claude --detach > "$dir/$label.out" 2> "$stderr_file"
    rc=$?
    set -e
    [ "$rc" -eq 2 ] || case_ok=0
    check_live_stale_reaper_result "$expected_action" "$expected_diagnostic" "$expected_fifo_state" \
      "$handoff" "$owner" "$pid_file" "$stderr_file" || case_ok=0

    if [ "$expected_action" = retain ]; then
      [ "$(sha256_file "$owner")" = "$owner_hash" ] && [ "$(sha256_file "$pid_file")" = "$pid_hash" ] || case_ok=0
    fi
    if [ "$sentinel_variant" = run_id_mismatch ]; then
      if check_live_stale_reaper_result remove none absent "$handoff" "$owner" "$pid_file" "$stderr_file"; then
        case_ok=0
      fi
      [ -f "$handoff/handoff-sentinel.json" ] || case_ok=0
    fi
    if [ "$sentinel_variant" = absent_with_external_symlink ]; then
      [ -L "$handoff/outside-link" ] && [ "$(readlink "$handoff/outside-link")" = "$outside_file" ] &&
        [ "$(sha256_file "$outside_file")" = "$outside_hash" ] || case_ok=0
    fi

    rm -f "$handoff/launcher-to-monitor.fifo" "$handoff/monitor-to-launcher.fifo" \
      "$handoff/handoff-sentinel.json" "$handoff/outside-link"
    rmdir "$handoff" 2>/dev/null || true
    rmdir "$new_handoff" 2>/dev/null || true
    rm -rf "$dir"
    [ "$case_ok" -eq 1 ] || return 1
  done < "$file"
}

run_sync() {
  local dir="$1" label="$2" target="$3" mode="$4" stub_mode="$5" extra="${6:-}" rc report workspace_path
  printf 'stub prompt\n' > "$dir/$label-prompt.md"
  mkdir -p "$dir/home/.codex"
  printf '[projects."%s"]\ntrust_level = "trusted"\n' "$REPO_ROOT" > "$dir/home/.codex/config.toml"
  workspace_path="$(pwd)"
  if [ "$workspace_path" != "$REPO_ROOT" ]; then
    printf '\n[projects."%s"]\ntrust_level = "trusted"\n' "$workspace_path" >> "$dir/home/.codex/config.toml"
  fi
  set +e
  HOME="$dir/home" PATH="$STUB_DIR:$PATH" AGENT_DELEGATE_STUB_MODE="$stub_mode" AGENT_DELEGATE_STUB_REVIEW="$([ "$mode" = review ] && printf 1 || printf 0)" \
    bash "$SCRIPT" --mode "$mode" --prompt-file "$dir/$label-prompt.md" --out-dir "$dir" --label "$label" \
      --target "$target" --sandbox workspace-write $extra > "$dir/$label-launch.out" 2> "$dir/$label-launch.err"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || return "$rc"
  report="$(tail -1 "$dir/$label-launch.out")"
  [ "$report" = "$dir/$label-report.json" ] && [ -f "$report" ] || return 1
  json_file "$report" -e --arg target "$target" --arg mode "$mode" '((eq(d?.status, "done") || eq(d?.status, "blocked"))) && eq((type(d?.meta?.run_id)), "string") && eq(d?.meta?.mode, $.mode) && eq((type(d?.touchedFiles)), "array") && eq((type(d?.artifacts)), "object")' >/dev/null
}

pid_is_running() {
  local state
  state="$(ps -o stat= -p "$1" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$state" ] && [[ "$state" != Z* ]]
}

wait_for_pid_stop() {
  local pid="$1" deadline=$(( $(date -u +%s) + 10 ))
  while [ "$(date -u +%s)" -lt "$deadline" ]; do
    pid_is_running "$pid" || return 0
  done
  return 1
}

run_stale_detach_and_sync_owner() (
  local root dir label handoff probe_handoff monitor rc owner_hash pid_hash barrier sync_pid peer old_run new_run deadline
  root="$(cd "${TMPDIR:-/tmp}" && pwd)"
  dir="$(new_work_dir)"
  trap '[ -z "${sync_pid:-}" ] || kill -TERM "$sync_pid" 2>/dev/null || true
    [ -z "${peer:-}" ] || kill -TERM "$peer" 2>/dev/null || true
    rm -rf "$dir" "${handoff:-}" "${probe_handoff:-}"' EXIT TERM INT HUP
  printf 'prompt\n' > "$dir/prompt.md"

  label=stale-detach
  monitor="$(absent_test_pid)"
  handoff="$root/agent-delegate-handoff.101.missing"
  rm -rf "$handoff"
  json_tool -n --arg handoff "$handoff" --argjson monitor "$monitor" '
    ({run_id:"stale-detach-run",run_kind:"detach",runner_pid:$.monitor,launcher_pid:101,
     monitor_pid:$.monitor,worker_pid:null,started_at:"2000-01-01T00:00:00Z",
     lease_at:"2000-01-01T00:00:00Z",handoff_dir:$.handoff,handoff_phase:"not_started"})
  ' > "$dir/$label-owner.json"
  printf 'pid: %s\nrun_id: stale-detach-run\n' "$monitor" > "$dir/$label.pid"
  probe_handoff="$(mktemp -d "$root/agent-delegate-heartbeat-handoff.XXXXXX")"; chmod 700 "$probe_handoff"
  set +e
  AGENT_DELEGATE_TEST_MODE=heartbeat AGENT_DELEGATE_TEST_HANDOFF_DIR="$probe_handoff" \
    AGENT_DELEGATE_TEST_FAIL_STAGE=new_pid bash "$SCRIPT" --mode delegate --prompt-file "$dir/prompt.md" \
      --out-dir "$dir" --label "$label" --target claude --detach > "$dir/$label.out" 2> "$dir/$label.err"
  rc=$?
  set -e
  [ "$rc" -eq 2 ] && [ ! -e "$dir/$label-owner.json" ] && [ ! -e "$dir/$label.pid" ] || return 1
  rm -rf "$probe_handoff"; probe_handoff=""

  label=stale-detach-negative
  handoff="$root/agent-delegate-handoff.101.owner-mismatch"
  rm -rf "$handoff"
  json_tool -n --arg handoff "$handoff" --argjson monitor "$monitor" '
    ({run_id:"negative-detach-run",run_kind:"detach",runner_pid:$.monitor,launcher_pid:102,
     monitor_pid:$.monitor,worker_pid:null,started_at:"2000-01-01T00:00:00Z",
     lease_at:"2000-01-01T00:00:00Z",handoff_dir:$.handoff,handoff_phase:"not_started"})
  ' > "$dir/$label-owner.json"
  printf 'pid: %s\nrun_id: negative-detach-run\n' "$monitor" > "$dir/$label.pid"
  owner_hash="$(sha256_file "$dir/$label-owner.json")"; pid_hash="$(sha256_file "$dir/$label.pid")"
  probe_handoff="$(mktemp -d "$root/agent-delegate-heartbeat-handoff.XXXXXX")"; chmod 700 "$probe_handoff"
  set +e
  AGENT_DELEGATE_TEST_MODE=heartbeat AGENT_DELEGATE_TEST_HANDOFF_DIR="$probe_handoff" \
    AGENT_DELEGATE_TEST_FAIL_STAGE=new_pid bash "$SCRIPT" --mode delegate --prompt-file "$dir/prompt.md" \
      --out-dir "$dir" --label "$label" --target claude --detach > "$dir/$label.out" 2> "$dir/$label.err"
  rc=$?
  set -e
  [ "$rc" -eq 2 ] && [ "$(sha256_file "$dir/$label-owner.json")" = "$owner_hash" ] &&
    [ "$(sha256_file "$dir/$label.pid")" = "$pid_hash" ] || return 1
  rm -rf "$probe_handoff"; probe_handoff=""

  label=stale-sync; barrier="$dir/sync-barrier"; mkdir "$barrier"; mkfifo "$barrier/release.fifo"
  PATH="$STUB_DIR:$PATH" AGENT_DELEGATE_STUB_BARRIER_DIR="$barrier" bash "$SCRIPT" --mode delegate \
    --prompt-file "$dir/prompt.md" --out-dir "$dir" --label "$label" --target claude --sandbox workspace-write \
    > "$dir/$label-old.out" 2> "$dir/$label-old.err" &
  sync_pid=$!; deadline=$(( $(date -u +%s) + 10 ))
  while [ "$(date -u +%s)" -lt "$deadline" ]; do
    [ -f "$barrier/claude.ready" ] && [ -f "$dir/$label-owner.json" ] && break
    pid_is_running "$sync_pid" || break
  done
  [ -f "$dir/$label-owner.json" ] && [ -f "$barrier/claude.pid" ] || return 1
  peer="$(cat "$barrier/claude.pid")"; old_run="$(json_file "$dir/$label-owner.json" -r 'd?.run_id')"
  kill -KILL "$sync_pid"; wait "$sync_pid" 2>/dev/null || true
  json_file "$dir/$label-owner.json" '({...d, lease_at: "2000-01-01T00:00:00Z"})' > "$dir/$label-owner.tmp"
  mv "$dir/$label-owner.tmp" "$dir/$label-owner.json"
  run_sync "$dir" "$label" claude delegate done
  new_run="$(json_file "$dir/$label-report.json" -r 'd?.meta?.run_id')"
  [ "$new_run" != "$old_run" ] && [ ! -e "$dir/$label-owner.json" ] || return 1
  if pid_is_running "$peer"; then printf 'release\n' > "$barrier/release.fifo"; fi
  wait_for_pid_stop "$peer" || kill -KILL "$peer" 2>/dev/null || true
)

run_live_sync_collision() (
  local dir label=live-sync barrier owner run pid peer deadline rc owner_hash report_hash stdout_hash last_hash
  dir="$(new_work_dir)"
  trap '[ -z "${pid:-}" ] || kill -TERM "$pid" 2>/dev/null || true
    [ -z "${peer:-}" ] || kill -TERM "$peer" 2>/dev/null || true
    rm -rf "$dir"' EXIT TERM INT HUP
  barrier="$dir/barrier"; mkdir "$barrier"; mkfifo "$barrier/release.fifo"; printf 'prompt\n' > "$dir/prompt.md"
  PATH="$STUB_DIR:$PATH" AGENT_DELEGATE_STUB_BARRIER_DIR="$barrier" bash "$SCRIPT" --mode delegate \
    --prompt-file "$dir/prompt.md" --out-dir "$dir" --label "$label" --target claude --sandbox workspace-write \
    > "$dir/first.out" 2> "$dir/first.err" &
  pid=$!; deadline=$(( $(date -u +%s) + 10 )); owner="$dir/$label-owner.json"
  while [ "$(date -u +%s)" -lt "$deadline" ]; do
    [ -f "$barrier/claude.ready" ] && [ -f "$owner" ] && break
    pid_is_running "$pid" || break
  done
  [ -f "$owner" ] || return 1
  run="$(json_file "$owner" -r 'd?.run_id')"; peer="$(cat "$barrier/claude.pid")"
  printf '{"protected":"report"}\n' > "$dir/$label-report.json"
  printf '{"protected":"stdout"}\n' > "$dir/$label-stdout.json"
  printf 'protected last\n' > "$dir/$label-last.txt"
  owner_hash="$(sha256_file "$owner")"; report_hash="$(sha256_file "$dir/$label-report.json")"
  stdout_hash="$(sha256_file "$dir/$label-stdout.json")"; last_hash="$(sha256_file "$dir/$label-last.txt")"
  set +e
  PATH="$STUB_DIR:$PATH" bash "$SCRIPT" --mode delegate --prompt-file "$dir/prompt.md" --out-dir "$dir" \
    --label "$label" --target claude > "$dir/collision.out" 2> "$dir/collision.err"
  rc=$?
  set -e
  [ "$rc" -eq 2 ] && grep -q "live sync run for label '$label'" "$dir/collision.err" || return 1
  [ "$(sha256_file "$owner")" = "$owner_hash" ] && [ "$(sha256_file "$dir/$label-report.json")" = "$report_hash" ] &&
    [ "$(sha256_file "$dir/$label-stdout.json")" = "$stdout_hash" ] && [ "$(sha256_file "$dir/$label-last.txt")" = "$last_hash" ] || return 1
  json_file "$owner" -e --arg run "$run" 'eq(d?.run_id, $.run) && eq(d?.run_kind, "sync")' >/dev/null || return 1
  [ ! -e "$dir/$label.pid" ] && [ ! -e "$dir/$label-heartbeat.json" ] || return 1
  printf 'release\n' > "$barrier/release.fifo"; wait "$pid"
  json_file "$dir/$label-report.json" -e --arg run "$run" 'eq(d?.meta?.run_id, $.run) && eq(d?.status, "done")' >/dev/null
)

run_stale_reaper_lock_timeout() (
  local dir label=lock-timeout rc
  dir="$(new_work_dir)"; trap 'rm -rf "$dir"' EXIT TERM INT HUP
  printf 'prompt\n' > "$dir/prompt.md"; mkdir "$dir/$label-owner.lock"
  printf 'pid: %s\nrun_id: live-lock-holder\n' "${BASHPID:-$$}" > "$dir/$label-owner.lock/holder"
  set +e
  PATH="$STUB_DIR:$PATH" bash "$SCRIPT" --mode delegate --prompt-file "$dir/prompt.md" --out-dir "$dir" \
    --label "$label" --target claude > "$dir/launch.out" 2> "$dir/launch.err"
  rc=$?
  set -e
  [ "$rc" -eq 2 ] && grep -q 'stale-reaper could not acquire the owner lock' "$dir/launch.err" || return 1
  [ -d "$dir/$label-owner.lock" ] && [ -f "$dir/$label-owner.lock/holder" ] || return 1
  [ ! -e "$dir/$label-report.json" ] && [ ! -e "$dir/$label-owner.json" ] && [ ! -e "$dir/$label.pid" ] &&
    [ ! -e "$dir/$label-heartbeat.json" ] && [ ! -e "$dir/$label-stdout.json" ] && [ ! -e "$dir/$label-last.txt" ]
)

run_force_orphan_peer_isolation() (
  local dir label=force-orphan barrier owner monitor worker peer handoff old_run new_run before_stdout before_last
  dir="$(new_work_dir)"; barrier="$dir/barrier"
  trap 'cleanup_detach_stub_fixture "$dir" "$label"' EXIT TERM INT HUP
  mkdir "$barrier"; mkfifo "$barrier/release.fifo"; printf 'prompt\n' > "$dir/prompt.md"
  launch_detach_review_stub "$dir" "$label" "$barrier" || return 1
  wait_for_detach_stub_runtime "$dir" "$label" "$barrier" || return 1
  owner="$dir/$label-owner.json"; monitor="$(json_file "$owner" -r 'd?.monitor_pid')"; worker="$(json_file "$owner" -r 'd?.worker_pid')"
  peer="$(cat "$barrier/claude.pid")"; handoff="$(json_file "$owner" -r 'd?.handoff_dir')"; old_run="$(json_file "$owner" -r 'd?.run_id')"
  [ "$(process_group_of "$monitor")" = "$monitor" ] && pid_is_running "$peer" || return 1
  kill -KILL "$worker" "$monitor" 2>/dev/null || return 1
  wait_for_pid_stop "$worker" || return 1; wait_for_pid_stop "$monitor" || return 1
  pid_is_running "$peer" || return 1
  json_file "$owner" '({...d, lease_at: "2000-01-01T00:00:00Z"})' > "$owner.tmp"; mv "$owner.tmp" "$owner"
  rm -rf "$handoff"
  run_sync "$dir" "$label" claude delegate done --force
  new_run="$(json_file "$dir/$label-report.json" -r 'd?.meta?.run_id')"
  [ "$new_run" != "$old_run" ] && wait_for_pid_stop "$peer" || return 1
  json_file "$dir/$label-report.json" -e --arg run "$new_run" 'eq(d?.meta?.run_id, $.run) && eq(d?.status, "done")' >/dev/null || return 1
  json_file "$dir/$label-stdout.json" -e 'eq(d?.session_id, "stub-claude-session") && eq(d?.result, "stub claude completed")' >/dev/null || return 1
  [ "$(cat "$dir/$label-last.txt")" = 'stub claude completed' ] || return 1
  before_stdout="$(sha256_file "$dir/$label-stdout.json")"; before_last="$(sha256_file "$dir/$label-last.txt")"
  [ "$(sha256_file "$dir/$label-stdout.json")" = "$before_stdout" ] &&
    [ "$(sha256_file "$dir/$label-last.txt")" = "$before_last" ]
)

check_readiness_timeout_sentinel() {
  local sentinel="$1" owner="$2"
  json_file "$sentinel" -e --argjson owner "$(cat "$owner")" 'eq(d?.state, "setup_failed") && eq(d?.failure_stage, "readiness_timeout") && eq(d?.handoff_phase, "not_started") && eq(d?.run_id, $.owner?.run_id) && eq(d?.launcher_pid, $.owner?.launcher_pid) && eq(d?.monitor_pid, $.owner?.monitor_pid) && eq((type(d?.created_fifos)), "array")' >/dev/null
}

run_setup_term_readiness_sentinel() (
  local root dir label=setup-term handoff barrier bin real_mkfifo launcher monitor deadline rc sentinel owner bad
  root="$(cd "${TMPDIR:-/tmp}" && pwd)"; dir="$(new_work_dir)"; barrier="$dir/barrier"; bin="$dir/bin"
  handoff="$(mktemp -d "$root/agent-delegate-heartbeat-handoff.XXXXXX")"; chmod 700 "$handoff"
  trap '[ -z "${monitor:-}" ] || kill -TERM "$monitor" 2>/dev/null || true
    [ -z "${launcher:-}" ] || kill -TERM "$launcher" 2>/dev/null || true
    rm -rf "$dir" "$handoff"' EXIT TERM INT HUP
  mkdir "$barrier" "$bin"; mkfifo "$barrier/release.fifo"; printf 'prompt\n' > "$dir/prompt.md"
  real_mkfifo="$(command -v mkfifo)"
  cat > "$bin/mkfifo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
"$AGENT_DELEGATE_REAL_MKFIFO" "$@"
if mkdir "$AGENT_DELEGATE_MKFIFO_ONCE" 2>/dev/null; then
  printf 'ready\n' > "$AGENT_DELEGATE_MKFIFO_READY"
  IFS= read -r _ < "$AGENT_DELEGATE_MKFIFO_RELEASE"
fi
EOF
  chmod +x "$bin/mkfifo"
  PATH="$bin:$STUB_DIR:$PATH" AGENT_DELEGATE_REAL_MKFIFO="$real_mkfifo" \
    AGENT_DELEGATE_MKFIFO_ONCE="$barrier/once" AGENT_DELEGATE_MKFIFO_READY="$barrier/mkfifo.ready" \
    AGENT_DELEGATE_MKFIFO_RELEASE="$barrier/release.fifo" AGENT_DELEGATE_TEST_MODE=heartbeat \
    AGENT_DELEGATE_TEST_HANDOFF_DIR="$handoff" bash "$SCRIPT" --mode delegate --prompt-file "$dir/prompt.md" \
      --out-dir "$dir" --label "$label" --target claude --detach > "$dir/launch.out" 2> "$dir/launch.err" &
  launcher=$!; deadline=$(( $(date -u +%s) + 10 )); owner="$dir/$label-owner.json"
  while [ "$(date -u +%s)" -lt "$deadline" ]; do
    [ -f "$owner" ] && [ -f "$barrier/mkfifo.ready" ] && break
    pid_is_running "$launcher" || break
  done
  [ -f "$owner" ] && [ -f "$barrier/mkfifo.ready" ] || return 1
  monitor="$(json_file "$owner" -r 'd?.monitor_pid')"; kill -TERM "$monitor"
  printf 'release\n' > "$barrier/release.fifo"
  set +e; wait "$launcher"; rc=$?; set -e
  [ "$rc" -eq 0 ] || return 1
  sentinel="$dir/$label-handoff-sentinel-final.json"; owner="$dir/$label-owner-final.json"
  check_readiness_timeout_sentinel "$sentinel" "$owner" || return 1
  json_file "$dir/$label-report.json" -e 'eq(d?.status, "blocked") && eq(d?.blocker_category, "env_error")' >/dev/null || return 1
  bad="$dir/$label-handoff-sentinel.negative.json"; json_file "$sentinel" '({...d, run_id: "corrupted-run"})' > "$bad"
  if check_readiness_timeout_sentinel "$bad" "$owner"; then return 1; fi
  [ ! -e "$dir/$label-owner.json" ] && [ ! -e "$dir/$label.pid" ] && [ ! -d "$handoff" ]
)

write_stale_detach_records() {
  local dir="$1" label="$2" handoff="$3" run="$4" launcher="$5" monitor="$6"
  json_tool -n --arg run "$run" --arg handoff "$handoff" --argjson launcher "$launcher" --argjson monitor "$monitor" '
    ({run_id:$.run,run_kind:"detach",runner_pid:$.monitor,launcher_pid:$.launcher,monitor_pid:$.monitor,
     worker_pid:null,started_at:"2000-01-01T00:00:00Z",lease_at:"2000-01-01T00:00:00Z",
     handoff_dir:$.handoff,handoff_phase:"not_started"})
  ' > "$dir/$label-owner.json"
  printf 'pid: %s\nrun_id: %s\n' "$monitor" "$run" > "$dir/$label.pid"
}

write_stale_sentinel() {
  local path="$1" run="$2" launcher="$3" monitor="$4" handoff="$5"
  json_tool -n --arg run "$run" --arg handoff "$handoff" --argjson launcher "$launcher" --argjson monitor "$monitor" '
    ({run_id:$.run,launcher_pid:$.launcher,monitor_pid:$.monitor,handoff_dir:$.handoff,
     created_fifos:["launcher-to-monitor.fifo","monitor-to-launcher.fifo"]})
  ' > "$path"
}

run_partial_handoff_safe_cleanup() (
  local root variant dir label handoff target probe monitor run rc expected owner_hash pid_hash
  root="$(cd "${TMPDIR:-/tmp}" && pwd)"; monitor="$(absent_test_pid)"
  trap 'rm -rf "${probe:-}" "${handoff:-}" "${target:-}" "${dir:-}"' EXIT TERM INT HUP
  for variant in missing-listed-fifo outside-root symlink unknown-entry sentinel-run-mismatch fifo-type-mismatch; do
    dir="$(new_work_dir)"; label="partial-$variant"; run="run-$variant"; printf 'prompt\n' > "$dir/prompt.md"
    target=""; expected=retain
    case "$variant" in
      missing-listed-fifo)
        handoff="$(mktemp -d "$root/agent-delegate-handoff.101.XXXXXX")"; chmod 700 "$handoff"
        mkfifo "$handoff/launcher-to-monitor.fifo"; expected=remove ;;
      outside-root)
        handoff="$dir/agent-delegate-handoff.101.outside"; mkdir -m 700 "$handoff"
        mkfifo "$handoff/launcher-to-monitor.fifo" ;;
      symlink)
        target="$dir/symlink-target"; mkdir -m 700 "$target"; mkfifo "$target/launcher-to-monitor.fifo"
        handoff="$root/agent-delegate-handoff.101.symlink"; rm -f "$handoff"; ln -s "$target" "$handoff" ;;
      unknown-entry)
        handoff="$(mktemp -d "$root/agent-delegate-handoff.101.XXXXXX")"; chmod 700 "$handoff"
        mkfifo "$handoff/launcher-to-monitor.fifo"; printf 'protected\n' > "$handoff/unknown-entry" ;;
      sentinel-run-mismatch)
        handoff="$(mktemp -d "$root/agent-delegate-handoff.101.XXXXXX")"; chmod 700 "$handoff"
        mkfifo "$handoff/launcher-to-monitor.fifo" ;;
      fifo-type-mismatch)
        handoff="$(mktemp -d "$root/agent-delegate-handoff.101.XXXXXX")"; chmod 700 "$handoff"
        printf 'not a fifo\n' > "$handoff/launcher-to-monitor.fifo" ;;
    esac
    write_stale_sentinel "$handoff/handoff-sentinel.json" "$run" 101 "$monitor" "$handoff"
    if [ "$variant" = sentinel-run-mismatch ]; then
      json_file "$handoff/handoff-sentinel.json" '({...d, run_id: "corrupted-run"})' > "$handoff/s.tmp"
      mv "$handoff/s.tmp" "$handoff/handoff-sentinel.json"
    fi
    write_stale_detach_records "$dir" "$label" "$handoff" "$run" 101 "$monitor"
    owner_hash="$(sha256_file "$dir/$label-owner.json")"; pid_hash="$(sha256_file "$dir/$label.pid")"
    probe="$(mktemp -d "$root/agent-delegate-heartbeat-handoff.XXXXXX")"; chmod 700 "$probe"
    set +e
    AGENT_DELEGATE_TEST_MODE=heartbeat AGENT_DELEGATE_TEST_HANDOFF_DIR="$probe" AGENT_DELEGATE_TEST_FAIL_STAGE=new_pid \
      bash "$SCRIPT" --mode delegate --prompt-file "$dir/prompt.md" --out-dir "$dir" --label "$label" \
        --target claude --detach > "$dir/launch.out" 2> "$dir/launch.err"
    rc=$?
    set -e
    [ "$rc" -eq 2 ] || return 1
    if [ "$expected" = remove ]; then
      [ ! -e "$handoff" ] && [ ! -L "$handoff" ] && [ ! -e "$dir/$label-owner.json" ] && [ ! -e "$dir/$label.pid" ] || return 1
    else
      { [ -d "$handoff" ] || [ -L "$handoff" ]; } && [ "$(sha256_file "$dir/$label-owner.json")" = "$owner_hash" ] &&
        [ "$(sha256_file "$dir/$label.pid")" = "$pid_hash" ] || return 1
      case "$variant" in
        outside-root) grep -q 'retained unsafe handoff path' "$dir/launch.err" || return 1 ;;
        symlink) [ -L "$handoff" ] && [ "$(readlink "$handoff")" = "$target" ] || return 1 ;;
        unknown-entry) [ "$(cat "$handoff/unknown-entry")" = protected ] || return 1 ;;
        sentinel-run-mismatch) grep -q 'retained invalid_sentinel' "$dir/launch.err" || return 1 ;;
        fifo-type-mismatch) [ -f "$handoff/launcher-to-monitor.fifo" ] || return 1 ;;
      esac
    fi
    rm -rf "$probe"; [ -L "$handoff" ] && rm -f "$handoff" || rm -rf "$handoff"; rm -rf "$target" "$dir"
  done
)

check_abnormal_cleanup_fixture() {
  local file="$1" id expected count=0
  while IFS=$'\t' read -r id expected; do
    [ "$id" = case_id ] && continue
    count=$((count + 1)); [ -n "$expected" ] || return 1
    case "$id" in
      stale-detach-and-sync-owner|live-sync-collision|stale-reaper-lock-timeout|force-orphan-peer-isolation|setup-term-readiness-sentinel|partial-handoff-safe-cleanup) : ;;
      *) return 1 ;;
    esac
  done < "$file"
  [ "$count" -eq 6 ]
}

case_abnormal_cleanup_real_filesystem() {
  local fixture="$FIXTURE_DIR/abnormal-cleanup-cases.tsv" id expected bad
  check_abnormal_cleanup_fixture "$fixture" || die 'abnormal cleanup fixture rejected'
  bad="$(mktemp "${TMPDIR:-/tmp}/agent-delegate-abnormal.XXXXXX")"
  awk 'BEGIN{FS=OFS="\t"} NR==2{$NF=""} {print}' "$fixture" > "$bad"
  if check_abnormal_cleanup_fixture "$bad"; then rm -f "$bad"; die 'abnormal cleanup checker accepted an empty expectation'; fi
  rm -f "$bad"
  while IFS=$'\t' read -r id expected; do
    [ "$id" = case_id ] && continue
    case "$id" in
      stale-detach-and-sync-owner) run_stale_detach_and_sync_owner || die "$id failed" ;;
      live-sync-collision) run_live_sync_collision || die "$id failed" ;;
      stale-reaper-lock-timeout) run_stale_reaper_lock_timeout || die "$id failed" ;;
      force-orphan-peer-isolation) run_force_orphan_peer_isolation || die "$id failed" ;;
      setup-term-readiness-sentinel) run_setup_term_readiness_sentinel || die "$id failed" ;;
      partial-handoff-safe-cleanup) run_partial_handoff_safe_cleanup || die "$id failed" ;;
    esac
  done < "$fixture"
}

case_heartbeat_schema_and_pids() { run_basic_harness_case "$1" done done 2; }

case_heartbeat_timing_contract() {
  local dir result label="$1" first second owner1 owner2
  dir="$(new_work_dir)"; result="$(run_harness "$dir" "$label" claude done)"
  check_harness_positive_and_negative "$result" 2 done
  first="$dir/$label-heartbeat-1.json"; second="$dir/$label-heartbeat-2.json"
  owner1="$dir/$label-owner-1.json"; owner2="$dir/$label-owner-2.json"
  json_file "$first" -e --argjson second "$(cat "$second")" 'eq(d?.run_id, $.second?.run_id) && eq(d?.started_at, $.second?.started_at) && d?.last_beat < $.second?.last_beat' >/dev/null
  json_file "$owner1" -e --argjson heartbeat "$(cat "$first")" 'eq(d?.run_id, $.heartbeat?.run_id) && eq(d?.lease_at, $.heartbeat?.last_beat)' >/dev/null
  json_file "$owner2" -e --argjson heartbeat "$(cat "$second")" 'eq(d?.run_id, $.heartbeat?.run_id) && eq(d?.lease_at, $.heartbeat?.last_beat)' >/dev/null
  grep -q '^HEARTBEAT_INTERVAL=30$' "$SCRIPT" && grep -q '^HEARTBEAT_FRESHNESS=90$' "$SCRIPT"
  ! grep -Eq '(^|[[:space:]])sleep([[:space:]]|$)' "$HARNESS"
  rm -rf "$dir"
}

case_atomic_runtime_records() {
  local dir result label="$1" handoff setup_label setup_report
  dir="$(new_work_dir)"; result="$(run_harness "$dir" "$label" claude done)"
  check_harness_positive_and_negative "$result" 2 done
  ! find "$dir" -maxdepth 1 \( -name '*.tmp.*' -o -name '*report.candidate*' -o -name '*owner.lock*' \) -print -quit | grep -q .
  rm -rf "$dir"

  dir="$(new_work_dir)"; setup_label="$label-setup-failure"; printf 'prompt\n' > "$dir/prompt.md"
  handoff="$(mktemp -d "$(cd "${TMPDIR:-/tmp}" && pwd)/agent-delegate-heartbeat-handoff.XXXXXX")"; chmod 700 "$handoff"
  AGENT_DELEGATE_TEST_MODE=heartbeat AGENT_DELEGATE_TEST_HANDOFF_DIR="$handoff" AGENT_DELEGATE_TEST_FAIL_STAGE=fifo_monitor_to_launcher \
    bash "$SCRIPT" --mode delegate --prompt-file "$dir/prompt.md" --out-dir "$dir" --label "$setup_label" --target claude --detach \
      > "$dir/launch.out" 2> "$dir/launch.err"
  setup_report="$(tail -1 "$dir/launch.out")"
  json_file "$setup_report" -e 'eq(d?.status, "blocked") && eq(d?.blocker_category, "env_error")' >/dev/null
  json_file "$dir/$setup_label-handoff-sentinel-final.json" -e 'eq(d?.state, "setup_failed") && eq(d?.failure_stage, "fifo_monitor_to_launcher") && eq(d?.created_fifos, ["launcher-to-monitor.fifo"])' >/dev/null
  [ ! -d "$handoff" ] && [ ! -e "$dir/$setup_label-owner.json" ] && [ ! -e "$dir/$setup_label.pid" ] &&
    [ ! -e "$dir/$setup_label-heartbeat.json" ]
  ! find "$dir" -maxdepth 1 \( -name '*.tmp.*' -o -name '*report.candidate*' -o -name '*owner.lock*' \) -print -quit | grep -q .
  rm -rf "$dir"
}

case_terminal_done_retention() {
  local dir result label="$1" heartbeat before after
  dir="$(new_work_dir)"; result="$(run_harness "$dir" "$label" claude done)"
  check_harness_positive_and_negative "$result" 2 done
  heartbeat="$(json_file "$result" -r 'd?.heartbeat_path')"; before="$(sha256_file "$heartbeat")"
  json_file "$heartbeat" -e 'eq(d?.state, "done")' >/dev/null; after="$(sha256_file "$heartbeat")"
  [ "$before" = "$after" ]; rm -rf "$dir"
}

case_terminal_worker_blocked() { run_basic_harness_case "$1" blocked blocked 2; }
case_worker_death_synthesis() {
  local dir result report
  dir="$(new_work_dir)"; result="$(run_harness "$dir" "$1" claude worker-death)"
  check_harness_positive_and_negative "$result" 2 blocked
  report="$(json_file "$result" -r 'd?.report_path')"; json_file "$report" -e 'eq(d?.blocker_category, "env_error")' >/dev/null
  rm -rf "$dir"
}

case_invalid_terminal_report() {
  local scenario dir result
  for scenario in invalid-json invalid-status wrong-run; do
    dir="$(new_work_dir)"; result="$(run_harness "$dir" "$1-$scenario" claude "$scenario")"
    check_harness_positive_and_negative "$result" 2 blocked
    json_file "$(json_file "$result" -r 'd?.report_path')" -e 'eq(d?.blocker_category, "env_error")' >/dev/null
    rm -rf "$dir"
  done
}

case_caller_state_machine() {
  local bad
  check_state_fixture "$FIXTURE_DIR/caller-states.tsv" || die "state fixture rejected"
  check_missing_heartbeat_contract_docs || die "public missing-heartbeat state contract is incomplete"
  bad="$(mktemp "${TMPDIR:-/tmp}/agent-delegate-states.XXXXXX")"
  corrupt_fixture_expectation "$FIXTURE_DIR/caller-states.tsv" starting-monitor-unknown \
    DEGRADED_NO_HEARTBEAT "$bad"
  if check_state_fixture "$bad"; then rm -f "$bad"; die "state checker accepted a corrupted unknown-monitor STARTING expectation"; fi
  corrupt_fixture_expectation "$FIXTURE_DIR/caller-states.tsv" no-heartbeat-monitor-unknown \
    STARTING "$bad"
  if check_state_fixture "$bad"; then rm -f "$bad"; die "state checker accepted a corrupted unknown-monitor DEGRADED_NO_HEARTBEAT expectation"; fi
  corrupt_fixture_expectation "$FIXTURE_DIR/caller-states.tsv" starting-owner-worker-alive \
    DEGRADED_NO_HEARTBEAT "$bad"
  if check_state_fixture "$bad"; then rm -f "$bad"; die "state checker accepted a corrupted owner-worker STARTING expectation"; fi
  corrupt_fixture_expectation "$FIXTURE_DIR/caller-states.tsv" no-heartbeat-owner-worker-unknown-monitor-unknown \
    STARTING "$bad"
  if check_state_fixture "$bad"; then rm -f "$bad"; die "state checker accepted a corrupted owner-worker DEGRADED_NO_HEARTBEAT expectation"; fi
  corrupt_fixture_expectation "$FIXTURE_DIR/caller-states.tsv" invalid-both-absent-dead \
    REPORT_INVALID_PENDING "$bad"
  if check_state_fixture "$bad"; then rm -f "$bad"; die "state checker accepted a corrupted expectation"; fi
  rm -f "$bad"
}

case_caller_initial_heartbeat_death() {
  local fixture="$FIXTURE_DIR/caller-initial-heartbeat.tsv" bad dir result owner bad_owner
  check_state_fixture "$fixture" || die "initial heartbeat state fixture rejected"
  bad="$(mktemp "${TMPDIR:-/tmp}/agent-delegate-initial-heartbeat.XXXXXX")"
  corrupt_fixture_expectation "$fixture" worker-pid-unpublished-confirmed DEGRADED_NO_HEARTBEAT "$bad"
  if check_state_fixture "$bad"; then
    rm -f "$bad"
    die "initial heartbeat checker accepted an unbounded missing-worker state"
  fi
  rm -f "$bad"

  dir="$(new_work_dir)"
  result="$(run_harness "$dir" initial-heartbeat claude monitor-kill-before-heartbeat)"
  owner="$(json_file "$result" -r 'd?.owner_snapshot')"
  json_file "$result" -e --argjson owner "$(cat "$owner")" 'eq(d?.scenario, "monitor-kill-before-heartbeat") && eq(d?.monitor_alive, false) && eq(d?.worker_alive_before_cleanup, true) && eq(d?.heartbeat_absent, true) && eq(d?.run_id, $.owner?.run_id) && eq(d?.monitor_pid, $.owner?.monitor_pid) && eq(d?.worker_pid, $.owner?.worker_pid)' >/dev/null || die "initial heartbeat runtime evidence rejected"
  [ ! -e "$(json_file "$result" -r 'd?.heartbeat_path')" ] || die "initial heartbeat was published before injected monitor death"
  bad_owner="$dir/initial-heartbeat-owner.negative.json"
  json_file "$owner" '({...d, worker_pid: d?.worker_pid + 1})' > "$bad_owner"
  if json_file "$result" -e --argjson owner "$(cat "$bad_owner")" 'eq(d?.run_id, $.owner?.run_id) && eq(d?.monitor_pid, $.owner?.monitor_pid) && eq(d?.worker_pid, $.owner?.worker_pid)' >/dev/null; then
    rm -rf "$dir"
    die "initial heartbeat runtime checker accepted a corrupted owner worker PID"
  fi
  rm -rf "$dir"
}

case_caller_state_priority() {
  local fixture="$FIXTURE_DIR/caller-priority.tsv" bad
  check_state_fixture "$fixture" || die "caller priority fixture rejected"
  bad="$(mktemp "${TMPDIR:-/tmp}/agent-delegate-priority.XXXXXX")"
  corrupt_fixture_expectation "$fixture" process-before-invalid-confirmed REPORT_INVALID_PENDING "$bad"
  if check_state_fixture "$bad"; then
    rm -f "$bad"
    die "caller priority checker accepted invalid-report priority over process death"
  fi
  rm -f "$bad"
}

case_caller_wait_upper_bound() {
  local fixture="$FIXTURE_DIR/caller-wait-bounds.tsv" bad
  check_wait_fixture "$fixture" || die "caller wait-bound fixture rejected"
  bad="$(mktemp "${TMPDIR:-/tmp}/agent-delegate-wait-bound.XXXXXX")"
  corrupt_fixture_expectation "$fixture" hard-limit-live-monitor WAIT "$bad"
  if check_wait_fixture "$bad"; then
    rm -f "$bad"
    die "wait-bound checker accepted an unbounded live monitor"
  fi
  rm -f "$bad"
  check_wait_contract_docs || die "public wait-bound contract is incomplete"
  run_detach_review_lifecycle_stub monitor-termination ||
    die "TERM did not produce a blocked terminal report and process cleanup"
}

case_artifact_recovery_contract() {
  local fixture="$FIXTURE_DIR/artifact-recovery.tsv" docs_fixture="$FIXTURE_DIR/artifact-recovery-docs.tsv" bad bad_docs
  check_artifact_recovery_fixture "$fixture" || die "artifact recovery fixture rejected"
  check_artifact_recovery_docs "$docs_fixture" || die "public artifact recovery contract is incomplete"
  bad="$(mktemp "${TMPDIR:-/tmp}/agent-delegate-artifact-recovery.XXXXXX")"
  corrupt_fixture_expectation "$fixture" review-stale-artifact ACCEPT_RECOVERY "$bad"
  if check_artifact_recovery_fixture "$bad"; then
    rm -f "$bad"
    die "artifact recovery checker accepted a stale review artifact"
  fi
  corrupt_fixture_expectation "$fixture" delegate-no-validator ACCEPT_RECOVERY "$bad"
  if check_artifact_recovery_fixture "$bad"; then
    rm -f "$bad"
    die "artifact recovery checker accepted a delegate without a task validator"
  fi
  rm -f "$bad"
  bad_docs="$(mktemp "${TMPDIR:-/tmp}/agent-delegate-artifact-recovery-docs.XXXXXX")"
  awk 'BEGIN{FS=OFS="\t"} $1=="contract-en"{$4="__missing_recovery_requirement__"} {print}' \
    "$docs_fixture" > "$bad_docs"
  if check_artifact_recovery_docs "$bad_docs"; then
    rm -f "$bad_docs"
    die "artifact recovery docs checker accepted a corrupted requirement"
  fi
  rm -f "$bad_docs"
}

case_run_ownership_force_resume() {
  local bad dir rc barrier old_pid deadline old_run new_run prior_run resumed_run raw old_handoff new_handoff metadata
  check_ownership_fixture "$FIXTURE_DIR/ownership-cases.tsv" || die "ownership fixture rejected"
  bad="$(mktemp "${TMPDIR:-/tmp}/agent-delegate-ownership.XXXXXX")"
  awk 'BEGIN{FS=OFS="\t"} NR==2{$NF="retain"} {print}' "$FIXTURE_DIR/ownership-cases.tsv" > "$bad"
  if check_ownership_fixture "$bad"; then rm -f "$bad"; die "ownership checker accepted a corrupted expectation"; fi
  rm -f "$bad"
  check_live_stale_reaper_fixture "$FIXTURE_DIR/stale-reaper-live-cases.tsv" "$1" ||
    die "production stale reaper filesystem fixture rejected"
  dir="$(new_work_dir)"; printf 'prompt\n' > "$dir/prompt.md"
  set +e
  AGENT_DELEGATE_TEST_LSTAT_METADATA='{"type":"directory"}' PATH="$STUB_DIR:$PATH" \
    bash "$SCRIPT" --mode delegate --prompt-file "$dir/prompt.md" --out-dir "$dir" --label injection \
      --target claude --detach > "$dir/out" 2> "$dir/err"
  rc=$?; set -e
  [ "$rc" -eq 2 ] && [ ! -e "$dir/injection-owner.json" ] && [ ! -e "$dir/injection.pid" ] &&
    [ ! -e "$dir/injection-report.json" ] && [ ! -e "$dir/injection-heartbeat.json" ]
  rm -rf "$dir"

  dir="$(new_work_dir)"; barrier="$dir/barrier"; mkdir "$barrier"; mkfifo "$barrier/release.fifo"
  printf 'old run\n' > "$dir/forced-prompt.md"
  PATH="$STUB_DIR:$PATH" AGENT_DELEGATE_STUB_BARRIER_DIR="$barrier" bash "$SCRIPT" --mode delegate \
    --prompt-file "$dir/forced-prompt.md" --out-dir "$dir" --label forced --target claude --sandbox workspace-write \
    > "$dir/forced-old.out" 2> "$dir/forced-old.err" &
  old_pid=$!; deadline=$(( $(date -u +%s) + 10 ))
  while [ "$(date -u +%s)" -lt "$deadline" ]; do
    [ -f "$barrier/claude.ready" ] && [ -f "$dir/forced-owner.json" ] && break
    kill -0 "$old_pid" >/dev/null 2>&1 || break
  done
  [ -f "$dir/forced-owner.json" ] || { kill "$old_pid" 2>/dev/null || true; die "force fixture old owner missing"; }
  old_run="$(json_file "$dir/forced-owner.json" -r 'd?.run_id')"
  run_sync "$dir" forced claude delegate done --force
  new_run="$(json_file "$dir/forced-report.json" -r 'd?.meta?.run_id')"; [ "$new_run" != "$old_run" ]
  printf 'release\n' > "$barrier/release.fifo" || true
  wait "$old_pid" 2>/dev/null || true
  json_file "$dir/forced-report.json" -e --arg run "$new_run" 'eq(d?.meta?.run_id, $.run)' >/dev/null
  [ ! -e "$dir/forced-owner.json" ] && [ ! -e "$dir/forced.pid" ] && [ ! -e "$dir/forced-heartbeat.json" ]

  run_sync "$dir" resumed claude delegate done
  prior_run="$(json_file "$dir/resumed-report.json" -r 'd?.meta?.run_id')"
  run_sync "$dir" resumed claude delegate done '--resume stub-claude-session'
  resumed_run="$(json_file "$dir/resumed-report.json" -r 'd?.meta?.run_id')"
  [ "$prior_run" != "$resumed_run" ]
  json_file "$dir/resumed-report.json" -e --arg run "$resumed_run" 'eq(d?.meta?.run_id, $.run) && eq(d?.meta?.resumed, true) && eq(d?.thread_id, "stub-claude-session")' >/dev/null
  rm -rf "$dir"

  raw="$(new_work_dir)"; mkdir -p "$raw/force" "$raw/resume"
  for dir in "$raw/force" "$raw/resume"; do
    if [ "$(basename "$dir")" = force ]; then new_run=force-new; old_run=force-old; else new_run=resume-new; old_run=resume-old; fi
    json_tool -n --arg run "$old_run" '({meta:{run_id:$.run},completed_after_owner_switch:true})' > "$dir/old-delayed-writer.json"
    json_tool -n --arg run "$new_run" '({status:"done",meta:{run_id:$.run}})' > "$dir/report.json"
    json_tool -n --arg run "$new_run" '({run_id:$.run,state:"done"})' > "$dir/heartbeat.json"
    json_tool -n --arg run "$new_run" '({run_id:$.run,run_kind:"detach"})' > "$dir/owner.json"
    printf 'pid: 999999\nrun_id: %s\n' "$new_run" > "$dir/pid"
    check_shared_run_files "$dir" "$new_run" || die "shared run files rejected: $dir"
    json_file "$dir/heartbeat.json" '({...d, run_id: "corrupted"})' > "$dir/heartbeat.bad"; mv "$dir/heartbeat.bad" "$dir/heartbeat.json"
    if check_shared_run_files "$dir" "$new_run"; then die "shared run checker accepted corrupted heartbeat"; fi
  done
  rm -rf "$raw"

  dir="$(new_work_dir)"; printf 'prompt\n' > "$dir/prompt.md"
  old_handoff="$(cd "${TMPDIR:-/tmp}" && pwd)/agent-delegate-handoff.101.wronguid"; new_handoff="$(mktemp -d "$(cd "${TMPDIR:-/tmp}" && pwd)/agent-delegate-heartbeat-handoff.XXXXXX")"
  rm -rf "$old_handoff"; mkdir -m 700 "$old_handoff"; mkfifo "$old_handoff/launcher-to-monitor.fifo"
  json_tool -n --arg handoff "$old_handoff" '({run_id:"old-run",run_kind:"detach",runner_pid:999999,launcher_pid:101,
    monitor_pid:999999,worker_pid:null,started_at:"2000-01-01T00:00:00Z",lease_at:"2000-01-01T00:00:00Z",
    handoff_dir:$.handoff,handoff_phase:"not_started"})' > "$dir/wronguid-owner.json"
  printf 'pid: 999999\nrun_id: old-run\n' > "$dir/wronguid.pid"
  metadata="$(json_tool -nc --argjson uid "$(( $(id -u) + 1 ))" --argjson dev "$(stat -c %d "$old_handoff" 2>/dev/null || stat -f %d "$old_handoff")" \
    --argjson ino "$(stat -c %i "$old_handoff" 2>/dev/null || stat -f %i "$old_handoff")" \
    '({source:"heartbeat_test_injection",type:"directory",symlink:false,uid:$.uid,mode:700,device:$.dev,inode:$.ino})')"
  set +e
  AGENT_DELEGATE_TEST_MODE=heartbeat AGENT_DELEGATE_TEST_HANDOFF_DIR="$new_handoff" AGENT_DELEGATE_TEST_LSTAT_METADATA="$metadata" \
    bash "$SCRIPT" --mode delegate --prompt-file "$dir/prompt.md" --out-dir "$dir" --label wronguid --target claude --detach \
      > "$dir/wronguid.out" 2> "$dir/wronguid.err"
  rc=$?; set -e
  [ "$rc" -eq 2 ] && [ -d "$old_handoff" ] && [ -p "$old_handoff/launcher-to-monitor.fifo" ] &&
    [ -f "$dir/wronguid-owner.json" ] && [ -f "$dir/wronguid.pid" ] && [ ! -e "$dir/wronguid-heartbeat.json" ] && [ ! -e "$dir/wronguid-report.json" ]
  rm -f "$old_handoff/launcher-to-monitor.fifo"; rmdir "$old_handoff"; rmdir "$new_handoff"; rm -rf "$dir"
}

case_heartbeat_testmode_both_directions() {
  local dir result target rc
  for target in claude codex; do
    dir="$(new_work_dir)"; result="$(run_harness "$dir" "$1-$target" "$target" done)"
    check_harness_positive_and_negative "$result" 2 done
    json_file "$result" -e --arg target "$target" 'eq(d?.target, $.target) && (((eq($.target, "claude") && eq(d?.direction, "codex->claude")) || (eq($.target, "codex") && eq(d?.direction, "claude->codex"))))' >/dev/null
    rm -rf "$dir"
  done
  dir="$(new_work_dir)"; printf 'prompt\n' > "$dir/prompt.md"
  set +e; AGENT_DELEGATE_TEST_MODE=heartbeat bash "$SCRIPT" --mode delegate --prompt-file "$dir/prompt.md" --out-dir "$dir" --label sync --target claude >/dev/null 2>&1; rc=$?; set -e
  [ "$rc" -eq 2 ] && [ ! -e "$dir/sync-owner.json" ] && [ ! -e "$dir/sync-heartbeat.json" ]
  ! find "$dir" -maxdepth 1 -name 'sync-report.candidate.*.json' -print -quit | grep -q .
  AGENT_DELEGATE_TEST_MODE=1 bash "$SCRIPT" --mode delegate --prompt-file "$dir/prompt.md" --out-dir "$dir" --label plan --target claude | grep -q '^TESTMODE '
  [ ! -e "$dir/plan-owner.json" ]; rm -rf "$dir"
}

document_contract_targets() {
  # README files omit heartbeat-interval because they define neither the heartbeat interval nor its freshness contract; including it would accidentally match unrelated 30-second and 90-second contracts.
  cat <<'EOF'
T-A13	en	README.md	write-delegate,polling,reevaluation,hard-stop,termination-grace,automatic-force
T-A13	ja	README.ja.md	write-delegate,polling,reevaluation,hard-stop,termination-grace,automatic-force
T-A11	en	skills/agent-delegate/SKILL.md	write-delegate
T-A12	en	skills/agent-delegate/references/contract.md	sync-scope,polling,reevaluation,hard-stop,termination-grace,automatic-force,heartbeat-interval
T-A12	ja	skills/agent-delegate/references/contract.ja.md	sync-scope,polling,reevaluation,hard-stop,termination-grace,automatic-force,heartbeat-interval
T-A13	en	skills/spec-orchestrate/SKILL.md	watchdog
T-A12	en	skills/spec-orchestrate/references/role-dispatch.md	sync-scope,polling,reevaluation,hard-stop,termination-grace,automatic-force
T-A12	ja	skills/spec-orchestrate/references/role-dispatch.ja.md	sync-scope,polling,reevaluation,hard-stop,termination-grace,automatic-force
T-A11	en	skills/spec-orchestrate/references/phases/spec_generate.md	write-delegate
T-A11	ja	skills/spec-orchestrate/references/phases/spec_generate.ja.md	write-delegate
T-A12	en	skills/spec-orchestrate/references/phases/spec_review.md	write-delegate
T-A12	ja	skills/spec-orchestrate/references/phases/spec_review.ja.md	write-delegate
T-A11	en	skills/spec-orchestrate/references/phases/evaluate.md	write-delegate
T-A11	ja	skills/spec-orchestrate/references/phases/evaluate.ja.md	write-delegate
T-A13	en	skills/spec-orchestrate/references/phases/intake.md	runtime-records
T-A13	ja	skills/spec-orchestrate/references/phases/intake.ja.md	runtime-records
T-A13	en	skills/spec-orchestrate/references/pipeline-config.md	runtime-record-files
T-A13	ja	skills/spec-orchestrate/references/pipeline-config.ja.md	runtime-record-files
T-A11	en	skills/spec-implement/SKILL.md	write-delegate
T-A11	en	skills/spec-implement/references/implement-guide.md	write-delegate
T-A11	ja	skills/spec-implement/references/implement-guide.ja.md	write-delegate
T-A11	en	skills/spec-evaluate/SKILL.md	write-delegate
T-A11	en	skills/spec-evaluate/references/execution-backend.md	write-delegate
T-A11	ja	skills/spec-evaluate/references/execution-backend.ja.md	write-delegate
EOF
}

contract_fixture_row() {
  local file="$1" wanted="$2"
  awk -F '\t' -v wanted="$wanted" '
    NR>1 && $1==wanted {print; count++}
    END {if (count != 1) exit 1}
  ' "$file"
}

check_contract_fixture() {
  local file="$1"
  awk -F '\t' '
    NR==1 {
      if ($0 != "contract_id\tenglish_token\tjapanese_token\tenglish_expected\tjapanese_expected") exit 1
      next
    }
    NF!=5 || $1=="" || $2=="" || $3=="" || $4=="" || $5=="" ||
      $4~/^[0-9]+$/ || $5~/^[0-9]+$/ || seen[$1]++ {exit 1}
    {count++}
    END {if (count==0) exit 1}
  ' "$file"
}

check_document_contract_targets() {
  local fixture="$1" wanted_test="$2" test_id language relative ids row id
  local en ja en_expected ja_expected token expected expected_count count=0
  document_contract_targets | awk -F '\t' '
    NF!=4 || ($1!="T-A11" && $1!="T-A12" && $1!="T-A13") || ($2!="en" && $2!="ja") || seen[$3]++ {exit 1}
    END {if (NR!=24) exit 1}
  ' || return 1
  case "$wanted_test" in
    T-A11) expected_count=11 ;;
    T-A12) expected_count=6 ;;
    T-A13) expected_count=7 ;;
    *) return 1 ;;
  esac
  while IFS=$'\t' read -r test_id language relative ids; do
    [ "$test_id" = "$wanted_test" ] || continue
    count=$((count + 1))
    [ -f "$REPO_ROOT/$relative" ] || return 1
    while [ -n "$ids" ]; do
      case "$ids" in *,*) id="${ids%%,*}"; ids="${ids#*,}" ;; *) id="$ids"; ids="" ;; esac
      row="$(contract_fixture_row "$fixture" "$id")" || return 1
      IFS=$'\t' read -r id en ja en_expected ja_expected <<EOF
$row
EOF
      if [ "$language" = en ]; then
        token="$en"; expected="$en_expected"
      else
        token="$ja"; expected="$ja_expected"
      fi
      check_contract_section "$REPO_ROOT/$relative" "$token" "$expected" || return 1
    done
  done < <(document_contract_targets)
  [ "$count" -eq "$expected_count" ]
}

check_contract_section() {
  local file="$1" token="$2" expected="$3"
  awk -v token="$token" -v expected="$expected" '
    function matches(section) {
      gsub(/[[:space:]]+/, " ", section)
      return index(section, token) && index(section, expected)
    }
    function marker_length(line, marker, count) {
      count=0
      while (substr(line, count + 1, 1) == marker) count++
      return count
    }
    function opening_fence_indent_ok(line, i, char, spaces) {
      spaces=0
      for (i=1; i<=length(line); i++) {
        char=substr(line, i, 1)
        if (char == " ") {
          spaces++
          if (spaces > 3) return 0
        } else if (char == "\t") {
          return 0
        } else {
          break
        }
      }
      return 1
    }
    {
      opening_indent_ok=opening_fence_indent_ok($0)
      trimmed=$0
      sub(/^[[:space:]]*/, "", trimmed)
      marker=substr(trimmed, 1, 1)
      run_length=0
      if (marker == "`" || marker == "~") run_length=marker_length(trimmed, marker)
      if (in_fence) {
        rest=substr(trimmed, run_length + 1)
        if (marker == fence_marker && run_length >= fence_length && rest ~ /^[[:space:]]*$/) {
          in_fence=0
        }
      } else if (opening_indent_ok && (marker == "`" || marker == "~") && run_length >= 3) {
        in_fence=1
        fence_marker=marker
        fence_length=run_length
      } else if ($0 ~ /^#+[[:space:]]/) {
        if (matches(section)) found=1
        section=""
      }
      section=section " " $0
    }
    END {
      if (matches(section)) found=1
      exit !found
    }
  ' "$file"
}

check_contract_section_fence_regression() {
  local dir positive three_space_positive negative long_closing_negative indented_negative
  local tab_indented_negative candidate
  dir="$(new_work_dir)"
  positive="$dir/fenced-comments.md"
  three_space_positive="$dir/three-space-opening.md"
  negative="$dir/real-heading.md"
  long_closing_negative="$dir/long-closing-fence.md"
  indented_negative="$dir/indented-code-block.md"
  tab_indented_negative="$dir/tab-indented-code-block.md"
  cat > "$positive" <<'EOF'
# Contract
write-delegate
   ```sh
~~~
# This shell comment is not a Markdown heading.
```js
# A fence marker with trailing content does not close the block.
   ````
~~~sh
```
# This shell comment is also not a Markdown heading.
~~~js
# A tilde fence marker with trailing content does not close the block.
~~~~
delegate request
EOF
  cat > "$three_space_positive" <<'EOF'
# Contract
write-delegate
   ```sh
# This shell comment is not a Markdown heading.
   ```
delegate request
EOF
  cat > "$negative" <<'EOF'
# Contract
write-delegate
# Separate contract
delegate request
EOF
  cat > "$long_closing_negative" <<'EOF'
# Contract
write-delegate
```sh
# This shell comment is not a Markdown heading.
````
# Separate contract
delegate request
EOF
  cat > "$indented_negative" <<'EOF'
# Contract
write-delegate
    ```sh
# Separate contract
delegate request
EOF
  printf '# Contract\nwrite-delegate\n\t```sh\n# Separate contract\ndelegate request\n' \
    > "$tab_indented_negative"
  check_contract_section "$positive" write-delegate 'delegate request' || {
    rm -rf "$dir"
    return 1
  }
  check_contract_section "$three_space_positive" write-delegate 'delegate request' || {
    rm -rf "$dir"
    return 1
  }
  for candidate in "$negative" "$long_closing_negative" "$indented_negative" \
    "$tab_indented_negative"; do
    if check_contract_section "$candidate" write-delegate 'delegate request'; then
      rm -rf "$dir"
      return 1
    fi
  done
  rm -rf "$dir"
}

check_ordered_tokens() {
  local file="$1" content token
  shift
  content="$(tr '\n' ' ' < "$file")"
  for token in "$@"; do
    case "$content" in *"$token"*) content="${content#*"$token"}" ;; *) return 1 ;; esac
  done
}

check_runtime_record_order() {
  local relative
  for relative in \
    skills/spec-orchestrate/references/phases/intake.md \
    skills/spec-orchestrate/references/phases/intake.ja.md; do
    check_ordered_tokens "$REPO_ROOT/$relative" \
      '*/*-heartbeat.json' '*/*-owner.json' '*/*-owner.lock/' '*/*-report.candidate.*.json' || return 1
  done
  for relative in \
    skills/spec-orchestrate/references/pipeline-config.md \
    skills/spec-orchestrate/references/pipeline-config.ja.md; do
    check_ordered_tokens "$REPO_ROOT/$relative" \
      '*-heartbeat.json' '*-owner.json' '*-owner.lock/' '*-report.candidate.*.json' || return 1
  done
}

check_intake_gitignore_contract() {
  local file="$1"
  awk '
    /^```/ {
      if (in_fence) {
        if ($0 ~ /^```[[:space:]]*$/) {
          if (candidate && marker && stdout_json && stdout_run_json && stdout_run_jsonl && last_run_txt) valid=1
          in_fence=candidate=0
        }
      } else {
        in_fence=1
        candidate=($0 ~ /^```(gitignore)?[[:space:]]*$/)
        marker=stdout_json=stdout_run_json=stdout_run_jsonl=last_run_txt=0
      }
      next
    }
    in_fence && candidate {
      if ($0 ~ /^# spec-orchestrate run records/) marker=1
      if ($0 == "*/*-stdout.json") stdout_json=1
      if ($0 == "*/*-stdout.*.json") stdout_run_json=1
      if ($0 == "*/*-stdout.*.jsonl") stdout_run_jsonl=1
      if ($0 == "*/*-last.*.txt") last_run_txt=1
    }
    END {exit !valid}
  ' "$file"
}

check_pipeline_run_records_contract() {
  local file="$1" marker="$2"
  awk -v marker="$marker" '
    index($0, marker)==1 {in_section=1; found_section=1}
    in_section && /^##[[:space:]]/ && index($0, marker)!=1 {in_section=0}
    in_section {
      if (index($0, "`*/*-stdout.json`") > 0) stdout_json=1
      if (index($0, "`*/*-stdout.*.json`") > 0) stdout_run_json=1
      if (index($0, "`*/*-stdout.*.jsonl`") > 0) stdout_run_jsonl=1
      if (index($0, "`*/*-last.*.txt`") > 0) last_run_txt=1
    }
    END {exit !(found_section && stdout_json && stdout_run_json && stdout_run_jsonl && last_run_txt)}
  ' "$file"
}

check_improve_yaml_contract() {
  local file="$1"
  awk '
    /^```yaml[[:space:]]*$/ {in_yaml=1; next}
    in_yaml && /^```[[:space:]]*$/ {in_yaml=in_improve=0; next}
    in_yaml && /^improve:[[:space:]]/ {in_improve=1; found_improve=1; next}
    in_improve && /^[[:alnum:]_][[:alnum:]_-]*:[[:space:]]/ {in_improve=0}
    in_improve {
      if ($0 ~ /^[[:space:]]+skills_repo:/) skills_repo_count++
      if ($0 == "  skills_repo: \"~/path/to/agent-skills\"") neutral=1
      if (index($0, "/Users/") || index($0, "sunagakeita") ||
          index($0, "keitasunaga") || index($0, "anyoneanderson") ||
          index($0, "~/Documents/zenchaine/")) forbidden=1
    }
    END {exit !(found_improve && neutral && skills_repo_count==1 && !forbidden)}
  ' "$file"
}

check_runtime_record_and_skills_repo_contract() {
  local root="$1"
  check_intake_gitignore_contract \
    "$root/skills/spec-orchestrate/references/phases/intake.md" || return 1
  check_intake_gitignore_contract \
    "$root/skills/spec-orchestrate/references/phases/intake.ja.md" || return 1
  check_pipeline_run_records_contract \
    "$root/skills/spec-orchestrate/references/pipeline-config.md" '**Run records**' || return 1
  check_pipeline_run_records_contract \
    "$root/skills/spec-orchestrate/references/pipeline-config.ja.md" '**運転記録**' || return 1
  check_improve_yaml_contract \
    "$root/skills/spec-orchestrate/references/pipeline-config.md" || return 1
  check_improve_yaml_contract \
    "$root/skills/spec-orchestrate/references/pipeline-config.ja.md"
}

copy_runtime_record_contract_documents() {
  local root="$1" relative
  for relative in \
    skills/spec-orchestrate/references/phases/intake.md \
    skills/spec-orchestrate/references/phases/intake.ja.md \
    skills/spec-orchestrate/references/pipeline-config.md \
    skills/spec-orchestrate/references/pipeline-config.ja.md; do
    mkdir -p "$root/$(dirname "$relative")"
    cp "$REPO_ROOT/$relative" "$root/$relative"
  done
}

replace_literal_in_file() {
  local file="$1" token="$2" replacement="$3" bad
  bad="$(mktemp "$(cd "${TMPDIR:-/tmp}" && pwd)/agent-delegate-document-mutation.XXXXXX")"
  awk -v token="$token" -v replacement="$replacement" '
    {
      line=$0
      while ((position=index(line, token)) > 0) {
        line=substr(line, 1, position - 1) replacement substr(line, position + length(token))
        changed++
      }
      print line
    }
    END {if (changed==0) exit 1}
  ' "$file" > "$bad" || { rm -f "$bad"; return 1; }
  mv "$bad" "$file"
}

insert_after_exact_line() {
  local file="$1" expected="$2" inserted="$3" bad
  bad="$(mktemp "$(cd "${TMPDIR:-/tmp}" && pwd)/agent-delegate-document-insertion.XXXXXX")"
  awk -v expected="$expected" -v inserted="$inserted" '
    {print}
    $0==expected {print inserted; changed++}
    END {if (changed!=1) exit 1}
  ' "$file" > "$bad" || { rm -f "$bad"; return 1; }
  mv "$bad" "$file"
}

remove_runtime_record_format() {
  local file="$1" relative="$2" token="$3" bad
  case "$relative" in
    */phases/intake*)
      bad="$(mktemp "$(cd "${TMPDIR:-/tmp}" && pwd)/agent-delegate-format-mutation.XXXXXX")"
      awk -v token="$token" '
        $0==token {$0="__missing_runtime_record_format__"; changed++}
        {print}
        END {if (changed!=1) exit 1}
      ' "$file" > "$bad" || { rm -f "$bad"; return 1; }
      mv "$bad" "$file"
      ;;
    */pipeline-config*)
      replace_literal_in_file "$file" "\`$token\`" '`__missing_runtime_record_format__`'
      ;;
    *) return 1 ;;
  esac
}

check_runtime_record_and_skills_repo_mutations() {
  local dir relative token forbidden
  dir="$(new_work_dir)"
  copy_runtime_record_contract_documents "$dir"
  check_runtime_record_and_skills_repo_contract "$dir" || { rm -rf "$dir"; return 1; }

  for relative in \
    skills/spec-orchestrate/references/phases/intake.md \
    skills/spec-orchestrate/references/phases/intake.ja.md \
    skills/spec-orchestrate/references/pipeline-config.md \
    skills/spec-orchestrate/references/pipeline-config.ja.md; do
    for token in \
      '*/*-stdout.json' \
      '*/*-stdout.*.json' \
      '*/*-stdout.*.jsonl' \
      '*/*-last.*.txt'; do
      copy_runtime_record_contract_documents "$dir"
      remove_runtime_record_format "$dir/$relative" "$relative" "$token" || {
        rm -rf "$dir"
        return 1
      }
      if check_runtime_record_and_skills_repo_contract "$dir"; then
        rm -rf "$dir"
        return 1
      fi
      copy_runtime_record_contract_documents "$dir"
      remove_runtime_record_format "$dir/$relative" "$relative" "$token" || {
        rm -rf "$dir"
        return 1
      }
      case "$relative" in
        */phases/intake*) printf '\n%s\n' "$token" >> "$dir/$relative" ;;
        */pipeline-config*) printf '\noutside run records section: `%s`\n' "$token" >> "$dir/$relative" ;;
        *) rm -rf "$dir"; return 1 ;;
      esac
      if check_runtime_record_and_skills_repo_contract "$dir"; then
        rm -rf "$dir"
        return 1
      fi
    done
  done

  for relative in \
    skills/spec-orchestrate/references/pipeline-config.md \
    skills/spec-orchestrate/references/pipeline-config.ja.md; do
    copy_runtime_record_contract_documents "$dir"
    replace_literal_in_file "$dir/$relative" '~/path/to/agent-skills' '~/path/to/not-agent-skills' || {
      rm -rf "$dir"
      return 1
    }
    if check_runtime_record_and_skills_repo_contract "$dir"; then
      rm -rf "$dir"
      return 1
    fi
    copy_runtime_record_contract_documents "$dir"
    replace_literal_in_file "$dir/$relative" '~/path/to/agent-skills' '~/path/to/not-agent-skills' || {
      rm -rf "$dir"
      return 1
    }
    printf '\noutside improve YAML block:\n  skills_repo: "~/path/to/agent-skills"\n' >> "$dir/$relative"
    if check_runtime_record_and_skills_repo_contract "$dir"; then
      rm -rf "$dir"
      return 1
    fi
    for forbidden in \
      '/Users/' \
      'sunagakeita' \
      'keitasunaga' \
      'anyoneanderson' \
      '~/Documents/zenchaine/'; do
      copy_runtime_record_contract_documents "$dir"
      insert_after_exact_line "$dir/$relative" \
        '  skills_repo: "~/path/to/agent-skills"' \
        "  forbidden_mutation: \"$forbidden\"" || {
        rm -rf "$dir"
        return 1
      }
      if check_runtime_record_and_skills_repo_contract "$dir"; then
        rm -rf "$dir"
        return 1
      fi
    done
  done
  rm -rf "$dir"
}

# Extract the fenced block intake tells the agent to write verbatim into .specs/.gitignore.
# The document-text checks above verify the block mentions the required formats; this extraction
# lets the checks below verify what git actually does with the block.
extract_intake_gitignore_block() {
  local file="$1"
  awk '
    /^```/ {
      if (in_fence) {
        if (candidate && marker && $0 ~ /^```[[:space:]]*$/) {printf "%s", buffer; emitted=1; exit}
        in_fence=candidate=marker=0; buffer=""
      } else {
        in_fence=1
        candidate=($0 ~ /^```(gitignore)?[[:space:]]*$/)
        marker=0; buffer=""
      }
      next
    }
    in_fence && candidate {
      if ($0 ~ /^# spec-orchestrate run records/) marker=1
      buffer = buffer $0 "\n"
    }
    END {exit !emitted}
  ' "$file"
}

# Spec artifacts whose commit status pipeline-config.md leaves to the project.
# The run-record .gitignore must never hide them.
gitignore_projection_spec_artifacts() {
  printf '%s\n' \
    '.specs/sample-feature/requirement.md' \
    '.specs/sample-feature/design.md' \
    '.specs/sample-feature/tasks.md' \
    '.specs/sample-feature/test.md'
}

# One representative filename per pattern the block lists. Every one must stay ignored.
gitignore_projection_run_records() {
  printf '%s\n' \
    '.specs/pipeline-metrics.jsonl' \
    '.specs/.orchestrate-active.json' \
    '.specs/sample-feature/pipeline-state.json' \
    '.specs/sample-feature/inspection-report.md' \
    '.specs/sample-feature/.inspection_result.json' \
    '.specs/sample-feature/review-1.md' \
    '.specs/sample-feature/evaluate-1.md' \
    '.specs/sample-feature/evidence/screenshot.png' \
    '.specs/sample-feature/retrospective.md' \
    '.specs/sample-feature/plan-report.json' \
    '.specs/sample-feature/plan-heartbeat.json' \
    '.specs/sample-feature/plan-owner.json' \
    '.specs/sample-feature/plan-owner.lock/held' \
    '.specs/sample-feature/plan-report.candidate.1.json' \
    '.specs/sample-feature/plan-last.txt' \
    '.specs/sample-feature/plan-last.1.txt' \
    '.specs/sample-feature/plan-stdout.json' \
    '.specs/sample-feature/plan-stdout.jsonl' \
    '.specs/sample-feature/plan-stdout.1.json' \
    '.specs/sample-feature/plan-stdout.1.jsonl' \
    '.specs/sample-feature/plan-stderr.log' \
    '.specs/sample-feature/plan.pid'
}

# Project the given block into a throwaway repository as .specs/.gitignore and let git itself
# decide: spec artifacts must show up in git status, run records must not.
# Global and system gitignore files are disabled so the verdict does not depend on the machine.
check_gitignore_projection() {
  local block="$1" dir status relative
  dir="$(new_work_dir)"
  if ! GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
      git -C "$dir" init --quiet >/dev/null 2>&1; then
    rm -rf "$dir"
    return 1
  fi
  mkdir -p "$dir/.specs/sample-feature"
  printf '%s\n' "$block" > "$dir/.specs/.gitignore"
  while IFS= read -r relative; do
    mkdir -p "$dir/$(dirname "$relative")"
    printf 'fixture\n' > "$dir/$relative"
  done < <(gitignore_projection_spec_artifacts; gitignore_projection_run_records)

  status="$(GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    git -C "$dir" status --porcelain --untracked-files=all)" || {
    rm -rf "$dir"
    return 1
  }

  while IFS= read -r relative; do
    if ! printf '%s\n' "$status" | grep -Fxq "?? $relative"; then
      rm -rf "$dir"
      return 1
    fi
  done < <(gitignore_projection_spec_artifacts)

  while IFS= read -r relative; do
    if printf '%s\n' "$status" | grep -Fq "$relative"; then
      rm -rf "$dir"
      return 1
    fi
  done < <(gitignore_projection_run_records)

  rm -rf "$dir"
}

check_gitignore_projection_mutations() {
  local block block_ja mutated
  block="$(extract_intake_gitignore_block \
    "$REPO_ROOT/skills/spec-orchestrate/references/phases/intake.md")" || return 1
  block_ja="$(extract_intake_gitignore_block \
    "$REPO_ROOT/skills/spec-orchestrate/references/phases/intake.ja.md")" || return 1
  # Both languages must dictate the same file; editing one alone changes what a project ignores
  # depending on which document the agent read.
  [ "$block" = "$block_ja" ] || return 1
  check_gitignore_projection "$block" || return 1

  # Over-matching 1: widening a run-record pattern also hides the spec artifacts.
  mutated="$(printf '%s\n' "$block" | awk '{print ($0=="*/review-*.md") ? "*/*.md" : $0}')"
  [ "$mutated" != "$block" ] || return 1
  if check_gitignore_projection "$mutated"; then return 1; fi

  # Over-matching 2: adding a pattern that reaches a spec artifact hides test.md.
  mutated="$(printf '%s\n%s\n' "$block" '*/test*.md')"
  if check_gitignore_projection "$mutated"; then return 1; fi

  # Under-matching: dropping a run-record pattern lets that record reach git status.
  mutated="$(printf '%s\n' "$block" | grep -vFx '*/*-stdout.json')"
  [ "$mutated" != "$block" ] || return 1
  if check_gitignore_projection "$mutated"; then return 1; fi
}

check_document_contracts() {
  local fixture="$1" test_id="$2"
  check_contract_fixture "$fixture" &&
    check_document_contract_targets "$fixture" "$test_id" &&
    { [ "$test_id" != T-A13 ] || check_runtime_record_order; }
}

check_contract_mutation_rejected() {
  local fixture="$1" test_id="$2" mutation_id="$3" language="$4" kind="$5" replacement="$6"
  local field bad
  case "$language:$kind" in
    en:token) field=2 ;;
    ja:token) field=3 ;;
    en:expected) field=4 ;;
    ja:expected) field=5 ;;
    *) return 1 ;;
  esac
  bad="$(mktemp "$(cd "${TMPDIR:-/tmp}" && pwd)/agent-delegate-contract.XXXXXX")"
  awk -v wanted="$mutation_id" -v field="$field" -v replacement="$replacement" '
    BEGIN {FS=OFS="\t"}
    $1==wanted {$field=replacement; changed++}
    {print}
    END {if (changed!=1) exit 1}
  ' "$fixture" > "$bad" || { rm -f "$bad"; return 1; }
  if check_document_contracts "$bad" "$test_id"; then rm -f "$bad"; return 1; fi
  rm -f "$bad"
}

check_contract_positive_and_negative() {
  local test_id="$1" token_id="$2" token_language="$3" time_id="$4" time_language="$5" time_replacement="$6"
  local fixture="$FIXTURE_DIR/document-contract.tsv"
  check_document_contracts "$fixture" "$test_id" || return 1
  check_contract_mutation_rejected "$fixture" "$test_id" "$token_id" "$token_language" token \
    __missing_contract_token__ || return 1
  [ -z "$time_id" ] || check_contract_mutation_rejected "$fixture" "$test_id" "$time_id" \
    "$time_language" expected "$time_replacement"
}
case_write_delegate_docs_use_detach() {
  check_contract_positive_and_negative T-A11 write-delegate en '' '' '' &&
    check_contract_section_fence_regression
}
case_caller_sync_poll_timeout_contract() {
  check_contract_positive_and_negative T-A12 polling en heartbeat-interval en '91 seconds'
}
case_bilingual_contract_and_runtime_records() {
  check_contract_positive_and_negative T-A13 runtime-record-files ja polling ja '31秒' ||
    die 'bilingual document contract fixture or section contract rejected'
  check_runtime_record_and_skills_repo_mutations ||
    die 'runtime record or skills_repo scoped positive and negative checks failed'
  check_gitignore_projection_mutations ||
    die 'gitignore projection hid a spec artifact or exposed a run record'
}

check_compatibility_fixture() {
  local file="$1" id path ref mode target sandbox stub expected_exit expected_status artifact count=0
  while IFS=$'\t' read -r id path ref mode target sandbox stub expected_exit expected_status artifact; do
    [ "$id" = case_id ] && continue
    count=$((count + 1))
    [ -n "$id" ] && [ -n "$ref" ] && [ -n "$artifact" ] || return 1
    case "$expected_exit" in 0|2) : ;; *) return 1 ;; esac
    case "$target" in codex|claude) : ;; *) return 1 ;; esac
    git -C "$REPO_ROOT" cat-file -e "origin/main:$path" 2>/dev/null || return 1
  done < "$file"
  [ "$count" -eq 14 ]
}

process_group_of() {
  ps -o pgid= -p "$1" 2>/dev/null | tr -d '[:space:]'
}

cleanup_detach_stub_fixture() {
  local dir="$1" label="$2" owner="$dir/$label-owner.json" monitor="" worker="" pgid="" own_pgid
  local handoff="" heartbeat="$dir/$label-heartbeat.json"
  if [ -f "$owner" ] && json_file "$owner" -e 'd' >/dev/null 2>&1; then
    monitor="$(json_file "$owner" -r 'alt(d?.monitor_pid, EMPTY)')"
    worker="$(json_file "$owner" -r 'alt(d?.worker_pid, EMPTY)')"
    handoff="$(json_file "$owner" -r 'alt(d?.handoff_dir, EMPTY)')"
  fi
  if [ -z "$monitor" ] && json_file "$heartbeat" -e 'd' >/dev/null 2>&1; then
    monitor="$(json_file "$heartbeat" -r 'alt(d?.monitor_pid, EMPTY)')"
    worker="$(json_file "$heartbeat" -r 'alt(d?.pid, EMPTY)')"
  fi
  own_pgid="$(process_group_of "${BASHPID:-$$}")"
  if [ -n "$monitor" ]; then
    pgid="$(process_group_of "$monitor")"
    if [ -n "$pgid" ] && [ "$pgid" != "$own_pgid" ]; then
      kill -TERM -- "-$pgid" 2>/dev/null || true
    else
      kill -TERM "$monitor" 2>/dev/null || true
      [ -z "$worker" ] || kill -TERM "$worker" 2>/dev/null || true
    fi
  fi
  [ -z "$handoff" ] || rm -rf "$handoff"
  rm -rf "$dir"
}

launch_detach_review_stub() {
  local dir="$1" label="$2" barrier="$3" signal_stage="${4:-}" test_handoff="${5:-}"
  local test_mode_override="${6:-}" term_ready_file="${7:-}" term_release_file="${8:-}"
  local driver driver_pgid monitor_mode=0 test_mode=0 ready_file=""
  if [ -n "$signal_stage" ]; then
    test_mode=owner-lock-signal
    ready_file="$barrier/claude.ready"
  fi
  [ -z "$test_mode_override" ] || test_mode="$test_mode_override"
  case $- in *m*) monitor_mode=1 ;; esac
  set -m
  (
    exec env PATH="$STUB_DIR:$PATH" AGENT_DELEGATE_STUB_BARRIER_DIR="$barrier" \
      AGENT_DELEGATE_STUB_REVIEW=1 AGENT_DELEGATE_TEST_MODE="$test_mode" \
      AGENT_DELEGATE_TEST_HANDOFF_DIR="$test_handoff" \
      AGENT_DELEGATE_TEST_OWNER_LOCK_SIGNAL_STAGE="$signal_stage" \
      AGENT_DELEGATE_TEST_OWNER_LOCK_READY_FILE="$ready_file" \
      AGENT_DELEGATE_TEST_MONITOR_BEFORE_PUBLISH_READY_FILE="$term_ready_file" \
      AGENT_DELEGATE_TEST_MONITOR_BEFORE_PUBLISH_RELEASE_FILE="$term_release_file" \
      bash "$SCRIPT" --mode review --prompt-file "$dir/prompt.md" \
        --out-dir "$dir" --label "$label" --target claude --detach
  ) > "$dir/$label-launch.out" 2> "$dir/$label-launch.err" &
  driver=$!
  driver_pgid="$(process_group_of "$driver")"
  [ "$monitor_mode" -eq 1 ] || set +m
  [ -n "$driver_pgid" ] || return 1
  printf '%s\n' "$driver" > "$dir/$label-launcher-shell.pid"
  printf '%s\n' "$driver_pgid" > "$dir/$label-launcher-shell.pgid"
  wait "$driver"
}

wait_for_detach_stub_runtime() {
  local dir="$1" label="$2" barrier="$3" deadline owner heartbeat
  owner="$dir/$label-owner.json"; heartbeat="$dir/$label-heartbeat.json"
  deadline=$(( $(date -u +%s) + 10 ))
  while [ "$(date -u +%s)" -lt "$deadline" ]; do
    if [ -f "$barrier/claude.ready" ] && [ -f "$owner" ] && [ -f "$heartbeat" ] &&
       json_file "$owner" -e 'eq(d?.handoff_phase, "verified") && eq((type(d?.monitor_pid)), "number") && eq((type(d?.worker_pid)), "number")' >/dev/null 2>&1 &&
       json_file "$heartbeat" -e 'eq(d?.state, "running") && eq((type(d?.pid)), "number") && eq((type(d?.monitor_pid)), "number")' >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

wait_for_detach_stub_terminal() {
  local dir="$1" label="$2" expected="$3" handoff="$4" deadline report heartbeat
  report="$dir/$label-report.json"; heartbeat="$dir/$label-heartbeat.json"
  deadline=$(( $(date -u +%s) + 10 ))
  while [ "$(date -u +%s)" -lt "$deadline" ]; do
    if [ -f "$report" ] && [ -f "$heartbeat" ] &&
       json_file "$report" -e --arg expected "$expected" 'eq(d?.status, $.expected) && eq((type(d?.meta?.run_id)), "string")' >/dev/null 2>&1 &&
       json_file "$heartbeat" -e --arg expected "$expected" --argjson report_run "$(json_file "$report" -c 'd?.meta?.run_id')" \
         'eq(d?.state, $.expected) && eq(d?.run_id, $.report_run)' >/dev/null 2>&1 &&
       [ ! -e "$dir/$label-owner.json" ] && [ ! -e "$dir/$label.pid" ] && [ ! -d "$handoff" ]; then
      return 0
    fi
  done
  return 1
}

run_detach_review_lifecycle_stub() (
  local scenario="$1" dir label barrier owner monitor worker peer monitor_pgid worker_pgid driver_pgid handoff report
  dir="$(new_work_dir)"; label="detach-$scenario"; barrier="$dir/barrier"
  trap 'cleanup_detach_stub_fixture "$dir" "$label"' EXIT TERM INT HUP
  mkdir "$barrier"; mkfifo "$barrier/release.fifo"; printf 'review prompt\n' > "$dir/prompt.md"
  launch_detach_review_stub "$dir" "$label" "$barrier" || return 1
  wait_for_detach_stub_runtime "$dir" "$label" "$barrier" || return 1
  owner="$dir/$label-owner.json"; monitor="$(json_file "$owner" -r 'd?.monitor_pid')"; worker="$(json_file "$owner" -r 'd?.worker_pid')"
  peer="$(cat "$barrier/claude.pid")"
  handoff="$(json_file "$owner" -r 'd?.handoff_dir')"; driver_pgid="$(cat "$dir/$label-launcher-shell.pgid")"
  monitor_pgid="$(process_group_of "$monitor")"; worker_pgid="$(process_group_of "$worker")"
  [ -n "$monitor_pgid" ] && [ "$monitor_pgid" = "$worker_pgid" ] && [ "$monitor_pgid" != "$driver_pgid" ] || return 1

  # Model the process-group cleanup performed by a command runner after the
  # launcher shell exits. The detached monitor group must not be affected.
  kill -TERM -- "-$driver_pgid" 2>/dev/null || true
  kill -0 "$monitor" 2>/dev/null && kill -0 "$worker" 2>/dev/null || return 1

  case "$scenario" in
    survives-launcher-exit)
      printf 'release\n' > "$barrier/release.fifo"
      wait_for_detach_stub_terminal "$dir" "$label" done "$handoff" || return 1
      report="$dir/$label-report.json"
      json_file "$report" -e 'eq(d?.status, "done") && eq(d?.meta?.mode, "review")' >/dev/null || return 1
      [ -f "$dir/$label-review.md" ] || return 1
      ! kill -0 "$peer" 2>/dev/null || return 1
      ;;
    worker-death)
      kill -KILL "$worker" 2>/dev/null || return 1
      wait_for_detach_stub_terminal "$dir" "$label" blocked "$handoff" || return 1
      json_file "$dir/$label-report.json" -e 'eq(d?.blocker_category, "env_error")' >/dev/null || return 1
      ! kill -0 "$peer" 2>/dev/null || return 1
      ;;
    monitor-termination)
      kill -TERM "$monitor" 2>/dev/null || return 1
      wait_for_detach_stub_terminal "$dir" "$label" blocked "$handoff" || return 1
      json_file "$dir/$label-report.json" -e 'eq(d?.blocker_category, "env_error")' >/dev/null || return 1
      ! kill -0 "$peer" 2>/dev/null || return 1
      ;;
    *) return 1 ;;
  esac
  trap - EXIT TERM INT HUP
  rm -rf "$dir"
)

run_monitor_term_review_stub() (
  local case_id="$1" mutation="$2" expected_status="$3" dir label barrier owner monitor worker peer
  local handoff driver_pgid monitor_pgid worker_pgid run candidate review ready release deadline report
  dir="$(new_work_dir)"; label="monitor-term-review-$case_id"; barrier="$dir/barrier"
  ready="$barrier/candidate.ready"; release="$barrier/monitor.release"
  trap 'touch "$release" 2>/dev/null || true; cleanup_detach_stub_fixture "$dir" "$label"' EXIT TERM INT HUP
  mkdir "$barrier"; mkfifo "$barrier/release.fifo"; printf 'review prompt\n' > "$dir/prompt.md"
  launch_detach_review_stub "$dir" "$label" "$barrier" "" "" monitor-term-recovery "$ready" "$release" || return 1
  wait_for_detach_stub_runtime "$dir" "$label" "$barrier" || return 1
  owner="$dir/$label-owner.json"; monitor="$(json_file "$owner" -r 'd?.monitor_pid')"; worker="$(json_file "$owner" -r 'd?.worker_pid')"
  peer="$(cat "$barrier/claude.pid")"; handoff="$(json_file "$owner" -r 'd?.handoff_dir')"
  driver_pgid="$(cat "$dir/$label-launcher-shell.pgid")"; monitor_pgid="$(process_group_of "$monitor")"
  worker_pgid="$(process_group_of "$worker")"; run="$(json_file "$owner" -r 'd?.run_id')"
  candidate="$dir/$label-report.candidate.$run.json"; review="$dir/$label-review.md"
  [ -n "$monitor_pgid" ] && [ "$monitor_pgid" = "$worker_pgid" ] && [ "$monitor_pgid" != "$driver_pgid" ] || return 1
  kill -TERM -- "-$driver_pgid" 2>/dev/null || true
  kill -0 "$monitor" 2>/dev/null && kill -0 "$worker" 2>/dev/null || return 1

  printf 'release\n' > "$barrier/release.fifo"
  deadline=$(( $(date -u +%s) + 10 ))
  while [ "$(date -u +%s)" -lt "$deadline" ]; do
    [ -f "$ready" ] && [ -f "$candidate" ] && [ -f "$review" ] && break
  done
  [ -f "$ready" ] && [ -f "$candidate" ] && [ -f "$review" ] || return 1
  ! kill -0 "$peer" 2>/dev/null || return 1

  case "$mutation" in
    none) : ;;
    missing-review) rm -f "$review" ;;
    malformed-review) printf 'type: review\n## Findings\n' > "$review" ;;
    wrong-run)
      json_file "$candidate" '({...d, meta: {...d?.meta, run_id: "stale-run"}})' > "$candidate.tmp" && mv -f "$candidate.tmp" "$candidate"
      ;;
    *) return 1 ;;
  esac
  kill -TERM "$monitor" 2>/dev/null || return 1
  wait_for_detach_stub_terminal "$dir" "$label" "$expected_status" "$handoff" || return 1
  report="$dir/$label-report.json"
  if [ "$expected_status" = done ]; then
    json_file "$report" -e --arg run "$run" --arg review "$review" \
      'eq(d?.status, "done") && eq(d?.blocker, null) && eq(d?.blocker_category, null) && eq(d?.meta?.run_id, $.run) && eq(d?.meta?.mode, "review") && eq(d?.touchedFiles, []) && eq(d?.artifacts?.review_file, $.review)' >/dev/null || return 1
    grep -q '^type: review' "$review" && grep -q '^## Meta' "$review" &&
      grep -q '^## Findings' "$review" && grep -qE 'Gate:[[:space:]]*(PASS|FAIL)' "$review" || return 1
  else
    json_file "$report" -e --arg run "$run" \
      'eq(d?.status, "blocked") && eq(d.blocker_category, "env_error") &&
       eq(d.meta?.run_id, $.run) && type(d.blocker)==="string" && d.blocker.includes("TERM")' >/dev/null || return 1
  fi
  [ ! -e "$candidate" ] && [ ! -e "$candidate.tmp" ] || return 1
  trap - EXIT TERM INT HUP
  rm -rf "$dir"
)

check_monitor_term_review_fixture() {
  local file="$1" case_id mutation expected_status count=0
  while IFS=$'\t' read -r case_id mutation expected_status; do
    [ "$case_id" = case_id ] && continue
    count=$((count + 1))
    case "$mutation" in none|missing-review|malformed-review|wrong-run) : ;; *) return 1 ;; esac
    case "$expected_status" in done|blocked) : ;; *) return 1 ;; esac
    run_monitor_term_review_stub "$case_id" "$mutation" "$expected_status" || return 1
  done < "$file"
  [ "$count" -eq 4 ]
}

case_monitor_term_review_recovery() {
  check_monitor_term_review_fixture "$FIXTURE_DIR/monitor-term-review-cases.tsv" ||
    die "monitor TERM review recovery fixture rejected"
  grep -Fq 'review candidate to `done` only when the candidate belongs to the expected' \
    "$REPO_ROOT/skills/agent-delegate/references/contract.md" ||
    die "English monitor TERM recovery contract is missing"
  grep -Fq '未公開の review candidate を `done` として採用できるのは' \
    "$REPO_ROOT/skills/agent-delegate/references/contract.ja.md" ||
    die "Japanese monitor TERM recovery contract is missing"
}

check_owner_lock_signal_artifacts() {
  local report="$1" heartbeat="$2" dir="$3" label="$4" handoff="$5" expected_status="$6"
  [ -f "$report" ] && [ -f "$heartbeat" ] || return 1
  json_file "$report" -e --arg status "$expected_status" '
    eq(d?.status, $.status) && type(d.meta?.run_id)==="string" && len(d.meta.run_id)>0 &&
    eq(d.blocker_category, "env_error") && type(d.blocker)==="string" && d.blocker.includes("TERM")
  ' >/dev/null || return 1
  json_file "$heartbeat" -e --arg status "$expected_status" --argjson report_run "$(json_file "$report" -c 'd?.meta?.run_id')" 'eq(d?.state, $.status) && eq(d?.run_id, $.report_run) && eq((type(d?.pid)), "number") && eq((type(d?.monitor_pid)), "number")' >/dev/null || return 1
  [ ! -e "$dir/$label-owner.json" ] && [ ! -e "$dir/$label.pid" ] &&
    [ ! -e "$dir/$label-owner.lock" ] && [ ! -d "$handoff" ] || return 1
  ! find "$dir" -maxdepth 1 \( -name "$label-report.candidate.*" -o -name "$label-report.json.tmp.*" \
    -o -name "$label-heartbeat.json.tmp.*" -o -name "$label-owner.json.tmp.*" \) -print -quit | grep -q .
}

run_owner_lock_signal_stub() (
  local case_id="$1" signal_stage="$2" expected_status="$3" dir label barrier handoff report heartbeat bad_heartbeat
  local monitor peer deadline
  dir="$(new_work_dir)"; label="owner-lock-signal-$case_id"; barrier="$dir/barrier"
  handoff="$(mktemp -d "$(cd "${TMPDIR:-/tmp}" && pwd)/agent-delegate-owner-lock-signal-handoff.XXXXXX")"
  chmod 700 "$handoff"
  trap 'cleanup_detach_stub_fixture "$dir" "$label"; rm -rf "$handoff"' EXIT TERM INT HUP
  mkdir "$barrier"; mkfifo "$barrier/release.fifo"; printf 'review prompt\n' > "$dir/prompt.md"
  launch_detach_review_stub "$dir" "$label" "$barrier" "$signal_stage" "$handoff" || return 1
  report="$dir/$label-report.json"; heartbeat="$dir/$label-heartbeat.json"
  deadline=$(( $(date -u +%s) + 10 ))
  while [ "$(date -u +%s)" -lt "$deadline" ]; do
    if check_owner_lock_signal_artifacts "$report" "$heartbeat" "$dir" "$label" "$handoff" "$expected_status"; then
      monitor="$(json_file "$heartbeat" -r 'd?.monitor_pid')"
      peer="$(cat "$barrier/claude.pid" 2>/dev/null || true)"
      if ! kill -0 "$monitor" 2>/dev/null && { [ -z "$peer" ] || ! kill -0 "$peer" 2>/dev/null; }; then break; fi
    fi
  done
  check_owner_lock_signal_artifacts "$report" "$heartbeat" "$dir" "$label" "$handoff" "$expected_status" || return 1
  monitor="$(json_file "$heartbeat" -r 'd?.monitor_pid')"; ! kill -0 "$monitor" 2>/dev/null || return 1
  peer="$(cat "$barrier/claude.pid" 2>/dev/null || true)"; [ -z "$peer" ] || ! kill -0 "$peer" 2>/dev/null || return 1

  bad_heartbeat="$dir/$label-heartbeat.negative.json"
  json_file "$heartbeat" '({...d, run_id: "corrupted-run"})' > "$bad_heartbeat"
  if check_owner_lock_signal_artifacts "$report" "$bad_heartbeat" "$dir" "$label" "$handoff" "$expected_status"; then
    return 1
  fi
  rm -f "$bad_heartbeat"
  trap - EXIT TERM INT HUP
  rm -rf "$dir"
)

check_owner_lock_signal_fixture() {
  local file="$1" case_id signal_stage expected_status
  while IFS=$'\t' read -r case_id signal_stage expected_status; do
    [ "$case_id" = case_id ] && continue
    run_owner_lock_signal_stub "$case_id" "$signal_stage" "$expected_status" || return 1
  done < "$file"
}

case_clean_checkout_compatibility() {
  local dir rc worktree_parent worktree runner_rel deadline detach_report bad_fixture
  runner_rel="skills/agent-delegate/references/scripts/tests/run_tests.sh"
  if [ "${AGENT_DELEGATE_IN_CLEAN_CHECKOUT:-0}" != 1 ] && git -C "$REPO_ROOT" cat-file -e "HEAD:$runner_rel" 2>/dev/null; then
    worktree_parent="$(new_work_dir)"; worktree="$worktree_parent/worktree"
    git -C "$REPO_ROOT" worktree add --detach "$worktree" HEAD >/dev/null
    set +e
    (cd "$worktree" && AGENT_DELEGATE_IN_CLEAN_CHECKOUT=1 bash "$runner_rel" --case clean-checkout-compatibility)
    rc=$?
    set -e
    git -C "$REPO_ROOT" worktree remove --force "$worktree" >/dev/null 2>&1 || true
    rm -rf "$worktree_parent"
    [ "$rc" -eq 0 ] || return "$rc"
    return 0
  fi
  check_compatibility_fixture "$FIXTURE_DIR/compatibility-cases.tsv" || die "compatibility fixture rejected"
  bad_fixture="$(mktemp "$(cd "${TMPDIR:-/tmp}" && pwd)/agent-delegate-compatibility.XXXXXX")"
  awk 'BEGIN{FS=OFS="\t"} NR==2{$2="missing-contract.md"} {print}' "$FIXTURE_DIR/compatibility-cases.tsv" > "$bad_fixture"
  if check_compatibility_fixture "$bad_fixture"; then rm -f "$bad_fixture"; die "compatibility checker accepted missing origin/main contract"; fi
  rm -f "$bad_fixture"
  dir="$(new_work_dir)"
  bash "$SCRIPT" --help | grep -q 'Usage:'
  set +e; bash "$SCRIPT" --mode delegate > "$dir/invalid.out" 2> "$dir/invalid.err"; rc=$?; set -e
  [ "$rc" -eq 2 ]
  printf 'prompt\n' > "$dir/plan-prompt.md"
  AGENT_DELEGATE_TEST_MODE=1 bash "$SCRIPT" --mode delegate --prompt-file "$dir/plan-prompt.md" --out-dir "$dir" --label plan --target codex --sandbox read-only | grep -q 'target=codex sandbox=read-only'
  run_sync "$dir" claude-done claude delegate done
  run_sync "$dir" claude-blocked claude delegate blocked
  json_file "$dir/claude-blocked-report.json" -e 'eq(d?.status, "blocked") && eq((type(d?.blocker)), "string") && eq((type(d?.blocker_category)), "string")' >/dev/null
  run_sync "$dir" review claude review done
  [ -f "$dir/review-review.md" ]
  run_sync "$dir" codex-done codex delegate done
  printf 'detached prompt\n' > "$dir/detach-prompt.md"
  PATH="$STUB_DIR:$PATH" bash "$SCRIPT" --mode delegate --prompt-file "$dir/detach-prompt.md" --out-dir "$dir" \
    --label detach --target claude --sandbox workspace-write --detach > "$dir/detach-launch.out" 2> "$dir/detach-launch.err"
  detach_report="$(tail -1 "$dir/detach-launch.out")"; deadline=$(( $(date -u +%s) + 10 ))
  while [ "$(date -u +%s)" -lt "$deadline" ]; do
    if [ -f "$detach_report" ] && json_file "$detach_report" -e 'eq(d?.status, "done")' >/dev/null 2>&1 &&
       [ -f "$dir/detach-heartbeat.json" ] && [ ! -e "$dir/detach-owner.json" ] && [ ! -e "$dir/detach.pid" ]; then
      break
    fi
  done
  json_file "$detach_report" -e 'eq(d?.status, "done") && eq((type(d?.meta?.run_id)), "string")' >/dev/null
  json_file "$dir/detach-heartbeat.json" -e --argjson report_run "$(json_file "$detach_report" -c 'd?.meta?.run_id')" 'eq(d?.state, "done") && eq(d?.run_id, $.report_run)' >/dev/null
  [ ! -e "$dir/detach-owner.json" ] && [ ! -e "$dir/detach.pid" ]
  ! find "$dir" -maxdepth 1 -name '*.tmp.*' -print -quit | grep -q .
  rm -rf "$dir"
  run_detach_review_lifecycle_stub survives-launcher-exit || die "detach monitor did not survive launcher process-group cleanup"
  run_detach_review_lifecycle_stub worker-death || die "detach monitor did not synthesize blocked after worker death"
  run_detach_review_lifecycle_stub monitor-termination || die "detach monitor did not synthesize blocked after monitor termination"
  check_owner_lock_signal_fixture "$FIXTURE_DIR/owner-lock-signal-cases.tsv" ||
    die "owner lock signal fixture rejected"
}

case_monitor_only_publishers() {
  local bad
  awk -F '\t' 'NR==1{next} $3!="monitor" && $3!="launcher" && $3!="worker"{exit 1} END{exit !(NR==6)}' "$FIXTURE_DIR/publisher-contract.tsv"
  bad="$(mktemp "$(cd "${TMPDIR:-/tmp}" && pwd)/agent-delegate-publisher.XXXXXX")"
  awk 'BEGIN{FS=OFS="\t"} NR==2{$3="unknown"} {print}' "$FIXTURE_DIR/publisher-contract.tsv" > "$bad"
  if awk -F '\t' 'NR==1{next} $3!="monitor" && $3!="launcher" && $3!="worker"{exit 1}' "$bad"; then rm -f "$bad"; die "publisher checker accepted invalid role"; fi
  rm -f "$bad"
  grep -q '^run_monitor()' "$SCRIPT"
  grep -q '^run_worker()' "$SCRIPT"
  grep -q 'REPORT_FILE="$CANDIDATE_FILE"' "$SCRIPT"
  grep -q 'write_heartbeat running' "$SCRIPT"
  ! sed -n '/^run_worker()/,/^}/p' "$SCRIPT" | grep -q 'write_heartbeat'
  ! sed -n '/^run_cli()/,/^}/p' "$SCRIPT" | grep -q 'write_heartbeat'
}

case_allowed_scope_and_skill_style() {
  local changed bad_dir skill_files
  changed="$(git -C "$REPO_ROOT" status --porcelain | sed 's/^...//' | sed 's/^"//;s/"$//' || true)"
  while IFS= read -r path; do
    [ -z "$path" ] && continue
    case "$path" in
      AGENTS.md|README.md|README.ja.md|docs/coding-rules.md|docs/review_rules.md|docs/skill-style-guide.md) : ;;
      skills/agent-delegate/SKILL.md|skills/agent-delegate/references/contract.md|skills/agent-delegate/references/contract.ja.md) : ;;
      skills/mcp-convert/SKILL.md) : ;;
      skills/agent-delegate/references/scripts/agent-delegate.sh|skills/agent-delegate/references/scripts/json-tool.mjs|skills/agent-delegate/references/scripts/tests/*) : ;;
      skills/spec-orchestrate/SKILL.md|skills/spec-orchestrate/references/role-dispatch.md|skills/spec-orchestrate/references/role-dispatch.ja.md) : ;;
      skills/spec-orchestrate/references/phases/spec_generate.md|skills/spec-orchestrate/references/phases/spec_generate.ja.md) : ;;
      skills/spec-orchestrate/references/phases/spec_review.md|skills/spec-orchestrate/references/phases/spec_review.ja.md) : ;;
      skills/spec-orchestrate/references/phases/evaluate.md|skills/spec-orchestrate/references/phases/evaluate.ja.md) : ;;
      skills/spec-implement/SKILL.md|skills/spec-implement/references/implement-guide.md|skills/spec-implement/references/implement-guide.ja.md) : ;;
      skills/spec-evaluate/SKILL.md|skills/spec-evaluate/references/execution-backend.md|skills/spec-evaluate/references/execution-backend.ja.md) : ;;
      *) die "out-of-scope tracked change: $path" ;;
    esac
  done <<EOF
$changed
EOF
  bash "$QUALITY_CONTRACT" >/dev/null
  skill_files=("$REPO_ROOT"/skills/*/SKILL.md)
  [ -f "${skill_files[0]}" ] || die 'quality checker found no SKILL.md files'
  bash "$QUALITY" "${skill_files[@]}" >/dev/null
  bad_dir="$(new_work_dir)/wrong-name"; mkdir -p "$bad_dir"; cp "$REPO_ROOT/skills/agent-delegate/SKILL.md" "$bad_dir/SKILL.md"
  if bash "$QUALITY" "$bad_dir/SKILL.md" >/dev/null 2>&1; then rm -rf "$(dirname "$bad_dir")"; die "quality checker accepted a broken directory/name relation"; fi
  rm -rf "$(dirname "$bad_dir")"
}

check_spec_ids() {
  local ids="$1" spec_dir="$2" id kind file
  while IFS=$'\t' read -r id kind; do
    [ "$id" = id ] && continue
    for file in requirement.md design.md tasks.md test.md; do
      grep -q "$id" "$spec_dir/$file" || return 1
    done
  done < "$ids"
}

case_spec_id_semantic_coverage() {
  local bad_dir spec_dir file
  spec_dir="$REPO_ROOT/.specs/agent-delegate-heartbeat"
  for file in requirement.md design.md tasks.md test.md; do [ -f "$REPO_ROOT/.specs/agent-delegate-heartbeat/$file" ] || die "missing spec: $file"; done
  check_spec_ids "$FIXTURE_DIR/spec-ids.tsv" "$spec_dir" || die "spec ID coverage rejected"
  bad_dir="$(new_work_dir)"
  for file in requirement.md design.md tasks.md test.md; do cp "$spec_dir/$file" "$bad_dir/$file"; done
  sed 's/REQ-001/REQ-CORRUPTED/g' "$bad_dir/design.md" > "$bad_dir/design.md.tmp"; mv "$bad_dir/design.md.tmp" "$bad_dir/design.md"
  if check_spec_ids "$FIXTURE_DIR/spec-ids.tsv" "$bad_dir"; then rm -rf "$bad_dir"; die "spec checker accepted corrupted semantic coverage"; fi
  [ "$(grep -Ec '^## T-A[0-9]+:' "$REPO_ROOT/.specs/agent-delegate-heartbeat/test.md")" -eq 22 ]
  rm -rf "$bad_dir"
}

case_heartbeat_harness_contract() {
  local dir result
  dir="$(new_work_dir)"; result="$(run_harness "$dir" "$1" claude done)"
  check_harness_positive_and_negative "$result" 2 done
  [ "$(mode_of "$dir/$1-sentinel-ready.json")" = 600 ]
  awk -F '\t' '$2=="owner-before-fifo"{owner=NR} $2=="fifo-ready"{fifo=NR} END{exit !(owner && fifo && owner<fifo)}' "$dir/$1-harness-events.tsv"
  rm -rf "$dir"
}

case_readonly_gate_evidence() {
  awk -F '\t' 'NR>1 && $2!="yes" && $2!="no"{exit 1} END{exit !(NR>10)}' "$FIXTURE_DIR/readonly-evidence.tsv"
  grep -q $'^environment_dump\tno$' "$FIXTURE_DIR/readonly-evidence.tsv"
  grep -q $'^structured_review\tyes$' "$FIXTURE_DIR/readonly-evidence.tsv"
}

case_all_repeat_3() {
  bash "$TEST_DIR/run_tests.sh" --all --repeat 3
}

case_synchronous_no_heartbeat() {
  local dir label="$1" barrier pid owner report deadline
  dir="$(new_work_dir)"; barrier="$dir/barrier"; mkdir "$barrier"; mkfifo "$barrier/release.fifo"
  printf 'prompt\n' > "$dir/prompt.md"
  PATH="$STUB_DIR:$PATH" AGENT_DELEGATE_STUB_BARRIER_DIR="$barrier" bash "$SCRIPT" --mode delegate \
    --prompt-file "$dir/prompt.md" --out-dir "$dir" --label "$label" --target claude --sandbox workspace-write \
    > "$dir/out" 2> "$dir/err" &
  pid=$!
  deadline=$(( $(date -u +%s) + 10 ))
  while [ "$(date -u +%s)" -lt "$deadline" ]; do
    [ -f "$barrier/claude.ready" ] && [ -f "$dir/$label-owner.json" ] && break
    kill -0 "$pid" >/dev/null 2>&1 || break
  done
  owner="$dir/$label-owner.json"; [ -f "$owner" ] || { kill "$pid" 2>/dev/null || true; die "sync owner was not observable"; }
  json_file "$owner" -e --argjson pid "$pid" 'eq(d?.run_kind, "sync") && eq(d?.runner_pid, $.pid) && eq(d?.launcher_pid, $.pid) && eq(d?.monitor_pid, null) && eq(d?.worker_pid, $.pid) && eq(d?.lease_at, d?.started_at) && eq(d?.handoff_dir, null) && eq(d?.handoff_phase, "not_applicable")' >/dev/null
  [ ! -e "$dir/$label-heartbeat.json" ] && [ ! -e "$dir/$label.pid" ]
  printf 'release\n' > "$barrier/release.fifo"; wait "$pid"
  report="$(tail -1 "$dir/out")"; [ "$report" = "$dir/$label-report.json" ]
  [ ! -e "$owner" ] && [ ! -e "$dir/$label-owner.lock" ] && [ ! -e "$dir/$label-heartbeat.json" ] && [ ! -e "$dir/$label.pid" ]
  rm -rf "$dir"
}

check_handoff_artifacts() {
  local result="$1" scenario="$2" expected_phase="$3" expected_attempts="$4" expected_heartbeat="$5"
  local expected_publisher="$6" expected_report="$7" expected_decision="$8" publisher_override="${9:-}"
  local out label run request ack sentinel owner worker publisher decision report heartbeat
  out="$(dirname "$result")"; label="$(basename "$result" -harness-result.json)"; run="$(json_file "$result" -r 'd?.run_id')"
  request="$out/$label-handoff-request.json"; ack="$out/$label-handoff-acknowledgement.json"
  sentinel="$out/$label-handoff-sentinel-final.json"; owner="$out/$label-owner-final.json"
  worker="$out/$label-worker-result.json"; publisher="${publisher_override:-$out/$label-publisher.txt}"
  decision="$out/$label-launcher-decision.txt"; report="$(json_file "$result" -r 'd?.report_path')"
  heartbeat="$(json_file "$result" -r 'd?.heartbeat_path')"
  [ -f "$request" ] && [ -f "$ack" ] && [ -f "$sentinel" ] && [ -f "$owner" ] &&
    [ -f "$worker" ] && [ -f "$publisher" ] && [ -f "$decision" ] && [ -f "$report" ] || return 1
  json_file "$request" -e --arg run "$run" 'eq(d?.run_id, $.run)' >/dev/null || return 1
  json_file "$sentinel" -e --arg run "$run" --arg phase "$expected_phase" 'eq(d?.run_id, $.run) && eq(d?.handoff_phase, $.phase)' >/dev/null || return 1
  json_file "$owner" -e --arg run "$run" --arg phase "$expected_phase" 'eq(d?.run_id, $.run) && eq(d?.handoff_phase, $.phase)' >/dev/null || return 1
  json_file "$worker" -e --argjson attempts "$expected_attempts" 'eq(d?.attempts, $.attempts) && eq((type(d?.started)), "boolean")' >/dev/null || return 1
  [ "$(cat "$publisher")" = "$expected_publisher" ] && [ "$(cat "$decision")" = "$expected_decision" ] || return 1
  case "$expected_report" in
    blocked) json_file "$report" -e --arg run "$run" 'eq(d?.status, "blocked") && eq(d?.meta?.run_id, $.run)' >/dev/null || return 1 ;;
    absent) [ "$(json_file "$report" -r 'd?.status')" != blocked ] || return 1 ;;
    *) return 1 ;;
  esac
  case "$expected_heartbeat" in
    absent) [ ! -f "$heartbeat" ] || return 1 ;;
    terminal-blocked) json_file "$heartbeat" -e --arg run "$run" 'eq(d?.run_id, $.run) && eq(d?.state, "blocked")' >/dev/null || return 1 ;;
    terminal-done) json_file "$heartbeat" -e --arg run "$run" 'eq(d?.run_id, $.run) && eq(d?.state, "done")' >/dev/null || return 1 ;;
    *) return 1 ;;
  esac
  case "$scenario" in
    owner-pid-mismatch)
      json_file "$request" -e 'eq(d?.message, "handoff-ready")' >/dev/null && json_file "$ack" -e '(type(d?.raw)==="string" && d?.raw.startsWith("handoff-failed "))' >/dev/null || return 1 ;;
    acknowledgement-mismatch)
      json_file "$request" -e 'eq(d?.message, "handoff-ready")' >/dev/null && json_file "$ack" -e '(type(d?.raw)==="string" && d?.raw.startsWith("monitor-ready injected-mismatch "))' >/dev/null || return 1 ;;
    final-ack-timeout)
      json_file "$request" -e 'eq(d?.message, "handoff-verified") && eq(d?.verification, "ok") && eq(d?.delivery, "timeout")' >/dev/null &&
        json_file "$ack" -e '(type(d?.raw)==="string" && d?.raw.startsWith("handoff-committed "))' >/dev/null || return 1 ;;
    expire-handoff)
      json_file "$request" -e 'eq(d?.message, "expire-handoff") && eq(d?.expired_before_commit, true)' >/dev/null || return 1 ;;
    worker-start-failure)
      json_file "$request" -e 'eq(d?.message, "handoff-verified") && eq(d?.verification, "ok")' >/dev/null &&
        json_file "$worker" -e 'eq(d?.started, false) && eq(d?.attempts, 1)' >/dev/null || return 1 ;;
    final-ack-response-lost)
      json_file "$request" -e 'eq(d?.message, "handoff-verified") && eq(d?.verification, "ok")' >/dev/null &&
        json_file "$ack" -e '(type(d?.raw)==="string" && d?.raw.startsWith("handoff-verified-response-lost "))' >/dev/null && json_file "$worker" -e 'eq(d?.started, true) && eq(d?.attempts, 1)' >/dev/null || return 1 ;;
    *) return 1 ;;
  esac
}

check_phase_artifacts() {
  local result="$1" sentinel_phase="$2" owner_phase="$3" attempts="$4" publisher="$5" status="$6" decision="$7" publisher_override="${8:-}"
  local out label run sentinel owner worker publisher_file decision_file report heartbeat
  out="$(dirname "$result")"; label="$(basename "$result" -harness-result.json)"; run="$(json_file "$result" -r 'd?.run_id')"
  sentinel="$out/$label-handoff-sentinel-final.json"; owner="$out/$label-owner-final.json"
  worker="$out/$label-worker-result.json"; publisher_file="${publisher_override:-$out/$label-publisher.txt}"
  decision_file="$out/$label-launcher-decision.txt"; report="$(json_file "$result" -r 'd?.report_path')"; heartbeat="$(json_file "$result" -r 'd?.heartbeat_path')"
  json_file "$sentinel" -e --arg run "$run" --arg phase "$sentinel_phase" 'eq(d?.run_id, $.run) && eq(d?.handoff_phase, $.phase)' >/dev/null &&
    json_file "$owner" -e --arg run "$run" --arg phase "$owner_phase" 'eq(d?.run_id, $.run) && eq(d?.handoff_phase, $.phase)' >/dev/null &&
    json_file "$worker" -e --argjson attempts "$attempts" 'eq(d?.attempts, $.attempts)' >/dev/null || return 1
  [ "$(cat "$publisher_file")" = "$publisher" ] && [ "$(cat "$decision_file")" = "$decision" ] || return 1
  json_file "$report" -e --arg run "$run" --arg status "$status" 'eq(d?.meta?.run_id, $.run) && eq(d?.status, $.status)' >/dev/null || return 1
  if [ "$attempts" -eq 0 ]; then [ ! -f "$heartbeat" ] || return 1
  else json_file "$heartbeat" -e --arg run "$run" --arg state "$status" 'eq(d?.run_id, $.run) && eq(d?.state, $.state)' >/dev/null || return 1
  fi
}

check_rollback_branch() {
  local with_old_pid="$1" fail_stage="$2" dir handoff label=rollback rc owner_hash report_hash heartbeat_hash pid_hash=absent pid_ino=""
  local owner_after report_after heartbeat_after pid_after
  dir="$(new_work_dir)"; printf 'prompt\n' > "$dir/prompt.md"
  handoff="$(mktemp -d "$(cd "${TMPDIR:-/tmp}" && pwd)/agent-delegate-heartbeat-handoff.XXXXXX")"
  printf 'old-owner\n' > "$dir/$label-owner.json"; printf 'old-report\n' > "$dir/$label-report.json"; printf 'old-heartbeat\n' > "$dir/$label-heartbeat.json"
  if [ "$with_old_pid" = yes ]; then
    printf 'pid: 999999\nrun_id: old-run\n' > "$dir/$label.pid"
    pid_hash="$(sha256_file "$dir/$label.pid")"; pid_ino="$(stat -c %i "$dir/$label.pid" 2>/dev/null || stat -f %i "$dir/$label.pid")"
  fi
  owner_hash="$(sha256_file "$dir/$label-owner.json")"; report_hash="$(sha256_file "$dir/$label-report.json")"; heartbeat_hash="$(sha256_file "$dir/$label-heartbeat.json")"
  set +e
  AGENT_DELEGATE_TEST_MODE=heartbeat AGENT_DELEGATE_TEST_HANDOFF_DIR="$handoff" AGENT_DELEGATE_TEST_FAIL_STAGE="$fail_stage" \
    bash "$SCRIPT" --mode delegate --prompt-file "$dir/prompt.md" --out-dir "$dir" --label "$label" --target claude --detach --force \
      > "$dir/launch.out" 2> "$dir/launch.err"
  rc=$?; set -e
  [ "$rc" -eq 2 ] || return 1
  owner_after="$(sha256_file "$dir/$label-owner.json")"; report_after="$(sha256_file "$dir/$label-report.json")"; heartbeat_after="$(sha256_file "$dir/$label-heartbeat.json")"
  [ "$owner_after" = "$owner_hash" ] && [ "$report_after" = "$report_hash" ] && [ "$heartbeat_after" = "$heartbeat_hash" ] || return 1
  if [ "$with_old_pid" = yes ]; then
    pid_after="$(sha256_file "$dir/$label.pid")"
    [ "$pid_after" = "$pid_hash" ] && [ "$(stat -c %i "$dir/$label.pid" 2>/dev/null || stat -f %i "$dir/$label.pid")" = "$pid_ino" ] || return 1
  else [ ! -e "$dir/$label.pid" ] || return 1
  fi
  ! find "$dir" -maxdepth 1 \( -name '*.tmp.*' -o -name '*.backup.*' -o -name '*report.candidate*' -o -name '*owner.lock*' \) -print -quit | grep -q . || return 1
  [ ! -e "$handoff/launcher-to-monitor.fifo" ] && [ ! -e "$handoff/monitor-to-launcher.fifo" ] || return 1
  [ ! -d "$handoff" ] || rmdir "$handoff"
  rm -rf "$dir"
}

case_pid_handoff_barrier() {
  local scenario expected_phase attempts expected_heartbeat publisher expected_report decision dir result beats status bad_publisher
  local fail_stage expected_sentinel expected_owner
  check_rollback_branch yes new_pid || die "rollback rejected: prior pid + new pid publication failure"
  check_rollback_branch yes owner || die "rollback rejected: prior pid + owner publication failure"
  check_rollback_branch no owner || die "rollback rejected: absent prior pid + owner publication failure"
  while IFS=$'\t' read -r scenario expected_phase attempts expected_heartbeat publisher expected_report decision; do
    [ "$scenario" = scenario ] && continue
    dir="$(new_work_dir)"
    result="$(run_harness "$dir" "$1-$scenario" claude "$scenario")"
    case "$scenario" in
      worker-start-failure) beats=0; status=blocked ;;
      final-ack-response-lost) beats=2; status=done ;;
      *) beats=0; status=blocked ;;
    esac
    check_harness_positive_and_negative "$result" "$beats" "$status"
    check_handoff_artifacts "$result" "$scenario" "$expected_phase" "$attempts" "$expected_heartbeat" \
      "$publisher" "$expected_report" "$decision" || die "handoff artifacts rejected: $scenario"
    bad_publisher="$dir/$1-$scenario-negative-publisher.txt"; printf 'corrupted\n' > "$bad_publisher"
    if check_handoff_artifacts "$result" "$scenario" "$expected_phase" "$attempts" "$expected_heartbeat" \
      "$publisher" "$expected_report" "$decision" "$bad_publisher"; then
      die "handoff checker accepted corrupted publisher: $scenario"
    fi
    rm -rf "$dir"
  done < "$FIXTURE_DIR/handoff-cases.tsv"
  while IFS=$'\t' read -r scenario fail_stage expected_sentinel expected_owner attempts publisher status decision; do
    [ "$scenario" = scenario ] && continue
    dir="$(new_work_dir)"; result="$(run_harness "$dir" "$1-$scenario" claude "$scenario")"
    if [ "$attempts" -eq 0 ]; then beats=0; else beats=2; fi
    check_harness_positive_and_negative "$result" "$beats" "$status"
    check_phase_artifacts "$result" "$expected_sentinel" "$expected_owner" "$attempts" "$publisher" "$status" "$decision" ||
      die "phase artifacts rejected: $scenario"
    bad_publisher="$dir/$1-$scenario-negative-publisher.txt"; printf 'corrupted\n' > "$bad_publisher"
    if check_phase_artifacts "$result" "$expected_sentinel" "$expected_owner" "$attempts" "$publisher" "$status" "$decision" "$bad_publisher"; then
      die "phase checker accepted corrupted publisher: $scenario"
    fi
    rm -rf "$dir"
  done < "$FIXTURE_DIR/phase-cases.tsv"
}

json_tool_expect() {
  local id="$1" want_rc="$2" want_out="$3" input="$4" rc out
  shift 4
  set +e
  out="$(printf '%s' "$input" | json_tool "$@" 2>/dev/null)"; rc=$?
  set -e
  [ "$rc" -eq "$want_rc" ] || die "json-tool $id: exit $rc, expected $want_rc"
  [ "$out" = "$want_out" ] || die "json-tool $id: unexpected output: $out"
}

case_json_tool_semantics() {
  local dir id checked="" out rc repo home report i
  json_tool_expect missing-field-null 0 null '{}' -r 'd.x'
  json_tool_expect missing-field-null 0 '' '{}' -r 'alt(d.x, EMPTY)'
  checked="$checked missing-field-null"

  json_tool_expect exit-codes 1 false '{"a":1}' -e 'd.a === 2'
  json_tool_expect exit-codes 1 null '{"a":null}' -e 'd.a'
  json_tool_expect exit-codes 4 '' '{}' -e 'EMPTY'
  json_tool_expect exit-codes 0 'true' '{"a":1}' -e 'd.a === 1'
  json_tool_expect exit-codes 2 '' 'nope' -e 'd'
  json_tool_expect exit-codes 5 '' '{}' -e 'each(null)'
  checked="$checked exit-codes"

  json_tool_expect null-equality 0 'true' '{}' -e 'eq(d.monitor_pid, null)'
  json_tool_expect null-equality 0 'true' '{"monitor_pid":null}' -e 'eq(d.monitor_pid, null)'
  json_tool_expect null-equality 1 'false' '{"monitor_pid":0}' -e 'eq(d.monitor_pid, null)'
  checked="$checked null-equality"

  json_tool_expect jsonl-stream 0 'T' $'{"type":"x"}\n{"type":"thread.started","thread_id":"T"}\n' -r 'eq(d.type, "thread.started") ? d.thread_id : EMPTY'
  json_tool_expect jsonl-stream 2 'a' $'{"v":"a"}\n{\n{"v":"b"}\n' -r 'd.v'
  checked="$checked jsonl-stream"

  dir="$(new_work_dir)"
  node -e 'process.stdout.write(JSON.stringify("x".repeat(1000000)) + "\n{\n")' > "$dir/large.jsonl"
  set +e
  json_file "$dir/large.jsonl" -c 'd' 2>/dev/null | cat > "$dir/large.out"; rc="${PIPESTATUS[0]}"
  set -e
  [ "$rc" -eq 2 ] && [ "$(wc -c < "$dir/large.out" | tr -d ' ')" -eq 1000003 ] || die "json-tool large-output-then-error: exit $rc, $(wc -c < "$dir/large.out") bytes"
  node -e 'process.stdout.write(JSON.stringify("x".repeat(1000000)) + "\n" + JSON.stringify(null) + "\n")' > "$dir/large-throw.jsonl"
  set +e
  json_file "$dir/large-throw.jsonl" -c 'd === null ? each(null) : d' 2>/dev/null | cat > "$dir/large.out"; rc="${PIPESTATUS[0]}"
  set -e
  [ "$rc" -eq 5 ] && [ "$(wc -c < "$dir/large.out" | tr -d ' ')" -eq 1000003 ] || die "json-tool large-output-then-error: throw exit $rc"
  checked="$checked large-output-then-error"

  json_tool_expect argument-unconverted 0 '/tmp/x' '' -n -r --arg h /tmp/x '$.h'
  checked="$checked argument-unconverted"

  json_tool_expect codepoint-length 0 '3' '' -n --arg s 'aあ😀' 'len($.s)'
  checked="$checked codepoint-length"

  json_tool_expect num-conversion 0 '12' '' -n --arg v 12 'num($.v)'
  json_tool_expect num-conversion 5 '' '' -n --arg v 12x 'num($.v)'
  checked="$checked num-conversion"

  json_tool_expect multiple-values 0 $'"c"\n{"r":"h"}' '{"commit":"c","hashes":{"r":"h"}}' -c 'each([d.commit, d.hashes])'
  checked="$checked multiple-values"

  json_tool_expect raw-slurp 0 '[]' '' -R -s -c 'd.split("\n").filter((x) => len(x) > 0)'
  json_tool_expect raw-slurp 0 '["a","b c"]' $'a\nb c\n' -R -s -c 'd.split("\n").filter((x) => len(x) > 0)'
  json_tool_expect raw-slurp 0 '"a\nb"' $'a\nb' -R -s 'd'
  checked="$checked raw-slurp"

  json_tool_expect undefined-argument 5 '' '' -n '$.missing'
  checked="$checked undefined-argument"

  json_tool_expect pretty-format 0 $'{\n  "a": [\n    1,\n    {\n      "b": null\n    }\n  ],\n  "c": {}\n}' '{"a":[1,{"b":null}],"c":{}}' 'd'
  json_tool_expect pretty-format 0 '{"a":[1,{"b":null}],"c":{}}' '{"a":[1,{"b":null}],"c":{}}' -c 'd'
  checked="$checked pretty-format"

  repo="$dir/repo"; home="$dir/home"; mkdir -p "$repo" "$home/.codex" "$dir/out"
  git -C "$repo" init -q
  repo="$(cd "$repo" && pwd)"
  printf '[projects."%s"]\ntrust_level = "trusted"\n' "$repo" > "$home/.codex/config.toml"
  printf 'stub prompt\n' > "$dir/prompt.md"
  set +e
  (cd "$repo" && HOME="$home" PATH="$STUB_DIR:$PATH" AGENT_DELEGATE_STUB_MODE=blocked \
    AGENT_DELEGATE_STUB_TOUCH=3000 AGENT_DELEGATE_STUB_STDERR_CHARS=40000 \
    bash "$SCRIPT" --mode delegate --prompt-file "$dir/prompt.md" --out-dir "$dir/out" --label long \
      --target codex --sandbox workspace-write > "$dir/long.out" 2> "$dir/long.err")
  set -e
  report="$dir/out/long-report.json"
  [ -f "$report" ] || die "json-tool long-report-fields: no report"
  json_file "$report" -e '
    eq(d.status, "blocked") && type(d.blocker)==="string" && d.blocker.length > 40000 &&
    d.blocker.includes("e".repeat(40000)) && len(d.touchedFiles)===3000 &&
    d.touchedFiles.every((f) => /^touched-[0-9]+\.txt$/.test(f))
  ' >/dev/null || die "json-tool long-report-fields: report did not carry the long blocker and touched list"
  i=1; while [ "$i" -le 3000 ]; do printf 'touched-%s.txt\n' "$i"; i=$((i + 1)); done | sort > "$dir/expected-touched"
  json_file "$report" -r 'each(d.touchedFiles)' | sort | cmp -s - "$dir/expected-touched" || die "json-tool long-report-fields: touched list differs"
  checked="$checked long-report-fields"
  rm -rf "$dir"

  while IFS=$'\t' read -r id _; do
    [ "$id" = check_id ] && continue
    case " $checked " in *" $id "*) : ;; *) die "json-tool check is listed but not run: $id" ;; esac
  done < "$FIXTURE_DIR/json-tool-cases.tsv"
}

run_named_case() {
  local case_name="$1" fn
  dry_validate_case "$case_name" >/dev/null
  fn="case_$(printf '%s' "$case_name" | tr '-' '_')"
  type "$fn" >/dev/null 2>&1 || die "case is registered but has no implementation: $case_name"
  "$fn" "$case_name"
  printf 'PASS\t%s\n' "$case_name"
}

write_repeat_manifest() {
  local out="$1" iteration="$2" commit runner_hash fixture_hash harness_hash
  commit="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  runner_hash="$(sha256_file "$TEST_DIR/run_tests.sh")"
  fixture_hash="$(sha256_file "$MANIFEST")"
  harness_hash="$(sha256_file "$HARNESS")"
  json_tool -n --argjson iteration "$iteration" --arg commit "$commit" --arg runner "$runner_hash" \
    --arg fixture "$fixture_hash" --arg harness "$harness_hash" --argjson beats "$CURRENT_HEARTBEATS" \
    --argjson terminals "$CURRENT_TERMINALS" '
    ({iteration:$.iteration,commit:$.commit,hashes:{runner:$.runner,fixture:$.fixture,harness:$.harness},
     case_count:28,exit_code:0,heartbeat_updates:$.beats,terminal_reports:$.terminals,runtime_residue:false})
  ' > "$out"
  json_file "$out" -e 'eq(d?.case_count, 28) && eq(d?.exit_code, 0) && d?.heartbeat_updates >= 2 && d?.terminal_reports >= 1 && eq(d?.runtime_residue, false)' >/dev/null
}

if [ -n "$RUN_CASE" ]; then
  dry_validate_case "$RUN_CASE"
  [ "$DRY_RUN" -eq 1 ] || run_named_case "$RUN_CASE"
  exit 0
fi

require_command node; require_command git; require_command shasum
repeat_root="$(new_work_dir)"
trap 'rm -rf "$repeat_root"' EXIT TERM INT HUP
baseline_hashes=""
i=1
while [ "$i" -le "$REPEAT" ]; do
  CURRENT_HEARTBEATS=0; CURRENT_TERMINALS=0
  while IFS=$'\t' read -r test_id case_name kind scenario fixture expected; do
    [ "$test_id" = test_id ] && continue
    [ "$kind" = meta ] && continue
    run_named_case "$case_name"
  done < "$MANIFEST"
  run_named_case readonly-gate-evidence
  manifest_out="$repeat_root/repeat-$i.json"
  write_repeat_manifest "$manifest_out" "$i"
  hashes="$(json_file "$manifest_out" -c 'each([d?.commit, d?.hashes])')"
  if [ -z "$baseline_hashes" ]; then baseline_hashes="$hashes"; else [ "$hashes" = "$baseline_hashes" ] || die "repeat hashes changed"; fi
  printf 'REPEAT_PASS\t%s\t%s\n' "$i" "$manifest_out"
  i=$((i + 1))
done
if [ "$REPEAT" -eq 3 ]; then
  aggregate="$repeat_root/aggregate.json"
  json_tool -n --argjson repeats "$REPEAT" --arg commit "$(git -C "$REPO_ROOT" rev-parse HEAD)" \
    '({commit:$.commit,repeats:$.repeats,registered_cases:28,passed_cases:28,failed_cases:0,
      meta_cases:["readonly-gate-evidence","all-repeat-3"]})' > "$aggregate"
  json_file "$aggregate" -e 'eq(d?.repeats, 3) && eq(d?.registered_cases, 28) && eq(d?.passed_cases, 28) && eq(d?.failed_cases, 0)' >/dev/null
  printf 'PASS\tall-repeat-3\n'
  printf 'AGGREGATE\t%s\n' "$(json_file "$aggregate" -c 'd')"
  printf 'ALL_PASS\trepeats=%s\tcases=28/28\n' "$REPEAT"
else
  printf 'ALL_PASS\trepeats=%s\tcases=27/28\tmeta=all-repeat-3-deferred\n' "$REPEAT"
fi
