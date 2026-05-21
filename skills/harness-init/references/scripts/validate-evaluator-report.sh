#!/usr/bin/env bash
# validate-evaluator-report.sh — Evaluator report の schema と evidence を検証する。

set -euo pipefail

REPORT=""
NARRATIVE=""
SPRINT_DIR=""
REPORT_DIR=""
PHASE=""
STRICT=0
SCHEMA_VERSION=1

usage() {
  cat <<'EOF' >&2
Usage: validate-evaluator-report.sh --report <path> --narrative <path> --sprint-dir <path> --report-dir <path> --phase <negotiation|impl> [--strict]
EOF
  exit 2
}

json_array_from_lines() {
  jq -R -s 'split("\n") | map(select(length > 0))'
}

write_missing_report() {
  local reason="report-missing:${REPORT}"
  mkdir -p "$(dirname "$REPORT")"
  jq -n --arg reason "$reason" '{
    schema_version: 1,
    validator_invoked: true,
    status: "fail",
    phases_executed: [],
    validator_violations: [$reason],
    forced_failure_reason: $reason,
    phase_3_evidence_status: "n/a"
  }' > "$REPORT"
  jq -n --arg reason "$reason" '{
    schema_version: 1,
    validator_invoked: true,
    validator_violations: [$reason],
    forced_status: "fail",
    forced_failure_reason: $reason,
    phase_3_evidence_status: "n/a"
  }'
  printf 'validate-evaluator-report: %s\n' "$reason" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --report) REPORT="$2"; shift 2 ;;
    --narrative) NARRATIVE="$2"; shift 2 ;;
    --sprint-dir) SPRINT_DIR="$2"; shift 2 ;;
    --report-dir) REPORT_DIR="$2"; shift 2 ;;
    --phase) PHASE="$2"; shift 2 ;;
    --strict) STRICT=1; shift ;;
    *) usage ;;
  esac
done

[ -n "$REPORT" ] || usage
[ -n "$NARRATIVE" ] || usage
[ -n "$SPRINT_DIR" ] || usage
[ -n "$REPORT_DIR" ] || usage
[ -n "$PHASE" ] || usage

[ -f "$REPORT" ] || write_missing_report

existing_violations_json="$(jq -c '.validator_violations // null' "$REPORT" 2>/dev/null || printf 'null')"
existing_p3_status="$(jq -r '.phase_3_evidence_status // "n/a"' "$REPORT" 2>/dev/null || printf 'n/a')"
if [ "$existing_violations_json" != "null" ] && [ -n "$existing_violations_json" ]; then
  existing_count="$(printf '%s' "$existing_violations_json" | jq -r 'length')"
  if [ "$existing_count" -gt 0 ]; then
    reason="$(printf '%s' "$existing_violations_json" | jq -r 'join(",")')"
    jq --argjson schema_version "$SCHEMA_VERSION" '
      .validator_invoked = true
      | .schema_version = $schema_version
    ' "$REPORT" > "${REPORT}.tmp" && mv "${REPORT}.tmp" "$REPORT"
    jq -c --argjson v "$existing_violations_json" --arg reason "$reason" --arg p3 "$existing_p3_status" '{
      schema_version: 1,
      validator_invoked: true,
      validator_violations: $v,
      forced_status: "fail",
      forced_failure_reason: $reason,
      phase_3_evidence_status: $p3
    }'
    printf 'validate-evaluator-report: reusing existing validator_violations\n' >&2
    exit 1
  fi
fi

violations=()

authored_p3_status="$(jq -r 'if has("phase_3_evidence_status") then (.phase_3_evidence_status // "null") else "" end' "$REPORT" 2>/dev/null || printf '')"
if [ -n "$authored_p3_status" ] && ! printf '%s' "$authored_p3_status" | grep -Eq '^(present|missing|n/a)$'; then
  violations+=("phase-3-evidence-status-invalid:${authored_p3_status}")
fi

status="$(jq -r '.status // "null"' "$REPORT")"
if [ "$status" = "null" ] || ! printf '%s' "$status" | grep -Eq '^(pass|fail)$'; then
  violations+=("status-invalid:${status}")
fi

if ! jq -e '.phases_executed | type == "array"' "$REPORT" >/dev/null 2>&1; then
  phases=""
  for required in 1 2 2.5 3 4; do
    violations+=("phase-missing:${required}")
  done
