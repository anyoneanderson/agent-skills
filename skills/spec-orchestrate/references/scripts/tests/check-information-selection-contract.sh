#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ORCHESTRATE_DIR="$(cd "$TEST_DIR/../../.." && pwd)"
REPO_ROOT="$(cd "$ORCHESTRATE_DIR/../.." && pwd)"
FIXTURE_DIR="$TEST_DIR/fixtures"
CONTRACT_FIXTURE="$FIXTURE_DIR/information-selection-contract.tsv"

fail() {
  printf 'FAIL\t%s\n' "$*" >&2
  exit 1
}

validate_contract_file() {
  local actual_file="$1" relative_file="$2" language="$3"
  local contract_id en_file en_token ja_file ja_token expected_file token found=0

  while IFS=$'\t' read -r contract_id en_file en_token ja_file ja_token; do
    [ "$contract_id" = contract_id ] && continue
    case "$language" in
      en) expected_file="$en_file"; token="$en_token" ;;
      ja) expected_file="$ja_file"; token="$ja_token" ;;
      *) return 1 ;;
    esac
    [ "$expected_file" = "$relative_file" ] || continue
    found=$((found + 1))
    grep -Fq -- "$token" "$actual_file" || return 1
  done < "$CONTRACT_FIXTURE"

  [ "$found" -gt 0 ]
}

assert_contract_matrix() {
  local contract_id en_file en_token ja_file ja_token

  awk -F '\t' '
    NR == 1 {
      if ($0 != "contract_id\ten_file\ten_token\tja_file\tja_token") exit 1
      next
    }
    NF != 5 || $1 == "" || $2 == "" || $3 == "" || $4 == "" || $5 == "" { exit 1 }
    seen[$1]++ > 0 { exit 1 }
    END { if (NR < 2) exit 1 }
  ' "$CONTRACT_FIXTURE" || fail "information-selection contract matrix is malformed"

  while IFS=$'\t' read -r contract_id en_file en_token ja_file ja_token; do
    [ "$contract_id" = contract_id ] && continue
    [ -f "$REPO_ROOT/$en_file" ] || fail "$contract_id English file is missing: $en_file"
    [ -f "$REPO_ROOT/$ja_file" ] || fail "$contract_id Japanese file is missing: $ja_file"
    grep -Fq -- "$en_token" "$REPO_ROOT/$en_file" ||
      fail "$contract_id English contract is missing"
    grep -Fq -- "$ja_token" "$REPO_ROOT/$ja_file" ||
      fail "$contract_id Japanese contract is missing"
  done < "$CONTRACT_FIXTURE"
}

assert_contract_mutations_rejected() {
  local tmp="$1" contract_id en_file en_token ja_file ja_token language
  local source_file relative_file token mutant

  while IFS=$'\t' read -r contract_id en_file en_token ja_file ja_token; do
    [ "$contract_id" = contract_id ] && continue
    for language in en ja; do
      if [ "$language" = en ]; then
        relative_file="$en_file"
        token="$en_token"
      else
        relative_file="$ja_file"
        token="$ja_token"
      fi
      source_file="$REPO_ROOT/$relative_file"
      mutant="$tmp/${contract_id}-${language}.md"
      awk -v token="$token" 'index($0, token) == 0 { print }' "$source_file" > "$mutant"
      if validate_contract_file "$mutant" "$relative_file" "$language"; then
        fail "$contract_id $language mutation survived"
      fi
    done
  done < "$CONTRACT_FIXTURE"
}

assert_template_headings() {
  local template="$1" body="$2" heading
  while IFS= read -r heading; do
    [ -n "$heading" ] || continue
    grep -Fqx -- "$heading" "$body" || return 1
  done < "$template"
}

