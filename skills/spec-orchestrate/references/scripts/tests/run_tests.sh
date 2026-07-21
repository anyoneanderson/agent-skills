#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/.." && pwd)"
REFERENCE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ORCHESTRATE_DIR="$(cd "$REFERENCE_DIR/.." && pwd)"
SKILLS_DIR="$(cd "$ORCHESTRATE_DIR/.." && pwd)"
FIXTURE="$TEST_DIR/fixtures/dispatch-matrix.tsv"
REVIEW_FIXTURE="$TEST_DIR/fixtures/review-fallback.tsv"
SPEC_REVIEW_RECOVERY_FIXTURE="$TEST_DIR/fixtures/spec-review-env-error-contract.tsv"
ROLE_DISPATCH="$REFERENCE_DIR/role-dispatch.md"
ROLE_DISPATCH_JA="$REFERENCE_DIR/role-dispatch.ja.md"
IMPLEMENT_PHASE="$REFERENCE_DIR/phases/implement.md"
SPEC_REVIEW_PHASE="$REFERENCE_DIR/phases/spec_review.md"
SPEC_REVIEW_PHASE_JA="$REFERENCE_DIR/phases/spec_review.ja.md"
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

resolve_reviewer() {
  local host="$1" preferred="$2" peer_available="$3"
  local native_available="$4" policy="$5"
  case "$host" in claude|codex) ;; *) return 2 ;; esac
  case "$preferred" in claude|codex) ;; *) return 2 ;; esac
  case "$peer_available" in yes|no) ;; *) return 2 ;; esac
  case "$native_available" in yes|no) ;; *) return 2 ;; esac
  case "$policy" in block|native-independent) ;; *) return 2 ;; esac

  if [ "$preferred" = "$host" ]; then
    if [ "$native_available" = yes ]; then
      printf 'preferred\t%s\truntime-native\n' "$preferred"
    else
      printf 'blocked\t-\t-\n'
    fi
  elif [ "$peer_available" = yes ]; then
    printf 'preferred\t%s\tagent-delegate\n' "$preferred"
  elif [ "$policy" = native-independent ] && [ "$native_available" = yes ]; then
    printf 'fallback\t%s\truntime-native\n' "$host"
  else
    printf 'blocked\t-\t-\n'
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

extract_spec_review_recovery_contract() {
  awk '
    /<!-- spec-review-env-error-recovery:start -->/ { inside=1; next }
    /<!-- spec-review-env-error-recovery:end -->/ { inside=0 }
    inside { print }
  ' "$1"
}

validate_spec_review_recovery_contract() {
  local file="$1" language="$2" field contract_id en_token ja_token token section

  [ "$(grep -c '<!-- spec-review-env-error-recovery:start -->' "$file")" -eq 1 ] || return 1
  [ "$(grep -c '<!-- spec-review-env-error-recovery:end -->' "$file")" -eq 1 ] || return 1
  section="$(extract_spec_review_recovery_contract "$file")"
  [ -n "$section" ] || return 1

  case "$language" in
    en) field=2 ;;
    ja) field=3 ;;
    *) return 1 ;;
  esac

  while IFS=$'\t' read -r contract_id en_token ja_token; do
    [ "$contract_id" = contract_id ] && continue
    if [ "$field" -eq 2 ]; then token="$en_token"; else token="$ja_token"; fi
    printf '%s\n' "$section" | grep -Fq -- "$token" || return 1
  done < "$SPEC_REVIEW_RECOVERY_FIXTURE"
}

assert_spec_review_recovery_mutations_rejected() {
  local file="$1" language="$2" field contract_id en_token ja_token token mutant

  case "$language" in
    en) field=2 ;;
    ja) field=3 ;;
    *) return 1 ;;
  esac

  while IFS=$'\t' read -r contract_id en_token ja_token; do
    [ "$contract_id" = contract_id ] && continue
    if [ "$field" -eq 2 ]; then token="$en_token"; else token="$ja_token"; fi
    mutant="$tmp/spec-review-recovery-$language-$contract_id.md"
    awk -v token="$token" 'index($0, token) == 0 { print }' "$file" > "$mutant"
    if validate_spec_review_recovery_contract "$mutant" "$language"; then
      printf 'SURVIVED_MUTATION\t%s\t%s\n' "$language" "$contract_id" >&2
      return 1
    fi
  done < "$SPEC_REVIEW_RECOVERY_FIXTURE"
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

