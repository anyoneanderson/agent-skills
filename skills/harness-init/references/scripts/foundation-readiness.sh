#!/usr/bin/env bash
# foundation-readiness.sh — greenfield detection probe for /harness-plan Step 3.5
# and per-deliverable verifier for /harness-loop foundation-sprint protocol.
#
# Probe keys are unified with contract.deliverables (foundation-sprint-checklist.md)
# so that harness-loop can call `--check <deliverable_key>` directly without an
# alias table.
#
# Seven probes:
#   package_manifest          — language-appropriate manifest file exists
#   runtime_boots             — manifest has a dev/start script entry
#                               (static check only; actual boot left to AS-1 of
#                               sprint 1 or to Sprint 0's runtime verification)
#   test_runner_configured    — config file for the chosen evaluator_tools exists
#   env_example_committed     — .env.example / equivalent covers required secrets
#   external_setup_doc        — SETUP.md / docs/setup.md or similar exists
#   tracker_wired             — `gh auth status` (when tracker=github)
#   dev_db_available          — docker-compose or local DB file when DB is
#                               declared in Constraints
#
# Usage:
#   foundation-readiness.sh --epic <epic-slug>        # full assessment, writes report
#   foundation-readiness.sh --check <probe-key>       # single probe, exit 0 = ok, 1 = missing, 2 = unknown
#
# Full assessment writes `.harness/<epic>/foundation-readiness.md` and prints a
# JSON line to stdout:
#   {"severity":"GREEN|YELLOW|RED","missing":["pkg","runtime",...],"ok":[...]}
#
# Input for probes comes from _config.yml (tracker, evaluator_tools) and
# `.harness/<epic>/product-spec.md` (Constraints) when present. The script is
# best-effort: each probe returns ok/missing/unknown and the caller interprets.
#
# Legacy key aliases (accepted by --check for backward compat, removed in v2):
#   runtime_command   → runtime_boots
#   test_runner       → test_runner_configured
#   external_creds    → env_example_committed
#   persistence_layer → dev_db_available

set -euo pipefail

mode="${1:-}"
arg="${2:-}"
STATE_FILE=".harness/_state.json"
CONFIG_FILE=".harness/_config.yml"

usage() {
  cat >&2 <<EOF
usage: $0 --epic <epic-slug>
       $0 --check <probe-key>
probes: package_manifest runtime_boots test_runner_configured
        env_example_committed external_setup_doc tracker_wired
        dev_db_available
EOF
  exit 64
}

[ "$mode" = "--epic" ] || [ "$mode" = "--check" ] || usage
[ -n "$arg" ] || usage

# ---------- helpers ----------
yget() {
  grep -E "^$1:" "$CONFIG_FILE" 2>/dev/null | head -1 | awk -F': *' '{print $2}' | tr -d '"' || true
}

have_file() { [ -f "$1" ]; }
have_any()  { for f in "$@"; do [ -e "$f" ] && return 0; done; return 1; }

# Parse simple YAML list of evaluator_tools (one per line with leading `- `).
evaluator_tools_list() {
  awk '
    /^evaluator_tools:/ { in_list = 1; next }
    in_list && /^[^ -]/ { in_list = 0 }
    in_list && /^  *- / { gsub(/^  *- */, ""); gsub(/[",]/, ""); print }
  ' "$CONFIG_FILE" 2>/dev/null
}

product_spec_path() {
  local epic="$1"
  echo ".harness/$epic/product-spec.md"
}

spec_has_phrase() {
  local spec="$1"; shift
  [ -f "$spec" ] || return 1
  for p in "$@"; do
    grep -qiE "$p" "$spec" 2>/dev/null && return 0
  done
  return 1
}

# ---------- probes ----------
# Each probe prints one of: ok / missing / unknown and returns 0/1/2 exit code.

probe_package_manifest() {
  if have_any package.json pnpm-workspace.yaml pyproject.toml setup.py go.mod Cargo.toml Gemfile composer.json; then
    echo ok; return 0
  fi
  echo missing; return 1
}

probe_runtime_boots() {
  # Prefer not to execute commands (side effects); check for common manifest
  # with a dev/start script instead. Actual boot verification is left to the
  # user (AS-1 of the first normal sprint) or to Sprint 0's deliverables.
  if have_file package.json && grep -qE '"(dev|start)"[[:space:]]*:' package.json 2>/dev/null; then
    echo ok; return 0
  fi
  if have_file pyproject.toml && grep -qE '^\[project.scripts\]|^\[tool.poetry.scripts\]' pyproject.toml 2>/dev/null; then
    echo ok; return 0
  fi
  # No manifest → cannot tell.
  if have_any package.json pyproject.toml go.mod Cargo.toml; then
    echo missing; return 1
  fi
  echo unknown; return 2
}

probe_test_runner_configured() {
  local tools
  tools="$(evaluator_tools_list)"
  [ -z "$tools" ] && { echo unknown; return 2; }
  local any_match=0 any_missing=0
  while IFS= read -r tool; do
    [ -z "$tool" ] && continue
    case "$tool" in
      playwright|playwright-mcp|playwright-cli)
        if have_any playwright.config.ts playwright.config.js playwright.config.mjs; then
          any_match=1
        else
          any_missing=1
        fi
        ;;
      curl|custom|custom-script)
        # cannot reliably check; assume the project wires it up in sprint
        any_match=1
        ;;
    esac
  done <<<"$tools"
  [ "$any_missing" = "1" ] && { echo missing; return 1; }
  [ "$any_match"   = "1" ] && { echo ok; return 0; }
  echo unknown; return 2
}

probe_env_example_committed() {
  local spec
  spec="$(product_spec_path "${epic_slug:-}")"
  # If spec doesn't declare external auth needs, skip with ok.
  if [ -f "$spec" ] && ! spec_has_phrase "$spec" "oauth|api key|signing secret|client secret|anthropic_api_key|google_client|slack_signing"; then
    echo ok; return 0
  fi
  # Need .env.example (or analog) committed.
  if have_any .env.example .env.sample env.example config/env.example; then
    echo ok; return 0
  fi
  echo missing; return 1
}

probe_tracker_wired() {
  local tracker
  tracker="$(yget tracker)"
  case "$tracker" in
    github)
      command -v gh >/dev/null 2>&1 || { echo missing; return 1; }
      gh auth status >/dev/null 2>&1 || { echo missing; return 1; }
      echo ok; return 0
      ;;
    gitlab|none|"")
      echo ok; return 0
      ;;
    *)
      echo unknown; return 2
      ;;
  esac
}