assert_pr_examples() {
  local before="$FIXTURE_DIR/pr-body-before.md"
  local selected="$FIXTURE_DIR/pr-body-selected.md"
  local template="$FIXTURE_DIR/project-pr-template.md"
  local forbidden before_lines selected_lines

  grep -Fq -- 'Issue #162 dogfood edit history, anonymized structural reproduction.' "$before" ||
    fail "PR before fixture lacks anonymized dogfood provenance"
  grep -Fq -- 'Issue #162 dogfood edit history, anonymized structural reproduction.' "$selected" ||
    fail "selected PR fixture lacks anonymized dogfood provenance"

  for forbidden in '## Adversarial Review History' '## Acceptance Evidence' '### Evidence Manifest'; do
    grep -Fqx -- "$forbidden" "$before" || fail "PR before fixture lacks $forbidden"
    if grep -Fqx -- "$forbidden" "$selected"; then
      fail "selected PR fixture retained run-record section $forbidden"
    fi
  done

  assert_template_headings "$template" "$selected" ||
    fail "selected PR fixture does not preserve the project PR template"
  grep -Fq -- 'workerが処理と保存を行う方式へ変更しました' "$selected" ||
    fail "selected PR fixture lacks the design rationale"
  grep -Fq -- '共有エラー転送も修正しました' "$selected" ||
    fail "selected PR fixture lacks the easy-to-miss shared impact"
  grep -Fq -- '認証情報は#57で配線します' "$selected" ||
    fail "selected PR fixture lacks the deferred Issue link"
  grep -Fq -- '現在の実装レビューは進められます' "$selected" ||
    fail "selected PR fixture lacks the deferred finding landing rationale"
  grep -Fq -- '順に確認してください' "$selected" ||
    fail "selected PR fixture lacks review focus"

  before_lines="$(wc -l < "$before" | tr -d '[:space:]')"
  selected_lines="$(wc -l < "$selected" | tr -d '[:space:]')"
  [ "$before_lines" -gt "$selected_lines" ] ||
    fail "PR fixtures do not reproduce before/after information selection"
}

assert_issue_examples() {
  local source="$FIXTURE_DIR/issue-spec-tasks.md"
  local copied="$FIXTURE_DIR/issue-body-copied.md"
  local selected="$FIXTURE_DIR/issue-body-selected.md"
  local template="$FIXTURE_DIR/project-issue-template.md"
  local templated="$FIXTURE_DIR/issue-body-project-template.md"
  local task task_count=0 copied_count=0 selected_count=0

  while IFS= read -r task; do
    task="${task#\#\#\# }"
    task_count=$((task_count + 1))
    grep -Fq -- "$task" "$copied" && copied_count=$((copied_count + 1))
    grep -Fq -- "$task" "$selected" && selected_count=$((selected_count + 1))
  done < <(grep '^### T[0-9]' "$source")

  [ "$task_count" -ge 10 ] || fail "tasks-rich source fixture is too small"
  [ "$copied_count" -eq "$task_count" ] || fail "copied Issue fixture does not reproduce tasks.md"
  [ "$selected_count" -eq 0 ] || fail "selected Issue fixture copied task headings"
  grep -Fqx -- '## 技術スタック' "$copied" || fail "copied Issue fixture lacks the technology copy"
  if grep -Fqx -- '## 技術スタック' "$selected"; then
    fail "selected Issue fixture copied the technology stack without a decision reason"
  fi

  for heading in '## 解決したい問題' '## 完了後の状態' '## 現在の挙動' \
    '## 期待する挙動' '## スコープ' '## 受入条件' '## 設計を拘束する決定' '## 未決事項'; do
    grep -Fqx -- "$heading" "$selected" || fail "selected Issue fixture lacks $heading"
  done

  assert_template_headings "$template" "$templated" ||
    fail "project Issue template headings were not preserved"
  if grep -Fqx -- '## 解決したい問題' "$templated"; then
    fail "project-templated Issue appended the built-in template"
  fi
}

assert_fixture_hygiene() {
  local fixture last_byte
  for fixture in \
    "$CONTRACT_FIXTURE" \
    "$FIXTURE_DIR/pr-body-before.md" \
    "$FIXTURE_DIR/pr-body-selected.md" \
    "$FIXTURE_DIR/project-pr-template.md" \
    "$FIXTURE_DIR/issue-spec-tasks.md" \
    "$FIXTURE_DIR/issue-body-copied.md" \
    "$FIXTURE_DIR/issue-body-selected.md" \
    "$FIXTURE_DIR/project-issue-template.md" \
    "$FIXTURE_DIR/issue-body-project-template.md"; do
    last_byte="$(tail -c 1 "$fixture" | od -An -t u1 | tr -d '[:space:]')"
    [ "$last_byte" = 10 ] || fail "$fixture must end with a newline"
  done

  if grep -Eiq -- 'value-market|smb-dx|dev-insights|pull/405|PR #405|#322' \
    "$FIXTURE_DIR"/*.md; then
    fail "public information-selection fixtures contain dogfood repository identifiers"
  fi
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/information-selection-contract.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

assert_contract_matrix
assert_contract_mutations_rejected "$tmp"
assert_pr_examples
assert_issue_examples
assert_fixture_hygiene

printf 'PASS\tcontract\tPR and Issue information selection\n'