while IFS=$'\t' read -r host preferred peer_available native_available policy outcome actual backend; do
  [ "$host" = host_runtime ] && continue
  resolved="$(resolve_reviewer "$host" "$preferred" "$peer_available" "$native_available" "$policy")" ||
    fail "review fallback row rejected: $host/$preferred/$policy"
  expected_review="$outcome"$'\t'"$actual"$'\t'"$backend"
  [ "$resolved" = "$expected_review" ] ||
    fail "review fallback mismatch: expected $expected_review got $resolved"
  printf 'PASS\treview-fallback\t%s/%s\t%s/%s\n' "$host" "$policy" "$outcome" "$backend"
done < "$REVIEW_FIXTURE"

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
grep -q -- '--review-fallback' "$SKILLS_DIR/spec-implement/SKILL.md" ||
  fail "spec-implement does not expose the explicit review fallback policy"
grep -q 'native-independent' "$SKILLS_DIR/spec-implement/SKILL.md" ||
  fail "spec-implement does not define the native-independent policy"
grep -q -- '--review-fallback native-independent' "$ROLE_DISPATCH" ||
  fail "spec-orchestrate does not opt into independent native review"
grep -q -- '--review-fallback native-independent' "$IMPLEMENT_PHASE" ||
  fail "implement phase does not pass the independent review policy"
grep -q 'native-independent' "$SPEC_REVIEW_PHASE" ||
  fail "spec_review phase does not apply the independent review policy"
grep -q 'fresh runtime-native reviewer subagent' "$ROLE_DISPATCH" ||
  fail "independent reviewer instance contract is missing"
grep -q 'state.review_fallbacks' "$ROLE_DISPATCH" ||
  fail "review fallback state recording contract is missing"

validate_spec_review_recovery_contract "$SPEC_REVIEW_PHASE" en ||
  fail "English spec_review env_error recovery contract is incomplete"
validate_spec_review_recovery_contract "$SPEC_REVIEW_PHASE_JA" ja ||
  fail "Japanese spec_review env_error recovery contract is incomplete"
assert_spec_review_recovery_mutations_rejected "$SPEC_REVIEW_PHASE" en ||
  fail "English spec_review recovery validator accepted a contract mutation"
assert_spec_review_recovery_mutations_rejected "$SPEC_REVIEW_PHASE_JA" ja ||
  fail "Japanese spec_review recovery validator accepted a contract mutation"
printf 'PASS\tcontract\tspec_review env_error artifact recovery\n'

for fixture_file in "$FIXTURE" "$REVIEW_FIXTURE" "$SPEC_REVIEW_RECOVERY_FIXTURE"; do
  last_byte="$(tail -c 1 "$fixture_file" | od -An -t u1 | tr -d '[:space:]')"
  [ "$last_byte" = 10 ] || fail "$fixture_file must end with a newline"
done

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
  "review_fallbacks": [
    {
      "phase": "implement",
      "artifact": "T001",
      "round": 1,
      "host_runtime": "codex",
      "preferred_role": "claude",
      "actual_role": "codex",
      "backend": "runtime-native",
      "reason": "peer_unavailable",
      "independence": "fresh_subagent"
    }
  ],
  "arbitrations": []
}
JSON
cp "$tmp/spec/pipeline-state.json" "$tmp/valid-state.json"
bash "$STATE_CHECK" "$tmp/spec" >/dev/null ||
  fail "state checker rejected valid host and review fallback"
jq 'del(.review_fallbacks)' "$tmp/valid-state.json" > "$tmp/spec/pipeline-state.json"
bash "$STATE_CHECK" "$tmp/spec" >/dev/null ||
  fail "state checker rejected a backward-compatible state without review_fallbacks"
jq '.host_runtime = "claude"' "$tmp/valid-state.json" > "$tmp/spec/pipeline-state.json"
bash "$STATE_CHECK" "$tmp/spec" >/dev/null ||
  fail "state checker coupled historical review fallback to the current resume host"
jq '.host_runtime = "unknown"' "$tmp/valid-state.json" > "$tmp/bad.json"
mv "$tmp/bad.json" "$tmp/spec/pipeline-state.json"
if bash "$STATE_CHECK" "$tmp/spec" >/dev/null 2>&1; then
  fail "state checker accepted unknown host_runtime"
fi

jq '.review_fallbacks[0].independence = "shared_context"' \
  "$tmp/valid-state.json" > "$tmp/spec/pipeline-state.json"
if bash "$STATE_CHECK" "$tmp/spec" >/dev/null 2>&1; then
  fail "state checker accepted a shared-context reviewer fallback"
fi

jq '.review_fallbacks[0].host_runtime = "claude"' \
  "$tmp/valid-state.json" > "$tmp/spec/pipeline-state.json"
if bash "$STATE_CHECK" "$tmp/spec" >/dev/null 2>&1; then
  fail "state checker accepted a fallback reviewer that differed from its historical host"
fi

printf 'PASS\tcontract\thost-aware dispatch and independent review fallback\n'