else
  phases="$(jq -r '.phases_executed[]?' "$REPORT" | sort -u | tr '\n' ' ')"
  for required in 1 2 2.5 3 4; do
    if ! printf '%s' "$phases" | grep -Eq "(^| )${required}( |$)"; then
      violations+=("phase-missing:${required}")
    fi
  done
fi

quality_gate_found="$(jq -r '.phase_2_5_quality_gate_found // true' "$REPORT" 2>/dev/null || printf 'true')"
if [ "$quality_gate_found" != "false" ]; then
  if ! jq -e '.phase_2_5_commands | type == "array" and length > 0' "$REPORT" >/dev/null 2>&1; then
    violations+=("phase-2.5-commands-missing")
  elif jq -e '.phase_2_5_commands[]? | select((.exit // 1) != 0)' "$REPORT" >/dev/null 2>&1; then
    violations+=("project-quality-gate-failed")
  fi
fi

if [ "$PHASE" = "impl" ] && [ ! -f "$NARRATIVE" ]; then
  violations+=("narrative-missing:${NARRATIVE}")
fi

if printf '%s' "$phases" | grep -Eq '(^| )3( |$)'; then
  evidence_found=0
  if find "${SPRINT_DIR}/evidence" -type f \( \
    -name '*.png' -o -name '*.jsonl' -o -name '*.json' -o \
    -name '*.spec.ts' -o -name '*.test.ts' -o -name '*.log' -o \
    -name '*.txt' -o -name '*.md' \
  \) 2>/dev/null | grep -q .; then
    evidence_found=1
  fi
  if [ "$evidence_found" -eq 0 ] && find "${REPORT_DIR}/.playwright-mcp" -type f -name '*.png' 2>/dev/null | grep -q .; then
    evidence_found=1
  fi
  if [ "$evidence_found" -eq 0 ]; then
    while IFS= read -r ref; do
      if [ -f "$ref" ] || [ -f "${SPRINT_DIR%/}/$ref" ] || [ -f "${REPORT_DIR%/}/$ref" ]; then
        evidence_found=1
        break
      fi
    done < <(jq -r '.evidence_refs[]?' "$REPORT" 2>/dev/null)
  fi
  if [ "$evidence_found" -eq 1 ]; then
    phase3_status="present"
  else
    phase3_status="missing"
    violations+=("phase-3-evidence-missing")
  fi
else
  phase3_status="n/a"
fi

violations_json="$(printf '%s\n' "${violations[@]}" | json_array_from_lines)"
if [ "${#violations[@]}" -gt 0 ]; then
  reason="$(printf '%s' "$violations_json" | jq -r 'join(",")')"
  [ "$STRICT" -eq 0 ] || jq . "$REPORT" >&2
  jq --argjson v "$violations_json" --arg reason "$reason" --arg p3 "$phase3_status" --argjson schema_version "$SCHEMA_VERSION" '
    .status = "fail"
    | .validator_invoked = true
    | .schema_version = $schema_version
    | .validator_violations = $v
    | .forced_failure_reason = $reason
    | .phase_3_evidence_status = $p3
  ' "$REPORT" > "${REPORT}.tmp" && mv "${REPORT}.tmp" "$REPORT"
  jq -n --argjson v "$violations_json" --arg reason "$reason" --arg p3 "$phase3_status" '{
    schema_version: 1,
    validator_invoked: true,
    validator_violations: $v,
    forced_status: "fail",
    forced_failure_reason: $reason,
    phase_3_evidence_status: $p3
  }'
  printf 'validate-evaluator-report: violations=%s\n' "$reason" >&2
  exit 1
fi

jq --arg p3 "$phase3_status" --argjson schema_version "$SCHEMA_VERSION" '
  .validator_invoked = true
  | .schema_version = $schema_version
  | .validator_violations = []
  | .phase_3_evidence_status = $p3
' "$REPORT" > "${REPORT}.tmp" && mv "${REPORT}.tmp" "$REPORT"
jq -n --arg p3 "$phase3_status" '{
  schema_version: 1,
  validator_invoked: true,
  validator_violations: [],
  forced_status: null,
  phase_3_evidence_status: $p3
}'