probe_dev_db_available() {
  local spec
  spec="$(product_spec_path "${epic_slug:-}")"
  # If spec doesn't mention DB / ORM, skip with ok.
  if [ -f "$spec" ] && ! spec_has_phrase "$spec" "database|prisma|postgres|sqlite|mysql|mongodb|supabase|cloud sql|dynamodb"; then
    echo ok; return 0
  fi
  if have_any docker-compose.yml docker-compose.yaml prisma/schema.prisma db.sqlite dev.db; then
    echo ok; return 0
  fi
  echo missing; return 1
}

probe_external_setup_doc() {
  # Check for operator-facing setup instructions that document external
  # provider registration (GCP OAuth client, Slack app, etc.).
  if have_any SETUP.md docs/SETUP.md docs/setup.md README.md; then
    echo ok; return 0
  fi
  echo missing; return 1
}

run_probe() {
  case "$1" in
    package_manifest)        probe_package_manifest        ;;
    runtime_boots)           probe_runtime_boots           ;;
    test_runner_configured)  probe_test_runner_configured  ;;
    env_example_committed)   probe_env_example_committed   ;;
    external_setup_doc)      probe_external_setup_doc      ;;
    tracker_wired)           probe_tracker_wired           ;;
    dev_db_available)        probe_dev_db_available        ;;

    # Legacy key aliases (v1 compat; removed in v2).
    runtime_command)   probe_runtime_boots          ;;
    test_runner)       probe_test_runner_configured ;;
    external_creds)    probe_env_example_committed  ;;
    persistence_layer) probe_dev_db_available       ;;

    *) echo "unknown probe: $1" >&2; exit 64 ;;
  esac
}

# ---------- mode: --check (single probe) ----------
if [ "$mode" = "--check" ]; then
  run_probe "$arg"
  exit $?
fi

# ---------- mode: --epic (full assessment) ----------
epic_slug="$arg"
out_dir=".harness/$epic_slug"
[ -d "$out_dir" ] || { echo "epic dir not found: $out_dir" >&2; exit 65; }
report="$out_dir/foundation-readiness.md"

probes=(package_manifest runtime_boots test_runner_configured env_example_committed external_setup_doc tracker_wired dev_db_available)
declare -a ok_list=()
declare -a missing_list=()
declare -a unknown_list=()
verified_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  echo "# Foundation Readiness — $epic_slug"
  echo
  echo "Generated at $verified_at"
  echo
  echo "| Probe | Status |"
  echo "|---|---|"
} > "$report"

for p in "${probes[@]}"; do
  status="$(run_probe "$p" || true)"
  printf '| %s | %s |\n' "$p" "$status" >> "$report"
  case "$status" in
    ok)      ok_list+=("$p") ;;
    missing) missing_list+=("$p") ;;
    *)       unknown_list+=("$p") ;;
  esac
done

# Severity classification.
missing_count="${#missing_list[@]}"
has_manifest="ok"
for m in "${missing_list[@]}"; do [ "$m" = "package_manifest" ] && has_manifest="missing"; done
if [ "$has_manifest" = "missing" ] || [ "$missing_count" -ge 3 ]; then
  severity="RED"
elif [ "$missing_count" -ge 1 ]; then
  severity="YELLOW"
else
  severity="GREEN"
fi

{
  echo
  echo "**Severity: $severity**"
  echo
  if [ "${#missing_list[@]}" -gt 0 ]; then
    echo "## Missing probes"
    for m in "${missing_list[@]}"; do echo "- $m"; done
    echo
  fi
  if [ "${#unknown_list[@]}" -gt 0 ]; then
    echo "## Unknown probes (could not determine)"
    for m in "${unknown_list[@]}"; do echo "- $m"; done
    echo
  fi
} >> "$report"

# JSON line to stdout for orchestrator consumption.
jq -n \
  --arg severity "$severity" \
  --arg verified_at "$verified_at" \
  --argjson ok "$(printf '%s\n' "${ok_list[@]:-}" | jq -R . | jq -s .)" \
  --argjson missing "$(printf '%s\n' "${missing_list[@]:-}" | jq -R . | jq -s .)" \
  --argjson unknown "$(printf '%s\n' "${unknown_list[@]:-}" | jq -R . | jq -s .)" \
  '{severity:$severity, verified_at:$verified_at, ok:($ok|map(select(length>0))), missing:($missing|map(select(length>0))), unknown:($unknown|map(select(length>0)))}'
