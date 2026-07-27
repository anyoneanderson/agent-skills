#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/../.." && pwd)"

fail() {
  printf 'SKILL_REFERENCE_SPLIT_FAIL\t%s\n' "$*" >&2
  exit 1
}

check_pair() {
  local skill="$1" reference="$2" en_marker="$3" ja_marker="$4" en_secondary="$5" ja_secondary="$6"
  local skill_file="$REPO_ROOT/skills/$skill/SKILL.md"
  local en_file="$REPO_ROOT/skills/$skill/references/$reference.md"
  local ja_file="$REPO_ROOT/skills/$skill/references/$reference.ja.md"
  local en_h2 ja_h2 lines

  grep -Fq "references/$reference.md" "$skill_file" || fail "$skill does not link $reference.md"
  [ -f "$en_file" ] || fail "$skill is missing $reference.md"
  [ -f "$ja_file" ] || fail "$skill is missing $reference.ja.md"
  grep -Fq "$en_marker" "$en_file" || fail "$reference.md is missing $en_marker"
  grep -Fq "$ja_marker" "$ja_file" || fail "$reference.ja.md is missing $ja_marker"
  grep -Fq "$en_secondary" "$en_file" || fail "$reference.md is missing $en_secondary"
  grep -Fq "$ja_secondary" "$ja_file" || fail "$reference.ja.md is missing $ja_secondary"
  en_h2="$(grep -c '^## ' "$en_file" || true)"
  ja_h2="$(grep -c '^## ' "$ja_file" || true)"
  [ "$en_h2" -eq "$ja_h2" ] || fail "$reference heading count differs: en=$en_h2 ja=$ja_h2"
  lines="$(wc -l < "$skill_file" | tr -d ' ')"
  [ "$lines" -le 450 ] || fail "$skill has $lines lines; expected at most 450"
  printf 'SKILL_REFERENCE_SPLIT_OK\t%s\t%s\n' "$skill" "$reference"
}

check_pair spec-workflow-init agent-and-pipeline-setup 'pipeline-watchdog.sh' 'pipeline-watchdog.sh' '`--force`' '`--force`'
check_pair harness-loop completion-and-transition 'pending_worker_exit' 'pending_worker_exit' 'git push -u origin' 'git push -u origin'
check_pair harness-init installation-integration 'settings-merge.md' 'settings-merge.ja.md' 'never touch' '触れない'
check_pair spec-generator yagni-guardrails 'AskUserQuestion' 'AskUserQuestion' 'Requested or Discussed' '明示または対話'
check_pair harness-plan usage-and-approval 'TODO(epic-split)' 'TODO(epic-split)' 'single' '1回の呼び出し'
check_pair spec-inspect extended-quality-checks 'Check 19' 'Check 19' 'is not tracked by git' 'is not tracked by git'

printf 'SKILL_REFERENCE_SPLIT_SUMMARY\tPASS\t6\n'
