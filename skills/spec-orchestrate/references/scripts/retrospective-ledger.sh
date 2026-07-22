#!/usr/bin/env bash
# retrospective-ledger.sh — append and select versioned retrospective metrics.
#
# Usage:
#   retrospective-ledger.sh append-metrics-once <metrics.jsonl> '<metrics-json>'
#   retrospective-ledger.sh supersede-once <metrics.jsonl> '<supersede-json>'
#   retrospective-ledger.sh active <metrics.jsonl> <run-id>
#   retrospective-ledger.sh active-count <metrics.jsonl> <run-id>
#   retrospective-ledger.sh list-active <metrics.jsonl>
#   retrospective-ledger.sh list-metrics <metrics.jsonl> [run-id]

set -euo pipefail

command -v jq >/dev/null 2>&1 || {
  echo "retrospective-ledger: jq is required" >&2
  exit 2
}

command_name="${1:-}"
metrics_file="${2:-}"
[ -n "$command_name" ] && [ -n "$metrics_file" ] || {
  echo "usage: $0 <append-metrics-once|supersede-once|active|active-count|list-active|list-metrics> <metrics.jsonl> [json|run-id]" >&2
  exit 2
}

read_records() {
  if [ -f "$metrics_file" ]; then
    jq -cs . "$metrics_file"
  else
    printf '%s\n' '[]'
  fi
}

