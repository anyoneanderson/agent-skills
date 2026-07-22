#!/usr/bin/env bash
# pipeline-state-check.sh — verify pipeline-state.json against on-disk evidence.
#
# The state file is the orchestrator's own claim about where the run is; this
# script cross-checks that claim against evidence the state cannot fake: the
# tasks.md checkboxes, run-record files, and (when gh is available) the PR for
# the current branch. Run it after every state write and as the first step of a
# resume. A drift means the state was left behind (e.g. a phase ran without its
# state update) — reconcile state to the evidence before continuing
# (pipeline-config.md §State integrity check).
#
# Usage: pipeline-state-check.sh <spec-dir>       e.g. .specs/user-auth
# Exit:  0 = consistent, 1 = drift found (one "DRIFT:" line each), 2 = usage error

set -uo pipefail

SPEC_DIR="${1:-}"
SPEC_DIR="${SPEC_DIR%/}"
[ -n "$SPEC_DIR" ] && [ -d "$SPEC_DIR" ] || { echo "usage: $0 <spec-dir>" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "pipeline-state-check: jq is required" >&2; exit 2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$SPEC_DIR/pipeline-state.json"
METRICS="$(dirname "$SPEC_DIR")/pipeline-metrics.jsonl"
RETROSPECTIVE_LEDGER="$SCRIPT_DIR/retrospective-ledger.sh"
[ -f "$STATE" ] || { echo "pipeline-state-check: no state file at $STATE" >&2; exit 2; }
jq empty "$STATE" 2>/dev/null || { echo "DRIFT: $STATE is not valid JSON"; exit 1; }

drift=0
report() { echo "DRIFT: $1"; drift=1; }

sha256_stream() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    return 2
  fi
}

phase="$(jq -r '.phase // empty' "$STATE")"
completed="$(jq -r '(.completed_phases // []) | join(",")' "$STATE")"
host_runtime="$(jq -r '.host_runtime // empty' "$STATE")"

has_completed() { case ",$completed," in *",$1,"*) return 0;; *) return 1;; esac; }

case "$phase" in
  intake|spec_generate|inspect|spec_review|approval|implement|evaluate|arbitration|pr|retrospective) ;;
  *) report "unknown phase '$phase'" ;;
esac

case "$host_runtime" in
  claude|codex) ;;
  *) report "host_runtime must be 'claude' or 'codex' (got '$host_runtime')" ;;
esac

# --- independent review fallback records ------------------------------------
# Older states may omit review_fallbacks. When present, every entry describes
# the only permitted same-AI review fallback: a fresh host-native reviewer used
# because the preferred cross-AI peer was unavailable. Its nested host_runtime
# is historical; the top-level host may change when another runtime resumes.
if ! jq -e '
  . as $state
  | ($state.review_fallbacks // []) as $fallbacks
  | (($fallbacks | type) == "array")
    and all($fallbacks[];
      ((.phase == "spec_review") or (.phase == "implement"))
      and ((.artifact | type) == "string") and ((.artifact | length) > 0)
      and ((.round | type) == "number") and (.round >= 1) and (.round == (.round | floor))
      and ((.preferred_role == "claude") or (.preferred_role == "codex"))
      and ((.actual_role == "claude") or (.actual_role == "codex"))
      and ((.host_runtime == "claude") or (.host_runtime == "codex"))
      and (.preferred_role != .actual_role)
      and (.actual_role == .host_runtime)
      and (.backend == "runtime-native")
      and (.reason == "peer_unavailable")
      and (.independence == "fresh_subagent")
    )
' "$STATE" >/dev/null 2>&1; then
  report "review_fallbacks must contain only self-contained fresh host-native peer_unavailable review records"
fi

# --- completed_phases gap check ------------------------------------------------
# Every phase that precedes the current one in the canonical order must be
# recorded in completed_phases. A gap means a phase ran without its state update
# (the exact failure the #184 dogfood exhibited: phase=retrospective while
# implement/evaluate/pr were never recorded).
#
# Exception: an arbitration draft-PR landing (stall-detection.md —
# arbitration → pr) legitimately reaches pr/retrospective without
# approval/implement/evaluate. It is always recorded as an arbitrations[] entry
# with decision "draft", so that record exempts those three legs.
CANONICAL="intake spec_generate inspect spec_review approval implement evaluate pr retrospective"
draft_landed="$(jq -r '[(.arbitrations // [])[] | select(.decision == "draft")] | length > 0' "$STATE")"
if [ "$phase" != "arbitration" ]; then
  missing=""
  for p in $CANONICAL; do
    [ "$p" = "$phase" ] && break
    if [ "$draft_landed" = "true" ]; then
      case "$p" in approval|implement|evaluate) continue;; esac
    fi
    has_completed "$p" || missing="$missing $p"
  done
  [ -n "${missing// /}" ] && report "phases preceding '$phase' missing from completed_phases:$missing"
