#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/.." && pwd)"
REFERENCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCHESTRATE_DIR="$(cd "$REFERENCE_DIR/.." && pwd)"
SKILLS_DIR="$(cd "$ORCHESTRATE_DIR/.." && pwd)"
FIXTURE="$TEST_DIR/fixtures/dispatch-matrix.tsv"
ROLE_DISPATCH="$REFERENCE_DIR/role-dispatch.md"
ROLE_DISPATCH_JA="$REFERENCE_DIR/role-dispatch.ja.md"
IMPLEMENT_GUIDE="$SKILLS_DIR/spec-implement/references/implement-guide.md"
IMPLEMENT_GUIDE_JA="$SKILLS_DIR/spec-implement/references/implement-guide.ja.md"
EVALUATE_BACKEND="$SKILLS_DIR/spec-evaluate/references/execution-backend.md"
EVALUATE_BACKEND_JA="$SKILLS_DIR/spec-evaluate/references/execution-backend.ja.md"
STATE_CHECK="$SCRIPT_DIR/pipeline-state-check.sh"

fail() {
  printf 'FAIL\t%s\n' "$*" >&2
  exit 1
}

resolve_backend() {
  local host="$1" role="$2"
  case "$host" in claude|codex) ;; *) return 2 ;; esac
  case "$role" in claude|codex) ;; *) return 2 ;; esac
  if [ "$host" = "$role" ]; then
    printf 'runtime-native\t-\n'
  else
    printf 'agent-delegate\t%s\n' "$role"
  fi
}

extract_matrix() {
  awk -F '|' '
    /<!-- dispatch-matrix:start -->/ { inside=1; next }
    /<!-- dispatch-matrix:end -->/ { inside=0 }
    inside && $2 ~ /`(claude|codex)`/ {
      for (i=2; i<=5; i++) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i)
        gsub(/`/, "", $i)
      }
      print $2 "\t" $3 "\t" $4 "\t" $5
    }
  ' "$1"
}

validate_fixture() {
  local file="$1" host role backend target actual
  while IFS=$'\t' read -r host role backend target; do
    [ "$host" = host_runtime ] && continue
    actual="$(resolve_backend "$host" "$role")" || return 1
    [ "$actual" = "$backend"$'\t'"$target" ] || return 1
  done < "$file"
}

tmp="$(mktemp -d "${TMPDIR:-/tmp}/host-aware-dispatch.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
expected="$(tail -n +2 "$FIXTURE")"
for matrix_file in \
  "$ROLE_DISPATCH" "$ROLE_DISPATCH_JA" \
  "$IMPLEMENT_GUIDE" "$IMPLEMENT_GUIDE_JA" \
  "$EVALUATE_BACKEND" "$EVALUATE_BACKEND_JA"; do
  [ "$(extract_matrix "$matrix_file")" = "$expected" ] ||
    fail "$matrix_file matrix differs from tracked fixture"
done

validate_fixture "$FIXTURE" || fail "tracked fixture contains an invalid positive row"

while IFS=$'\t' read -r host role backend target; do
  [ "$host" = host_runtime ] && continue
  actual="$(resolve_backend "$host" "$role")" ||
    fail "positive row rejected: $host/$role"
  [ "$actual" = "$backend"$'\t'"$target" ] ||
    fail "positive row mismatch: $host/$role expected $backend/$target got $actual"
  printf 'PASS\tpositive\t%s/%s\t%s/%s\n' "$host" "$role" "$backend" "$target"

  if [ "$backend" = runtime-native ]; then
    bad_backend=agent-delegate
    bad_target="$role"
  else
    bad_backend=runtime-native
    bad_target=-
  fi
  bad_fixture="$tmp/reversed-$host-$role.tsv"
  awk -F '\t' -v OFS='\t' -v h="$host" -v r="$role" \
    -v b="$bad_backend" -v t="$bad_target" \
    'NR > 1 && $1 == h && $2 == r {$3 = b; $4 = t} {print}' \
    "$FIXTURE" > "$bad_fixture"
  if validate_fixture "$bad_fixture"; then
    fail "validator accepted reversed row: $host/$role as $bad_backend/$bad_target"
  fi
  printf 'PASS\tnegative\t%s/%s rejects %s/%s\n' \
    "$host" "$role" "$bad_backend" "$bad_target"
done < "$FIXTURE"

if resolve_backend unknown codex >/dev/null 2>&1; then
  fail "unknown host runtime was accepted"
fi
if resolve_backend codex unknown >/dev/null 2>&1; then
  fail "unknown AI role was accepted"
fi

grep -q -- '--host-runtime' "$SKILLS_DIR/spec-implement/SKILL.md" ||
  fail "spec-implement does not require host-runtime"
grep -q -- '--host-runtime' "$SKILLS_DIR/spec-evaluate/SKILL.md" ||
  fail "spec-evaluate does not accept host-runtime"
grep -q 'host_runtime' "$ORCHESTRATE_DIR/SKILL.md" ||
  fail "spec-orchestrate does not record host_runtime"
grep -q 'reviewer role first' "$ROLE_DISPATCH" ||
  fail "reviewer inversion is not ordered before backend resolution"
grep -q 'Reviewer AI role' "$ROLE_DISPATCH_JA" ||
  fail "Japanese reviewer inversion contract is missing"

mkdir -p "$tmp/spec"
cat > "$tmp/spec/pipeline-state.json" <<'JSON'
{
  "feature": "fixture",
  "mode": "auto",
  "issue": 96,
  "language": "en",
  "host_runtime": "codex",
  "phase": "pr",
  "completed_phases": [
    "intake", "spec_generate", "inspect", "spec_review", "approval",
    "implement", "evaluate"
  ],
  "rounds": {},
  "threads": {},
  "role_overrides": {},
  "arbitrations": []
}
JSON
bash "$STATE_CHECK" "$tmp/spec" >/dev/null ||
  fail "state checker rejected recorded host_runtime"
jq '.host_runtime = "unknown"' "$tmp/spec/pipeline-state.json" > "$tmp/bad.json"
mv "$tmp/bad.json" "$tmp/spec/pipeline-state.json"
if bash "$STATE_CHECK" "$tmp/spec" >/dev/null 2>&1; then
  fail "state checker accepted unknown host_runtime"
fi

printf 'PASS\tcontract\thost-aware dispatch matrix and consumers\n'