normalized_records() {
  read_records | jq -c '
    to_entries
    | map(
        .key as $index
        | .value
        | if ((.record_type // "metrics") == "metrics") then
            . + {
              record_type: "metrics",
              record_id: (.record_id // ("legacy:" + (($index + 1) | tostring)))
            }
          else . end
      )
  '
}

active_records() {
  normalized_records | jq -c --arg run_id "${1:-}" '
    . as $records
    | [$records[] | select(.record_type == "supersede")
        | {run_id: .run_id, record_id: .supersedes}] as $superseded
    | [$records[]
        | select(.record_type == "metrics")
        | select(($run_id == "") or (.run_id == $run_id))
        | . as $metric
        | select(any($superseded[];
            .run_id == $metric.run_id and .record_id == $metric.record_id) | not)]
  '
}

append_json_line() {
  local line="$1"
  mkdir -p "$(dirname "$metrics_file")"
  printf '%s\n' "$line" >> "$metrics_file"
}

case "$command_name" in
  active-count)
    run_id="${3:-}"
    [ -n "$run_id" ] || { echo "retrospective-ledger: run-id is required" >&2; exit 2; }
    active_records "$run_id" | jq 'length'
    ;;

  active)
    run_id="${3:-}"
    [ -n "$run_id" ] || { echo "retrospective-ledger: run-id is required" >&2; exit 2; }
    active_records "$run_id" | jq -ce '
      if length == 1 then .[0]
      else error("expected exactly one active metrics record, found \(length)")
      end
    '
    ;;

  list-active)
    records="$(active_records "")"
    if ! printf '%s\n' "$records" | jq -e '
      all(.[]; (.run_id | type) == "string" and (.run_id | length) > 0)
      and (group_by(.run_id) | all(.[]; length == 1))
    ' >/dev/null; then
      echo "retrospective-ledger: each run must have at most one active metrics record" >&2
      exit 1
    fi
    printf '%s\n' "$records" | jq -c '.[]'
    ;;

  list-metrics)
    run_id="${3:-}"
    normalized_records | jq -c --arg run "$run_id" '.[]
      | select(.record_type == "metrics")
      | select(($run == "") or (.run_id == $run))'
    ;;

  append-metrics-once)
    raw="${3:-}"
    [ -n "$raw" ] || { echo "retrospective-ledger: metrics JSON is required" >&2; exit 2; }
    line="$(printf '%s\n' "$raw" | jq -ce '
      select(.record_type == "metrics")
      | select((.record_id | type) == "string" and (.record_id | length) > 0)
      | select((.run_id | type) == "string" and (.run_id | length) > 0)
      | select((.snapshot_id | type) == "string" and (.snapshot_id | length) > 0)
      | select((.revision | type) == "number" and .revision >= 1 and .revision == (.revision | floor))
    ')" || { echo "retrospective-ledger: invalid metrics record" >&2; exit 2; }
    record_id="$(printf '%s\n' "$line" | jq -r .record_id)"
    run_id="$(printf '%s\n' "$line" | jq -r .run_id)"
    existing="$(normalized_records | jq -c --arg id "$record_id" '[.[] | select(.record_id == $id)]')"
    existing_count="$(printf '%s\n' "$existing" | jq 'length')"
    if [ "$existing_count" -gt 0 ]; then
      [ "$existing_count" -eq 1 ] || {
        echo "retrospective-ledger: duplicate record_id '$record_id'" >&2
        exit 1
      }
      existing_line="$(printf '%s\n' "$existing" | jq -cS '.[0]')"
      requested_line="$(printf '%s\n' "$line" | jq -cS '.')"
      [ "$existing_line" = "$requested_line" ] || {
        echo "retrospective-ledger: record_id '$record_id' has conflicting content" >&2
        exit 1
      }
      printf '%s\n' "$line"
      exit 0
    fi
    active_count="$(active_records "$run_id" | jq 'length')"
    [ "$active_count" -eq 0 ] || {
      echo "retrospective-ledger: run '$run_id' already has an active metrics record" >&2
      exit 1
    }
    max_revision="$(normalized_records | jq -r --arg run "$run_id" '
      [.[] | select(.record_type == "metrics" and .run_id == $run)
        | select((.revision | type) == "number")
        | select(.revision >= 1 and .revision == (.revision | floor))
        | .revision]
      | max // 0
    ')"
    expected_revision=$((max_revision + 1))
    requested_revision="$(printf '%s\n' "$line" | jq -r .revision)"
    [ "$requested_revision" -eq "$expected_revision" ] || {
      echo "retrospective-ledger: run '$run_id' expected revision $expected_revision, got $requested_revision" >&2
      exit 1
    }
    append_json_line "$line"
    printf '%s\n' "$line"
    ;;

  supersede-once)
    raw="${3:-}"
    [ -n "$raw" ] || { echo "retrospective-ledger: supersede JSON is required" >&2; exit 2; }
    line="$(printf '%s\n' "$raw" | jq -ce '
      select(.record_type == "supersede")
      | select((.event_id | type) == "string" and (.event_id | length) > 0)
      | select((.run_id | type) == "string" and (.run_id | length) > 0)
      | select((.supersedes | type) == "string" and (.supersedes | length) > 0)
      | select(.reason == "run_resumed" or .reason == "legacy_migration")
    ')" || { echo "retrospective-ledger: invalid supersede record" >&2; exit 2; }
    event_id="$(printf '%s\n' "$line" | jq -r .event_id)"
    run_id="$(printf '%s\n' "$line" | jq -r .run_id)"
    target_id="$(printf '%s\n' "$line" | jq -r .supersedes)"
    reason="$(printf '%s\n' "$line" | jq -r .reason)"
    existing="$(normalized_records | jq -c --arg id "$event_id" '[.[] | select(.event_id == $id)]')"
    existing_count="$(printf '%s\n' "$existing" | jq 'length')"
    if [ "$existing_count" -gt 0 ]; then
      [ "$existing_count" -eq 1 ] || {
        echo "retrospective-ledger: duplicate event_id '$event_id'" >&2
        exit 1
      }
      existing_line="$(printf '%s\n' "$existing" | jq -cS '.[0]')"
      requested_line="$(printf '%s\n' "$line" | jq -cS '.')"
      [ "$existing_line" = "$requested_line" ] || {
        echo "retrospective-ledger: event_id '$event_id' has conflicting content" >&2
        exit 1
      }
      printf '%s\n' "$line"
      exit 0
    fi
    target_count="$(normalized_records | jq -r --arg id "$target_id" --arg run "$run_id" \
      '[.[] | select(.record_type == "metrics" and .record_id == $id and .run_id == $run)] | length')"
    [ "$target_count" -eq 1 ] || {
      echo "retrospective-ledger: superseded record '$target_id' was not found exactly once for run '$run_id'" >&2
      exit 1
    }
    if [ "$reason" = legacy_migration ]; then
      legacy_target_count="$(normalized_records | jq -r --arg id "$target_id" --arg run "$run_id" \
        '[.[] | select(.record_type == "metrics" and .record_id == $id and .run_id == $run)
          | select((.revision | type) != "number")] | length')"
      [ "$legacy_target_count" -eq 1 ] || {
        echo "retrospective-ledger: legacy_migration may supersede only an unversioned metrics record" >&2
        exit 1
      }
    fi
    already_superseded="$(normalized_records | jq -r --arg id "$target_id" '[.[] | select(.record_type == "supersede" and .supersedes == $id)] | length')"
    [ "$already_superseded" -eq 0 ] || {
      echo "retrospective-ledger: record '$target_id' is already superseded" >&2
      exit 1
    }
    append_json_line "$line"
    printf '%s\n' "$line"
    ;;

  *)
    echo "retrospective-ledger: unknown command '$command_name'" >&2
    exit 2
    ;;
esac
