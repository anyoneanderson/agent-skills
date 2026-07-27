#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../../../../.." && pwd)"
FIXTURE_DIR="$TEST_DIR/fixtures/requirement-boundaries"
GENERATOR="$REPO_ROOT/skills/spec-generator"
INSPECT="$REPO_ROOT/skills/spec-inspect"
ORCHESTRATE="$REPO_ROOT/skills/spec-orchestrate"
PR_ASSEMBLY="$ORCHESTRATE/references/pr-assembly.md"
PR_ASSEMBLY_JA="$ORCHESTRATE/references/pr-assembly.ja.md"

fail() {
  printf 'FAIL\t%s\n' "$*" >&2
  exit 1
}

require_text() {
  local file="$1" text="$2" label="$3"
  grep -Fq -- "$text" "$file" || fail "$label: missing '$text' in $file"
  printf 'PASS\tcontract\t%s\n' "$label"
}

inspect_fixture() {
  local file="$1" language="$2"
  awk -v language="$language" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      return value
    }
    function placeholder(value, lowered) {
      value = trim(value)
      lowered = tolower(value)
      return lowered == "none" || lowered == "tbd" || lowered == "n/a" ||
        value == "なし" || value == "未定" || value == "該当なし" ||
        value == "..." || value == "…"
    }
    function finish_requirement() {
      if (requirement_id != "" && !(criteria_label && criteria_item)) {
        print "missing_acceptance:" requirement_id
      }
      requirement_id = ""
      criteria_label = 0
      criteria_item = 0
    }
    function is_scope_heading(line, lowered) {
      lowered = tolower(line)
      if (language == "en") {
        return lowered ~ /^##[[:space:]]+([0-9]+\.?[[:space:]]+)?(out of scope|non-goals)[[:space:]]*$/
      }
      return line ~ /^##[[:space:]]*([0-9]+\.?[[:space:]]+)?(非目標|対象外)[[:space:]]*$/
    }
    {
      line = $0
      sub(/\r$/, "", line)

      if (is_scope_heading(line)) {
        scope_found = 1
        in_scope = 1
        in_requirement_section = 0
        next
      }
      if (in_scope && line ~ /^##[[:space:]]+/) {
        in_scope = 0
      }
      if (in_scope && line ~ /^[[:space:]]*[-*+][[:space:]]+/) {
        item = line
        sub(/^[[:space:]]*[-*+][[:space:]]+/, "", item)
        if (!placeholder(item)) scope_item = 1
      }

      if (line ~ /^##[[:space:]]+/) {
        finish_requirement()
        lowered = tolower(line)
        if (language == "en") in_requirement_section = lowered ~ /(functional|non-functional) requirements/
        else in_requirement_section = line ~ /(機能要件|非機能要件)/
      }
      if (in_requirement_section && match(line, /^[[:space:]]*(###[[:space:]]+)?\[(REQ|NFR)-[0-9][0-9]*\]/)) {
        finish_requirement()
        requirement_id = substr(line, RSTART, RLENGTH)
        sub(/^.*\[/, "", requirement_id)
        sub(/\].*$/, "", requirement_id)
        next
      }
      if (requirement_id != "") {
        normalized = line
        gsub(/\*\*/, "", normalized)
        lowered = tolower(normalized)
        if (language == "en") label_at = match(lowered, /acceptance criteria[[:space:]]*:/)
        else label_at = match(normalized, /受入条件[[:space:]]*(：|:)/)
        if (label_at) {
          criteria_label = 1
          inline_item = substr(normalized, RSTART + RLENGTH)
          sub(/^[[:space:]]+/, "", inline_item)
          if (inline_item != "" && !placeholder(inline_item)) criteria_item = 1
          next
        }
        if (criteria_label && line ~ /^[[:space:]]*[-*+][[:space:]]+/) {
          item = line
          sub(/^[[:space:]]*[-*+][[:space:]]+/, "", item)
          sub(/^\[[ xX]\][[:space:]]*/, "", item)
          if (!placeholder(item)) criteria_item = 1
        }
      }
    }
    END {
      finish_requirement()
      if (!scope_found) print "missing_scope"
      else if (!scope_item) print "empty_scope"
    }
  ' "$file" | LC_ALL=C sort
}

assert_case() {
  local name="$1" language="$2" expected="$3" actual
  actual="$(inspect_fixture "$FIXTURE_DIR/$name.md" "$language")"
  if [ "$actual" != "$expected" ]; then
    fail "$name expected '$expected', got '$actual'"
  fi
  printf 'PASS\tfixture\t%s\n' "$name"
}

require_text "$GENERATOR/SKILL.md" "Confirm inferred non-goals, then generate" "quick mode confirms non-goals"
require_text "$GENERATOR/references/init.md" 'in an AskUserQuestion requirements round' "dialogue mode collects non-goals interactively"
require_text "$GENERATOR/references/init.md" "## 6. Out of Scope" "English template has Out of Scope"
require_text "$GENERATOR/references/init.md" "Acceptance Criteria:" "English template has acceptance criteria"
require_text "$GENERATOR/references/init.ja.md" "## 6. 非目標" "Japanese template has non-goals"
require_text "$GENERATOR/references/init.ja.md" "受入条件：" "Japanese template has acceptance criteria"
require_text "$GENERATOR/references/auto-mode.md" "never leave the section empty" "English auto mode enforces non-empty boundary"
require_text "$GENERATOR/references/auto-mode.ja.md" "非目標を空にしたり" "Japanese auto mode enforces non-empty boundary"
require_text "$INSPECT/SKILL.md" "requirement-boundary-check.md" "inspect invokes boundary contract"
require_text "$ORCHESTRATE/references/phases/spec_review.md" "rejected: out_of_scope" "English review rejection is recorded"
require_text "$ORCHESTRATE/references/phases/spec_review.ja.md" "rejected: out_of_scope" "Japanese review rejection is recorded"
require_text "$ORCHESTRATE/references/phases/spec_review.md" "raw Gate" "English review preserves raw Gate"
require_text "$ORCHESTRATE/references/phases/spec_review.ja.md" "生のGate" "Japanese review preserves raw Gate"
require_text "$ORCHESTRATE/references/phases/spec_review.md" "Never expand Out of Scope" "English review cannot expand scope to dismiss findings"
require_text "$ORCHESTRATE/references/phases/spec_review.ja.md" "指摘を棄却するために非目標を後から広げてはならない" "Japanese review cannot expand scope to dismiss findings"
require_text "$ORCHESTRATE/references/phases/spec_review.md" 'Exclude rejected findings from effective `fix_required`' "English rejected findings leave the effective gate"
require_text "$ORCHESTRATE/references/phases/spec_review.ja.md" '棄却したfindingを有効な`fix_required`' "Japanese rejected findings leave the effective gate"
require_text "$ORCHESTRATE/references/phases/spec_review.md" 'request or Issue that sourced the spec' "English source conflicts bypass filtering"
require_text "$ORCHESTRATE/references/phases/spec_review.ja.md" '情報源となった依頼やIssueと衝突' "Japanese source conflicts bypass filtering"
require_text "$ORCHESTRATE/references/phases/spec_review.md" '`Scope Baseline`' "English review freezes non-goals"
require_text "$ORCHESTRATE/references/phases/spec_review.ja.md" '`スコープ基準`' "Japanese review freezes non-goals"
require_text "$PR_ASSEMBLY" '`rejected: out_of_scope`' "English PR exposes rejected findings"
require_text "$PR_ASSEMBLY_JA" '`rejected: out_of_scope`' "Japanese PR exposes rejected findings"

assert_case en-valid en ""
assert_case en-missing-out-of-scope en "missing_scope"
assert_case en-empty-out-of-scope en "empty_scope"
assert_case en-missing-req-acceptance en "missing_acceptance:REQ-001"
assert_case en-empty-acceptance en "missing_acceptance:REQ-001"
assert_case en-non-goals-alias-legacy en ""
assert_case ja-valid ja ""
assert_case ja-empty-acceptance ja "missing_acceptance:REQ-001"
assert_case ja-missing-nfr-acceptance ja "missing_acceptance:NFR-001"
assert_case ja-missing-out-of-scope ja "missing_scope"
assert_case ja-empty-out-of-scope ja "empty_scope"
assert_case ja-target-out-alias ja ""

printf 'PASS\tcontract\trequirement boundaries and acceptance criteria\n'
