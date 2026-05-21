#!/usr/bin/env bash
set -euo pipefail

STATE="${1:-.harness/_state.json}"
CONFIG="${HARNESS_CONFIG:-.harness/_config.yml}"

command -v jq >/dev/null || { echo "jq required" >&2; exit 2; }
[[ -f $STATE ]] || { echo "state file missing: $STATE" >&2; exit 2; }

yget() {
  { grep -E "^$1:" "$CONFIG" 2>/dev/null | head -1 | awk -F': *' '{print $2}' | tr -d '"' | tr -d "'"; } || true
}

if [ "$(yget tracker)" = "none" ]; then
  printf 'check-sprint-prs-complete: tracker=none; skipping PR invariant\n'
  exit 0
fi

completed="$(jq -r '.completed // false' "$STATE")"
phase="$(jq -r '.phase // ""' "$STATE")"
current_sprint="$(jq -r '.current_sprint // 0' "$STATE")"
[ "$current_sprint" -gt 0 ] 2>/dev/null || {
  printf 'check-sprint-prs-complete: no current_sprint; nothing to check\n'
  exit 0
}

missing=()
for (( i = 1; i <= current_sprint; i++ )); do
  if ! jq -e --arg key "$i" '(.sprint_prs[$key] // "") | type == "string" and length > 0' "$STATE" >/dev/null; then
    missing+=("$i")
  fi
done

if [ "${#missing[@]}" -gt 0 ] && { [ "$completed" = "true" ] || [ "$phase" = "done" ]; }; then
  printf 'check-sprint-prs-complete: completed/done state is missing sprint_prs entries: %s\n' "${missing[*]}" >&2
  exit 1
fi

printf 'check-sprint-prs-complete: ok\n'
