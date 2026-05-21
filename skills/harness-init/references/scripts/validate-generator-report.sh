#!/usr/bin/env bash
# validate-generator-report.sh — Generator report の schema と本文を検証する。

set -euo pipefail

REPORT=""
NARRATIVE=""
REPORT_DIR=""
PHASE=""
SCHEMA_VERSION=1

usage() {
  cat <<'EOF' >&2
Usage: validate-generator-report.sh --report <path> --narrative <path> --report-dir <path> --phase <negotiation|impl>
EOF
  exit 2
}

json_array_from_lines() {
  jq -R -s 'split("\n") | map(select(length > 0))'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --report) REPORT="$2"; shift 2 ;;
    --narrative) NARRATIVE="$2"; shift 2 ;;
    --report-dir) REPORT_DIR="$2"; shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$REPORT" ] || usage
[ -n "$NARRATIVE" ] || usage
[ -n "$REPORT_DIR" ] || usage
[ -n "$PHASE" ] || usage

if [ ! -f "$REPORT" ]; then
  mkdir -p "$(dirname "$REPORT")"
  jq -n --arg reason "report-missing:${REPORT}" '{
    schema_version: 1,
    validator_invoked: true,
    status: "blocked",
    touchedFiles: [],
    summary: "(blocked: report missing)",
    validator_violations: [$reason],
    forced_blocker_reason: $reason
  }' > "$REPORT"
fi

existing_violations_json="$(jq -c '.validator_violations // null' "$REPORT" 2>/dev/null || printf 'null')"
if [ "$existing_violations_json" != "null" ] && [ -n "$existing_violations_json" ]; then
  existing_count="$(printf '%s' "$existing_violations_json" | jq -r 'length')"
  existing_status="$(jq -r '.status // "blocked"' "$REPORT")"
  if [ "$existing_count" -gt 0 ]; then
    reason="$(printf '%s' "$existing_violations_json" | jq -r 'join(",")')"
    jq --argjson schema_version "$SCHEMA_VERSION" '
      .validator_invoked = true
      | .schema_version = $schema_version
    ' "$REPORT" > "${REPORT}.tmp" && mv "${REPORT}.tmp" "$REPORT"
    jq -c --argjson v "$existing_violations_json" --arg st "$existing_status" --arg reason "$reason" '{
      schema_version: 1,
      validator_invoked: true,
      validator_violations: $v,
      forced_status: $st,
      forced_blocker_reason: $reason,
      forced_fallback_reason: $reason
    }'
    printf 'validate-generator-report: reusing existing validator_violations\n' >&2
    exit 1
  fi
fi

violations=()

status="$(jq -r '.status // "null"' "$REPORT")"
if [ "$status" = "null" ] || ! printf '%s' "$status" | grep -Eq '^(done|blocked|fallback)$'; then
  violations+=("status-invalid:${status}")
fi

if ! jq -e '.touchedFiles | type == "array"' "$REPORT" >/dev/null 2>&1; then
  violations+=("touchedFiles-invalid")
fi

summary="$(jq -r '.summary // ""' "$REPORT")"
if [ -z "$summary" ]; then
  violations+=("summary-empty")
fi

if [ ! -f "$NARRATIVE" ]; then
  violations+=("narrative-missing:${NARRATIVE}")
fi

violations_json="$(printf '%s\n' "${violations[@]}" | json_array_from_lines)"
if [ "${#violations[@]}" -gt 0 ]; then
  has_narrative_missing=0
  has_other=0
  for violation in "${violations[@]}"; do
    case "$violation" in
      narrative-missing:*) has_narrative_missing=1 ;;
      *) has_other=1 ;;
    esac
  done

  if [ "$has_narrative_missing" -eq 1 ] && [ "$has_other" -eq 0 ]; then
    forced_status="fallback"
    mkdir -p "$(dirname "$NARRATIVE")"
    {
      printf '%s\n' '---'
      printf '%s\n' 'role: generator'
      printf '%s\n' 'forced_fallback_reason: narrative-missing'
      printf '%s\n\n' '---'
      printf '%s\n' '(fallback: validate-generator-report.sh synthesised placeholder narrative)'
    } > "$NARRATIVE"
  else
    forced_status="blocked"
  fi

  reason="$(printf '%s' "$violations_json" | jq -r 'join(",")')"
  if [ "$forced_status" = "fallback" ]; then
    jq --argjson v "$violations_json" --arg st "$forced_status" --arg reason "$reason" --argjson schema_version "$SCHEMA_VERSION" '
      .status = $st
      | .validator_invoked = true
      | .schema_version = $schema_version
      | .validator_violations = $v
      | .forced_fallback_reason = $reason
    ' "$REPORT" > "${REPORT}.tmp" && mv "${REPORT}.tmp" "$REPORT"
  else
    jq --argjson v "$violations_json" --arg st "$forced_status" --arg reason "$reason" --argjson schema_version "$SCHEMA_VERSION" '
      .status = $st
      | .validator_invoked = true
      | .schema_version = $schema_version
      | .validator_violations = $v
      | .forced_blocker_reason = $reason
    ' "$REPORT" > "${REPORT}.tmp" && mv "${REPORT}.tmp" "$REPORT"
  fi
  jq -n --argjson v "$violations_json" --arg st "$forced_status" '{
    schema_version: 1,
    validator_invoked: true,
    validator_violations: $v,
    forced_status: $st
  }'
  printf 'validate-generator-report: violations=%s\n' "$reason" >&2
  exit 1
fi

jq --argjson schema_version "$SCHEMA_VERSION" '
  .validator_invoked = true
  | .schema_version = $schema_version
  | .validator_violations = []
' "$REPORT" > "${REPORT}.tmp" && mv "${REPORT}.tmp" "$REPORT"
jq -n '{ schema_version: 1, validator_invoked: true, validator_violations: [], forced_status: null }'