fi

# --- tasks.md checkboxes vs implement.tasks_done -----------------------------
# Task ids are T-prefixed and may carry a lowercase or hyphenated suffix
# (T000, T012b, T002-R, ...). Compare complete ids in both directions and
# reject duplicate state entries: tasks_done is a projection, not an event log.
TASK_ID_PATTERN='T[0-9]+[a-z]?(-[A-Za-z0-9]+)?' # task-id-contract
if [ -f "$SPEC_DIR/tasks.md" ] && jq -e '.implement.tasks_done' "$STATE" >/dev/null 2>&1; then
  if ! jq -e --arg pattern "^${TASK_ID_PATTERN}$" '
    .implement.tasks_done
    | (type == "array") and all(.[];
        if type == "string" then test($pattern) else false end)
  ' "$STATE" >/dev/null 2>&1; then
    report "implement.tasks_done must be an array of complete canonical task ids: $(jq -c '.implement.tasks_done' "$STATE")"
  else
    checked="$(
      sed -nE \
        "s/^[[:space:]]*[-*][[:space:]]+\[[xX]\][[:space:]]+($TASK_ID_PATTERN)([^A-Za-z0-9-]|$).*/\1/p" \
        "$SPEC_DIR/tasks.md" | LC_ALL=C sort -u
    )"
    recorded_raw="$(jq -r '.implement.tasks_done[]' "$STATE")"
    recorded_duplicates="$(printf '%s\n' "$recorded_raw" | sed '/^$/d' | LC_ALL=C sort | uniq -d | tr '\n' ' ')"
    recorded="$(printf '%s\n' "$recorded_raw" | sed '/^$/d' | LC_ALL=C sort -u)"
    only_checked="$(LC_ALL=C comm -23 <(printf '%s\n' $checked) <(printf '%s\n' $recorded) 2>/dev/null | tr '\n' ' ')"
    only_recorded="$(LC_ALL=C comm -13 <(printf '%s\n' $checked) <(printf '%s\n' $recorded) 2>/dev/null | tr '\n' ' ')"
    [ -n "${recorded_duplicates// /}" ] && report "duplicate ids in state.implement.tasks_done: $recorded_duplicates"
    [ -n "${only_checked// /}" ] && report "tasks checked in tasks.md but missing from state.implement.tasks_done: $only_checked"
    [ -n "${only_recorded// /}" ] && report "tasks in state.implement.tasks_done but unchecked in tasks.md: $only_recorded"
  fi
fi

# --- run-record files vs phase progression -----------------------------------
if [ -f "$SPEC_DIR/retrospective.md" ] && [ "$phase" != "retrospective" ] && ! has_completed retrospective; then
  report "retrospective.md exists but state is at phase '$phase' (retrospective not recorded)"
fi

# --- retrospective and metrics freshness -----------------------------------
# A completed retrospective is a versioned projection of state and run records.
# Resume invalidates that projection before non-terminal work continues. The
# append-only metrics ledger records supersession instead of rewriting history.
if ! has_completed retrospective && jq -e '(.retrospective | type) == "object"' "$STATE" >/dev/null 2>&1; then
  [ "$phase" = retrospective ] ||
    report "in-progress retrospective action history exists outside the retrospective phase"
  if ! jq -e '
    ((.retrospective.action_history // []) | type) == "array"
    and all((.retrospective.action_history // [])[];
      (.action_key | type) == "string" and (.action_key | length) > 0)
    and (((.retrospective.action_history // []) | map(.action_key) | length)
      == ((.retrospective.action_history // []) | map(.action_key) | unique | length))
  ' "$STATE" >/dev/null 2>&1; then
    report "in-progress retrospective action_history requires unique non-empty action_key values"
  fi
elif has_completed retrospective; then
  if ! jq -e '
    (.run_id | type) == "string" and (.run_id | length) > 0
    and (.retrospective | type) == "object"
    and (.retrospective.revision | type) == "number"
    and (.retrospective.revision >= 1)
    and (.retrospective.revision == (.retrospective.revision | floor))
    and ((.retrospective.snapshot_id | type) == "string")
    and ((.retrospective.snapshot_id | length) > 0)
    and ((.retrospective.metrics_record_id | type) == "string")
    and ((.retrospective.metrics_record_id | length) > 0)
    and ((.retrospective.snapshot | type) == "object")
    and ((.retrospective.stale | type) == "boolean")
    and ((.retrospective.regeneration_required | type) == "boolean")
    and (((.retrospective.action_history // []) | type) == "array")
    and all((.retrospective.action_history // [])[];
      (.action_key | type) == "string" and (.action_key | length) > 0)
    and (((.retrospective.action_history // []) | map(.action_key) | length)
      == ((.retrospective.action_history // []) | map(.action_key) | unique | length))
  ' "$STATE" >/dev/null 2>&1; then
    report "completed retrospective requires versioned snapshot, metrics, and unique action-history metadata"
  else
    run_id="$(jq -r .run_id "$STATE")"
    metrics_record_id="$(jq -r .retrospective.metrics_record_id "$STATE")"
    snapshot_id="$(jq -r .retrospective.snapshot_id "$STATE")"
    retrospective_stale="$(jq -r .retrospective.stale "$STATE")"
    regeneration_required="$(jq -r .retrospective.regeneration_required "$STATE")"

    if [ "$retrospective_stale" != "$regeneration_required" ]; then
      report "retrospective stale and regeneration_required flags must change together"
    fi

    if [ "$regeneration_required" = true ]; then
      if [ ! -f "$METRICS" ]; then
        report "retrospective is stale but pipeline-metrics.jsonl is missing"
      elif ! jq -cs -e --arg run "$run_id" --arg id "$metrics_record_id" '
        ([.[] | select((.record_type // "metrics") == "metrics" and .run_id == $run and .record_id == $id)] | length) == 1
        and ([.[] | select(.record_type == "supersede" and .run_id == $run and .supersedes == $id and .reason == "run_resumed")] | length) == 1
      ' "$METRICS" >/dev/null 2>&1; then
        report "stale retrospective metrics record '$metrics_record_id' is not superseded exactly once"
      elif [ -x "$RETROSPECTIVE_LEDGER" ]; then
        if active_count="$(bash "$RETROSPECTIVE_LEDGER" active-count "$METRICS" "$run_id" 2>/dev/null)"; then
          [ "$active_count" = 0 ] || report "stale metrics remain active for run '$run_id'"
        else
          report "retrospective metrics ledger could not select active records for run '$run_id'"
        fi
      else
        report "retrospective metrics ledger helper is missing or not executable"
      fi
    else
      [ "$phase" = retrospective ] || report "fresh retrospective snapshot is stale because state phase is '$phase'"

      current_completed="$(jq -c '(.completed_phases // [])' "$STATE")"
      snapshot_completed="$(jq -c '.retrospective.snapshot.completed_phases' "$STATE")"
      current_rounds_spec="$(jq -r '(.rounds.spec_review // []) | length' "$STATE")"
      current_rounds_eval="$(jq -r '(.rounds.evaluate // []) | length' "$STATE")"
      current_report_manifest="$(
        find "$SPEC_DIR" -type f \( -name 'report.json' -o -name '*-report.json' \) -print \
          | sed "s#^$SPEC_DIR/##" | LC_ALL=C sort \
          | jq -Rsc 'split("\n") | map(select(length > 0))'
      )"
      current_report_count="$(printf '%s\n' "$current_report_manifest" | jq 'length')"
      current_pr_url="$(jq -r '.pr.url // empty' "$STATE")"
      current_pr_status="$(jq -r '.pr.status // (if .pr.draft == true then "draft" elif .pr.draft == false then "ready" else empty end)' "$STATE")"
      current_state_ts="$(jq -r '.ts_updated // empty' "$STATE")"
      current_state_hash="$(jq -cS 'del(.retrospective)' "$STATE" | sha256_stream 2>/dev/null || printf unavailable)"

      [ "$(jq -r '.retrospective.snapshot.run_id' "$STATE")" = "$run_id" ] ||
        report "retrospective snapshot run_id differs from current state"
      [ "$(jq -r '.retrospective.snapshot.phase' "$STATE")" = "$phase" ] ||
        report "retrospective snapshot phase differs from current state"
      [ "$snapshot_completed" = "$current_completed" ] ||
        report "retrospective snapshot completed_phases differ from current state"
      [ "$(jq -r '.retrospective.snapshot.rounds_spec' "$STATE")" = "$current_rounds_spec" ] ||
        report "retrospective snapshot spec_review rounds differ from current state"
      [ "$(jq -r '.retrospective.snapshot.rounds_eval' "$STATE")" = "$current_rounds_eval" ] ||
        report "retrospective snapshot evaluate rounds differ from current state"
      [ "$(jq -r '.retrospective.snapshot.report_count' "$STATE")" = "$current_report_count" ] ||
        report "retrospective snapshot report.json count differs from current evidence"
      [ "$(jq -c '.retrospective.snapshot.report_manifest' "$STATE")" = "$current_report_manifest" ] ||
        report "retrospective snapshot report.json manifest differs from current evidence"
      [ "$(jq -r '.retrospective.snapshot.pr_url' "$STATE")" = "$current_pr_url" ] ||
        report "retrospective snapshot PR URL differs from current state"
      [ "$(jq -r '.retrospective.snapshot.pr_status' "$STATE")" = "$current_pr_status" ] ||
        report "retrospective snapshot PR status differs from current state"
      [ "$(jq -r '.retrospective.snapshot.state_ts_updated' "$STATE")" = "$current_state_ts" ] ||
        report "retrospective snapshot state timestamp differs from current state"
      [ "$current_state_hash" != unavailable ] ||
        report "SHA-256 is unavailable for retrospective state verification"
      [ "$(jq -r '.retrospective.snapshot.state_hash' "$STATE")" = "$current_state_hash" ] ||
        report "retrospective snapshot state hash differs from current state"
      current_snapshot_hash="$(jq -cS '.retrospective.snapshot' "$STATE" | sha256_stream 2>/dev/null || printf unavailable)"
      [ "$current_snapshot_hash" != unavailable ] ||
        report "SHA-256 is unavailable for retrospective snapshot verification"
      [ "$snapshot_id" = "$current_snapshot_hash" ] ||
        report "retrospective snapshot_id differs from the canonical snapshot hash"

      if [ ! -f "$SPEC_DIR/retrospective.md" ]; then
        report "fresh retrospective metadata has no retrospective.md"
      else
        report_snapshot_count="$(grep -c '^state_snapshot: ' "$SPEC_DIR/retrospective.md" || true)"
        report_snapshot="$(sed -n 's/^state_snapshot: //p' "$SPEC_DIR/retrospective.md" | head -1)"
        if [ "$report_snapshot_count" -ne 1 ]; then
          report "retrospective.md must contain exactly one state_snapshot JSON line"
        elif ! printf '%s\n' "$report_snapshot" | jq empty >/dev/null 2>&1; then
          report "retrospective.md has no valid state_snapshot JSON line"
        elif [ "$(printf '%s\n' "$report_snapshot" | jq -cS '.')" != "$(jq -cS '.retrospective.snapshot' "$STATE")" ]; then
          report "retrospective.md state_snapshot differs from current state metadata"
        fi
      fi

      if [ ! -f "$METRICS" ]; then
        report "fresh retrospective metadata has no pipeline-metrics.jsonl"
      elif [ ! -x "$RETROSPECTIVE_LEDGER" ]; then
        report "retrospective metrics ledger helper is missing or not executable"
      elif active_metric="$(bash "$RETROSPECTIVE_LEDGER" active "$METRICS" "$run_id" 2>/dev/null)"; then
        [ "$(printf '%s\n' "$active_metric" | jq -r .record_id)" = "$metrics_record_id" ] ||
          report "active metrics record differs from state.retrospective.metrics_record_id"
        [ "$(printf '%s\n' "$active_metric" | jq -r .revision)" = "$(jq -r .retrospective.revision "$STATE")" ] ||
          report "active metrics revision differs from state.retrospective.revision"
        [ "$(printf '%s\n' "$active_metric" | jq -r .snapshot_id)" = "$snapshot_id" ] ||
          report "active metrics snapshot_id differs from state.retrospective.snapshot_id"
        [ "$(printf '%s\n' "$active_metric" | jq -cS '.snapshot')" = "$(jq -cS '.retrospective.snapshot' "$STATE")" ] ||
          report "active metrics snapshot differs from current state metadata"
      else
        report "run '$run_id' must have exactly one active metrics record"
      fi
    fi
  fi
fi

# "Either kind of evaluate output exists" — ls over both patterns would fail
# whenever one of them has no match, silently skipping the check.
if compgen -G "$SPEC_DIR/evaluate-*.md" >/dev/null 2>&1 || [ -f "$SPEC_DIR/evaluation-report.md" ]; then
  case "$phase" in evaluate|pr|retrospective) ;; *)
    if ! has_completed evaluate; then
      report "evaluate results exist on disk but state is at phase '$phase' (evaluate not recorded)"
    fi ;;
  esac
fi

# --- PR evidence vs phase ------------------------------------------------------
# If the current branch already has a PR but the state has not reached 'pr',
# the pr phase ran without its state update (or the wrong branch is checked out).
if command -v gh >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git branch --show-current 2>/dev/null)"
  if [ -n "$branch" ] && [ "$phase" != "pr" ] && [ "$phase" != "retrospective" ] && ! has_completed pr; then
    pr_state="$(gh pr view "$branch" --json state --jq .state 2>/dev/null || true)"
    if [ -n "$pr_state" ]; then
      report "a PR exists for branch '$branch' ($pr_state) but state is at phase '$phase' (pr not recorded)"
    fi
  fi
fi

if [ "$drift" -eq 0 ]; then
  echo "STATE OK: phase=$phase completed=[$completed]"
  exit 0
fi
exit 1
