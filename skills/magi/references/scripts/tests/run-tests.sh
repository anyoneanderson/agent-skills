#!/usr/bin/env bash
# run-tests.sh — behaviour tests for magi-run.sh, driven by fake sages.
#
# Every case dispatches to sages whose CLI is a stock command (`sh`, `cat`,
# `sleep`), so the suite proves the mechanics of the dispatcher — parallel
# launch, hard timeout, failure isolation, config resolution, argv hygiene —
# without calling a real model CLI, an account or the network. Judging the
# content of an answer belongs to the host (CON-002) and is out of scope here.
#
# The fixtures, each documented further in its own `notes` fields:
#   sages-ok.json             three sages covering both prompt delivery modes
#                             (stdin, {PROMPT_FILE}) and all three extract rules
#                             (jq filter, answer-file, raw)
#   sages-parallel.json       three sages that each wait a second
#   sages-timeout.json        a sage that never answers, timeout_seconds 2
#   sages-error.json          a sage that writes stderr and exits 3
#   sages-bad-envelope.json   a sage that exits 0 with an unextractable answer
#   sages-missing-cli.json    a sage whose command is not installed
#   sages-override.json       TESTSAGE, a name no other config uses
#   sages-argv-probe.json     a sage that reports its own argv, then echoes stdin
#   sages-prompt-in-argv.json invalid on purpose: uses the withdrawn {PROMPT}
#
# Keep fixture timeouts small: a bug that hangs a sage should cost this suite
# seconds, not the ten minutes the real council allows.
#
# Usage: bash run-tests.sh      (works from the repository root or from tests/)
# Exit:  0 = every case passed | 1 = a case failed | 2 = the harness cannot run
#
# Run directories are kept on purpose: a failure is only diagnosable with the
# sage stdout/stderr and the summary.json it produced. Their root is printed at
# the start and at the end of the run.

set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$TEST_DIR/.." && pwd)"
SCRIPT="$SCRIPT_DIR/magi-run.sh"
BUNDLED_SAGES="$SCRIPT_DIR/sages.default.json"
FIXTURES="$TEST_DIR/fixtures"

# magi-run.sh resolves its config from the environment and the home directory,
# so an override left on the developer's machine must not decide what these
# cases see. Each case states the config it wants through RUN_CONFIG.
unset MAGI_SAGES_FILE

harness_error() { printf 'run-tests: %s\n' "$*" >&2; exit 2; }

[ -f "$SCRIPT" ] || harness_error "magi-run.sh not found at ${SCRIPT}"
[ -d "$FIXTURES" ] || harness_error "fixture directory not found at ${FIXTURES}"
for required in jq perl; do
  command -v "$required" >/dev/null 2>&1 ||
    harness_error "${required} is required to run these tests but is not on PATH"
done

WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/magi-tests.XXXXXX")"
# Resolved once, so a path this suite builds compares equal to the path
# magi-run.sh prints after its own `cd` (the macOS temp root is a symlink).
WORK_ROOT="$(cd "$WORK_ROOT" && pwd -P)"

PASS_COUNT=0
FAIL_COUNT=0
CASE_NAME=""
CASE_START=0
CASE_LOG="${WORK_ROOT}/.case-log"
# Filled in by the happy-path case and reported at the end: the acceptance plan
# (test.md T-A02 / T-A06) inspects these artifacts by hand.
OK_OUT_DIR=""
OK_SUMMARY=""

# BSD date has no sub-second format, so perl owns the clock here as it does in
# magi-run.sh.
now_ms() { perl -MTime::HiRes=time -e 'printf "%.0f\n", time() * 1000'; }

# --- case bookkeeping ------------------------------------------------------

begin_case() {
  CASE_NAME="$1"
  : > "$CASE_LOG"
  CASE_START="$(now_ms)"
}

note_failure() { printf 'FAIL %s\n' "$*" >> "$CASE_LOG"; }
note_info() { printf 'info %s\n' "$*" >> "$CASE_LOG"; }

end_case() {
  local elapsed failed line
  elapsed=$(( $(now_ms) - CASE_START ))
  failed="$(grep -c '^FAIL ' "$CASE_LOG" || true)"
  if [ "$failed" -gt 0 ]; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf 'FAIL  %s (%s ms)\n' "$CASE_NAME" "$elapsed"
  else
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'PASS  %s (%s ms)\n' "$CASE_NAME" "$elapsed"
  fi
  while IFS= read -r line; do
    printf '        %s\n' "${line#* }"
  done < "$CASE_LOG"
}

case_dir() {
  local dir="${WORK_ROOT}/$1"
  mkdir -p "$dir"
  printf '%s' "$dir"
}

# --- assertions ------------------------------------------------------------

expect_rc() { # <expected> <actual> <label>
  [ "$2" = "$1" ] || note_failure "$3: expected exit ${1}, got ${2}"
}

expect_value() { # <expected> <actual> <label>
  [ "$2" = "$1" ] || note_failure "$3: expected '${1}', got '${2}'"
}

expect_json() { # <file> <jq filter> <label>
  if [ ! -f "$1" ]; then
    note_failure "$3: file missing: $1"
    return 0
  fi
  jq -e "$2" "$1" >/dev/null 2>&1 || note_failure "$3 (unmet in $1: $2)"
}

expect_file() { # <path> <label>
  [ -f "$1" ] || note_failure "$2: file missing: $1"
}

expect_absent() { # <path> <label>
  [ ! -e "$1" ] || note_failure "$2: path should not exist: $1"
}

expect_contains() { # <file> <text> <label>
  if [ ! -f "$1" ]; then
    note_failure "$3: file missing: $1"
    return 0
  fi
  grep -Fq -- "$2" "$1" || note_failure "$3: '${2}' not found in $1"
}

expect_text_has() { # <text> <needle> <label>
  case "$1" in
    *"$2"*) : ;;
    *) note_failure "$3: '${2}' not found in '${1}'" ;;
  esac
}

expect_text_lacks() { # <text> <needle> <label>
  case "$1" in
    *"$2"*) note_failure "$3: '${2}' must not appear in '${1}'" ;;
    *) : ;;
  esac
}

# --- running the script under test -----------------------------------------

# Per-invocation environment. Set what a case needs immediately before run_magi;
# run_magi clears all three afterwards so a setting cannot leak into the next
# case.
RUN_CONFIG=""  # MAGI_SAGES_FILE ("" leaves it unset, exercising the search path)
RUN_CWD=""     # working directory (config search looks at ./.magi/sages.json)
RUN_HOME=""    # HOME (config search looks at ~/.magi/sages.json)

RUN_RC=0
RUN_OUT=""
RUN_ERR=""
RUN_LAST_LINE=""

run_magi() { # <case dir> <args...>
  local dir="$1"
  shift
  RUN_OUT="${dir}/magi.out"
  RUN_ERR="${dir}/magi.err"
  RUN_RC=0
  (
    [ -z "$RUN_CWD" ] || cd "$RUN_CWD"
    [ -z "$RUN_HOME" ] || export HOME="$RUN_HOME"
    [ -z "$RUN_CONFIG" ] || export MAGI_SAGES_FILE="$RUN_CONFIG"
    exec bash "$SCRIPT" "$@"
  ) > "$RUN_OUT" 2> "$RUN_ERR" || RUN_RC=$?
  RUN_LAST_LINE="$(tail -n 1 "$RUN_OUT")"
  RUN_CONFIG=""
  RUN_CWD=""
  RUN_HOME=""
}

sage_field() { # <summary.json> <sage name> <field>
  jq -r --arg name "$2" --arg field "$3" \
    '.sages[] | select(.name == $name) | .[$field]' "$1"
}

# The summary.json contract from design.md §4, asserted as one filter so a
# missing or mistyped field is reported wherever a case produces a summary.
SUMMARY_CONTRACT='
  (.round | type) == "string"
  and (.prompt_file | type) == "string"
  and (.sages | length) > 0
  and all(.sages[];
        (.name | type) == "string"
        and (.cli | type) == "string"
        and (.status | IN("ok", "timeout", "error"))
        and (.exit_code | type) == "number"
        and (.duration_ms | type) == "number" and .duration_ms >= 0
        and (.answer | type) == "string"
        and (.stdout_file | type) == "string"
        and (.stderr_file | type) == "string"
        and (.prompt_file | type) == "string"
        and ((.status == "ok") == (.answer | length > 0)))'

# --- cases -----------------------------------------------------------------

case_sources_parse() {
  begin_case "the script and every fixture parse when the suite starts"
  local fixture
  bash -n "$SCRIPT" 2>>"$CASE_LOG" || note_failure "magi-run.sh has a syntax error"
  # macOS ships bash 3.2 as /bin/bash while $PATH usually finds a newer one;
  # checking both keeps the script honest about its stated target (CON-003).
  if [ -x /bin/bash ]; then
    /bin/bash -n "$SCRIPT" 2>>"$CASE_LOG" ||
      note_failure "magi-run.sh does not parse under /bin/bash"
  fi
  for fixture in "$FIXTURES"/sages-*.json; do
    jq -e . "$fixture" >/dev/null 2>&1 || note_failure "fixture is not valid JSON: $fixture"
  done
  expect_file "$BUNDLED_SAGES" "bundled sage config"
  end_case
}

case_three_ok_answers() {
  begin_case "summary.json collects three ok answers when every sage responds"
  local dir out round marker summary name
  dir="$(case_dir happy-path)"
  out="${dir}/out"
  round="${out}/round1"
  marker="MAGI-HAPPY-MARKER"
  # The prompt lives inside the run directory, the way the host is told to keep
  # it, so this case doubles as the audit-trail fixture (NFR-003).
  mkdir -p "$round"
  printf 'Question %s: which option should we take?\n' "$marker" > "${round}/prompt.md"

  RUN_CONFIG="${FIXTURES}/sages-ok.json"
  run_magi "$dir" --prompt-file "${round}/prompt.md" --out-dir "$out" --round round1

  summary="${round}/summary.json"
  expect_rc 0 "$RUN_RC" "dispatch"
  expect_value "$summary" "$RUN_LAST_LINE" "last stdout line is the summary path"
  expect_json "$summary" "$SUMMARY_CONTRACT" "summary.json follows the contract"
  expect_json "$summary" '.round == "round1"' "round label is recorded"
  expect_json "$summary" '[.sages[].name] == ["ECHOSAGE", "FILESAGE", "ANSWERSAGE"]' \
    "sage rows keep config order"
  expect_json "$summary" 'all(.sages[]; .status == "ok")' "every sage is ok"
  expect_json "$summary" 'all(.sages[]; .exit_code == 0)' "every sage exited 0"
  # Each sage answers with the prompt it received, so the marker proves delivery
  # reached all three shapes: stdin, {PROMPT_FILE} and {ANSWER_FILE}.
  expect_json "$summary" "all(.sages[]; .answer | contains(\"${marker}\"))" \
    "every answer carries the prompt marker"
  for name in ECHOSAGE FILESAGE ANSWERSAGE; do
    expect_file "${round}/${name}.stdout" "${name} stdout is kept"
    expect_file "${round}/${name}.stderr" "${name} stderr is kept"
  done
  expect_file "${out}/preflight.json" "preflight.json is written on a normal run"
  expect_absent "${round}/.summary-parts.jsonl" "summary scratch file is removed"
  expect_absent "${round}/.ECHOSAGE.meta" "sage meta file is removed"
  expect_absent "${out}/.preflight-parts.jsonl" "preflight scratch file is removed"

  OK_OUT_DIR="$out"
  OK_SUMMARY="$summary"
  end_case
}

case_parallel_dispatch() {
  begin_case "a round finishes in under three seconds when three sages each wait one second"
  local dir out summary started elapsed
  dir="$(case_dir parallel)"
  out="${dir}/out"
  printf 'Waiting sages, please answer.\n' > "${dir}/prompt.md"

  RUN_CONFIG="${FIXTURES}/sages-parallel.json"
  started="$(now_ms)"
  run_magi "$dir" --prompt-file "${dir}/prompt.md" --out-dir "$out" --round round1
  elapsed=$(( $(now_ms) - started ))

  summary="${out}/round1/summary.json"
  expect_rc 0 "$RUN_RC" "dispatch"
  expect_json "$summary" 'all(.sages[]; .status == "ok")' "every waiting sage is ok"
  # Sequential execution costs at least three seconds. Each sage must still show
  # its own second of waiting, otherwise a fixture that stopped sleeping would
  # pass this case for the wrong reason.
  expect_json "$summary" 'all(.sages[]; .duration_ms >= 1000)' "each sage really waited a second"
  note_info "wall clock: ${elapsed} ms for three one-second sages"
  [ "$elapsed" -lt 3000 ] ||
    note_failure "round took ${elapsed} ms; three parallel one-second sages must finish in under 3000 ms"
  end_case
}

case_timeout_status() {
  begin_case "status is timeout when a sage runs past timeout_seconds"
  local dir out summary
  dir="$(case_dir timeout)"
  out="${dir}/out"
  printf 'A sage that never answers.\n' > "${dir}/prompt.md"

  RUN_CONFIG="${FIXTURES}/sages-timeout.json"
  run_magi "$dir" --prompt-file "${dir}/prompt.md" --out-dir "$out" --round round1

  summary="${out}/round1/summary.json"
  expect_rc 0 "$RUN_RC" "dispatch still succeeds"
  expect_json "$summary" "$SUMMARY_CONTRACT" "summary.json follows the contract"
  expect_value timeout "$(sage_field "$summary" STUCKSAGE status)" "stuck sage status"
  # 128 + SIGALRM: the perl wrapper's alarm reached the sage process itself.
  expect_value 142 "$(sage_field "$summary" STUCKSAGE exit_code)" "stuck sage exit code"
  expect_value "" "$(sage_field "$summary" STUCKSAGE answer)" "stuck sage answer is empty"
  expect_contains "${out}/round1/STUCKSAGE.stderr" "exceeded the 2 second timeout" \
    "the run directory explains the timeout"
  expect_value ok "$(sage_field "$summary" QUICKSAGE status)" "the fast sage is still collected"
  end_case
}

case_error_isolation() {
  begin_case "status is error and the other sage is still collected when a sage exits non-zero"
  local dir out summary marker
  dir="$(case_dir error)"
  out="${dir}/out"
  marker="MAGI-ERROR-MARKER"
  printf 'Question %s\n' "$marker" > "${dir}/prompt.md"

  RUN_CONFIG="${FIXTURES}/sages-error.json"
  run_magi "$dir" --prompt-file "${dir}/prompt.md" --out-dir "$out" --round round1

  summary="${out}/round1/summary.json"
  expect_rc 0 "$RUN_RC" "dispatch still succeeds"
  expect_json "$summary" "$SUMMARY_CONTRACT" "summary.json follows the contract"
  expect_value error "$(sage_field "$summary" BOOMSAGE status)" "failing sage status"
  expect_value 3 "$(sage_field "$summary" BOOMSAGE exit_code)" "failing sage exit code"
  expect_value "" "$(sage_field "$summary" BOOMSAGE answer)" "failing sage answer is empty"
  expect_contains "${out}/round1/BOOMSAGE.stderr" "boom" "the failing sage's stderr is kept"
  expect_value ok "$(sage_field "$summary" QUICKSAGE status)" "healthy sage status"
  expect_text_has "$(sage_field "$summary" QUICKSAGE answer)" "$marker" "healthy sage answer"
  end_case
}

case_unreadable_answer() {
  begin_case "status is error when the answer cannot be extracted from stdout"
  local dir out summary
  dir="$(case_dir bad-envelope)"
  out="${dir}/out"
  printf 'Plain text, not the JSON envelope the extract filter expects.\n' > "${dir}/prompt.md"

  RUN_CONFIG="${FIXTURES}/sages-bad-envelope.json"
  run_magi "$dir" --prompt-file "${dir}/prompt.md" --out-dir "$out" --round round1

  summary="${out}/round1/summary.json"
  expect_rc 0 "$RUN_RC" "dispatch still succeeds"
  expect_value error "$(sage_field "$summary" GARBLEDSAGE status)" "unreadable sage status"
  # Exit 0 with an unusable answer is the degraded case the host must see as a
  # failure, not as a silent empty opinion.
  expect_value 0 "$(sage_field "$summary" GARBLEDSAGE exit_code)" "unreadable sage exit code"
  expect_value "" "$(sage_field "$summary" GARBLEDSAGE answer)" "unreadable sage answer is empty"
  expect_contains "$RUN_ERR" "could not extract an answer" "the reason is reported on stderr"
  expect_file "${out}/round1/GARBLEDSAGE.stdout" "the raw output is kept for inspection"
  expect_value ok "$(sage_field "$summary" QUICKSAGE status)" "healthy sage status"
  end_case
}

case_preflight_missing_cli() {
  begin_case "preflight.json records the missing command when a sage cli is absent"
  local dir out preflight
  dir="$(case_dir preflight-missing)"
  out="${dir}/out"

  # The argument list mirrors acceptance case T-A03 so the two stay in step.
  RUN_CONFIG="${FIXTURES}/sages-missing-cli.json"
  run_magi "$dir" --preflight-only --out-dir "$out" --round preflight --prompt-file /dev/null

  preflight="${out}/preflight.json"
  # A missing CLI is data for the host's degraded-council question (REQ-009),
  # not a failure of the check itself.
  expect_rc 0 "$RUN_RC" "preflight-only"
  expect_value "$preflight" "$RUN_LAST_LINE" "last stdout line is the preflight path"
  expect_json "$preflight" '.missing == ["magi-no-such-cli"]' "the missing command is listed"
  expect_json "$preflight" '.jq_available == true' "jq is reported as available"
  expect_json "$preflight" '.available_count == 1' "one of two sages is available"
  expect_json "$preflight" \
    '(.sages[] | select(.name == "GONESAGE") | .available == false and .path == null)' \
    "the absent sage has no path"
  expect_json "$preflight" \
    '(.sages[] | select(.name == "HERESAGE") | .available == true and (.path | length) > 0)' \
    "the available sage records its path"
  expect_json "$preflight" '.timeout_seconds == 5' "the configured timeout is reported"
  expect_contains "$RUN_ERR" "sage commands not found on PATH" "the gap is also reported on stderr"
  expect_absent "${out}/preflight" "no round directory is created for a preflight-only run"
  end_case
}

case_refuses_missing_cli() {
  begin_case "dispatch is refused when a sage cli is absent"
  local dir out
  dir="$(case_dir refuse-missing)"
  out="${dir}/out"
  printf 'Nobody should be dispatched to.\n' > "${dir}/prompt.md"

  RUN_CONFIG="${FIXTURES}/sages-missing-cli.json"
  run_magi "$dir" --prompt-file "${dir}/prompt.md" --out-dir "$out" --round round1

  expect_rc 2 "$RUN_RC" "dispatch with a missing CLI"
  expect_contains "$RUN_ERR" "refusing to dispatch round 'round1'" "the refusal names the round"
  expect_file "${out}/preflight.json" "preflight.json is still written for the host"
  expect_absent "${out}/round1/summary.json" "no summary is written"
  end_case
}

case_env_override() {
  begin_case "summary.json names TESTSAGE when MAGI_SAGES_FILE points at the override config"
  local dir out summary
  dir="$(case_dir env-override)"
  out="${dir}/out"
  printf 'Override probe.\n' > "${dir}/prompt.md"

  RUN_CONFIG="${FIXTURES}/sages-override.json"
  run_magi "$dir" --prompt-file "${dir}/prompt.md" --out-dir "$out" --round round1

  summary="${out}/round1/summary.json"
  expect_rc 0 "$RUN_RC" "dispatch"
  expect_json "$summary" '[.sages[].name] == ["TESTSAGE"]' "only the override sage is dispatched"
  expect_json "$summary" 'all(.sages[]; .status == "ok")' "the override sage answers"
  expect_json "${out}/preflight.json" \
    ".sages_file == \"${FIXTURES}/sages-override.json\"" "preflight names the config it read"
  end_case
}

case_project_over_home_config() {
  begin_case "the project config is preferred over the home config when MAGI_SAGES_FILE is unset"
  local dir project home elsewhere
  dir="$(case_dir config-search)"
  project="${dir}/project"
  home="${dir}/home"
  elsewhere="${dir}/elsewhere"
  mkdir -p "${project}/.magi" "${home}/.magi" "$elsewhere"
  jq '.sages[0].name = "PROJECTSAGE"' "${FIXTURES}/sages-override.json" > "${project}/.magi/sages.json"
  jq '.sages[0].name = "HOMESAGE"' "${FIXTURES}/sages-override.json" > "${home}/.magi/sages.json"

  RUN_CWD="$project"
  RUN_HOME="$home"
  run_magi "$dir" --preflight-only --out-dir "${dir}/out-project"
  expect_rc 0 "$RUN_RC" "preflight from the project directory"
  expect_json "${dir}/out-project/preflight.json" \
    ".sages_file == \"${project}/.magi/sages.json\" and (.sages[0].name == \"PROJECTSAGE\")" \
    "./.magi/sages.json wins over the home config"

  # Same home, but a working directory without .magi: the next candidate in the
  # search order must take over.
  RUN_CWD="$elsewhere"
  RUN_HOME="$home"
  run_magi "$dir" --preflight-only --out-dir "${dir}/out-home"
  expect_rc 0 "$RUN_RC" "preflight from a directory without a project config"
  expect_json "${dir}/out-home/preflight.json" \
    ".sages_file == \"${home}/.magi/sages.json\" and (.sages[0].name == \"HOMESAGE\")" \
    "~/.magi/sages.json is used next"
  end_case
}

case_bundled_default_config() {
  begin_case "the bundled default config is used when no override exists"
  local dir home preflight
  dir="$(case_dir config-bundled)"
  home="${dir}/home"
  mkdir -p "$home"

  RUN_CWD="$dir"
  RUN_HOME="$home"
  run_magi "$dir" --preflight-only --out-dir "${dir}/out"

  preflight="${dir}/out/preflight.json"
  expect_rc 0 "$RUN_RC" "preflight with no override in place"
  expect_json "$preflight" ".sages_file == \"${BUNDLED_SAGES}\"" "the bundled config is read"
  # Availability is deliberately not asserted: whether claude / codex / grok are
  # installed on this machine says nothing about the resolution order.
  expect_json "$preflight" \
    '[.sages[].name] == ["MELCHIOR", "BALTHASAR", "CASPER"]' "the three default sages are checked"
  expect_json "$preflight" '.timeout_seconds == 600' "the default timeout is 600 seconds"
  end_case
}

case_rejects_prompt_in_argv() {
  begin_case "the config is rejected when a sage puts the prompt body in argv"
  local dir out
  dir="$(case_dir prompt-in-argv)"
  out="${dir}/out"
  printf 'Secret question that must never reach argv.\n' > "${dir}/prompt.md"

  RUN_CONFIG="${FIXTURES}/sages-prompt-in-argv.json"
  run_magi "$dir" --prompt-file "${dir}/prompt.md" --out-dir "$out" --round round1

  expect_rc 2 "$RUN_RC" "dispatch with a {PROMPT} placeholder"
  expect_contains "$RUN_ERR" "withdrawn {PROMPT} placeholder" "the reason names the placeholder"
  expect_absent "${out}/round1" "nothing is dispatched"
  end_case
}

case_per_sage_prompt() {
  begin_case "the per-sage prompt file is sent when the round directory holds prompt-<SAGE>.md"
  local dir out round summary shared personal
  dir="$(case_dir per-sage-prompt)"
  out="${dir}/out"
  round="${out}/debate1"
  shared="MAGI-SHARED-PROMPT"
  personal="MAGI-PERSONAL-PROMPT"
  mkdir -p "$round"
  printf 'Everyone reads this: %s\n' "$shared" > "${round}/prompt.md"
  printf 'Only FILESAGE reads this: %s\n' "$personal" > "${round}/prompt-FILESAGE.md"

  RUN_CONFIG="${FIXTURES}/sages-ok.json"
  run_magi "$dir" --prompt-file "${round}/prompt.md" --out-dir "$out" --round debate1

  summary="${round}/summary.json"
  expect_rc 0 "$RUN_RC" "dispatch"
  expect_value "${round}/prompt-FILESAGE.md" "$(sage_field "$summary" FILESAGE prompt_file)" \
    "FILESAGE is recorded against its own prompt"
  expect_text_has "$(sage_field "$summary" FILESAGE answer)" "$personal" "FILESAGE answer"
  expect_text_lacks "$(sage_field "$summary" FILESAGE answer)" "$shared" "FILESAGE answer"
  expect_value "${round}/prompt.md" "$(sage_field "$summary" ECHOSAGE prompt_file)" \
    "ECHOSAGE keeps the shared prompt"
  expect_text_has "$(sage_field "$summary" ECHOSAGE answer)" "$shared" "ECHOSAGE answer"
  # The top-level prompt_file stays the shared one; per-sage overrides are
  # visible on each sage row.
  expect_json "$summary" ".prompt_file == \"${round}/prompt.md\"" "the round records the shared prompt"
  end_case
}

case_sages_filter() {
  begin_case "only the requested sages are dispatched when --sages is given"
  local dir out summary
  dir="$(case_dir sages-filter)"
  out="${dir}/out"
  printf 'Two of three sages, please.\n' > "${dir}/prompt.md"

  RUN_CONFIG="${FIXTURES}/sages-ok.json"
  # Written out of order and with a stray space, because the host builds this
  # list from its own tally and should not have to normalise it.
  run_magi "$dir" --prompt-file "${dir}/prompt.md" --out-dir "$out" --round round1 \
    --sages "ANSWERSAGE, ECHOSAGE"

  summary="${out}/round1/summary.json"
  expect_rc 0 "$RUN_RC" "dispatch"
  expect_json "$summary" '[.sages[].name] == ["ECHOSAGE", "ANSWERSAGE"]' \
    "the selection keeps config order"
  expect_json "$summary" 'all(.sages[]; .status == "ok")' "both selected sages answer"
  expect_absent "${out}/round1/FILESAGE.stdout" "the unselected sage is not run"
  end_case
}

case_unknown_sage_name() {
  begin_case "dispatch is refused when --sages names an unknown sage"
  local dir out
  dir="$(case_dir unknown-sage)"
  out="${dir}/out"
  printf 'Nobody by that name.\n' > "${dir}/prompt.md"

  RUN_CONFIG="${FIXTURES}/sages-ok.json"
  run_magi "$dir" --prompt-file "${dir}/prompt.md" --out-dir "$out" --round round1 --sages NOSUCHSAGE

  expect_rc 2 "$RUN_RC" "dispatch with an unknown sage name"
  expect_contains "$RUN_ERR" "unknown sage 'NOSUCHSAGE'" "the error names the unknown sage"
  expect_contains "$RUN_ERR" "configured sages are: ECHOSAGE, FILESAGE, ANSWERSAGE" \
    "the error lists the configured sages"
  expect_absent "${out}/round1/summary.json" "no summary is written"
  end_case
}

case_schema_args_appended() {
  begin_case "schema_args carry the schema text when --schema-file is given"
  local dir out summary argv_line
  dir="$(case_dir schema-args)"
  out="${dir}/out"
  printf 'Constrained answer requested.\n' > "${dir}/prompt.md"
  printf '{"type":"object","properties":{"position":{"type":"string"}}}\n' > "${dir}/schema.json"

  RUN_CONFIG="${FIXTURES}/sages-argv-probe.json"
  run_magi "$dir" --prompt-file "${dir}/prompt.md" --out-dir "$out" --round round1 \
    --schema-file "${dir}/schema.json"

  summary="${out}/round1/summary.json"
  expect_rc 0 "$RUN_RC" "dispatch with a schema"
  expect_value ok "$(sage_field "$summary" PROBESAGE status)" "probe sage status"
  # The probe sage prints its own argument list on the first line of its answer.
  argv_line="$(jq -r '.sages[0].answer | split("\n")[0]' "$summary")"
  expect_text_has "$argv_line" "--json-schema" "the schema flag reaches argv"
  expect_text_has "$argv_line" '"position"' "the schema text is substituted into argv"
  end_case
}

case_schema_args_omitted() {
  begin_case "schema_args are omitted when no --schema-file is given"
  local dir out summary argv_line
  dir="$(case_dir schema-absent)"
  out="${dir}/out"
  printf 'Unconstrained answer requested.\n' > "${dir}/prompt.md"

  RUN_CONFIG="${FIXTURES}/sages-argv-probe.json"
  run_magi "$dir" --prompt-file "${dir}/prompt.md" --out-dir "$out" --round round1

  summary="${out}/round1/summary.json"
  expect_rc 0 "$RUN_RC" "dispatch without a schema"
  argv_line="$(jq -r '.sages[0].answer | split("\n")[0]' "$summary")"
  expect_value "args=[]" "$argv_line" "the sage receives no extra arguments"
  end_case
}

case_prompt_body_not_in_argv() {
  begin_case "the prompt body stays out of argv when the sage reads stdin"
  local dir out summary answer argv_line
  dir="$(case_dir argv-hygiene)"
  out="${dir}/out"
  printf 'Confidential MAGI-ARGV-LEAK-MARKER question.\n' > "${dir}/prompt.md"

  RUN_CONFIG="${FIXTURES}/sages-argv-probe.json"
  run_magi "$dir" --prompt-file "${dir}/prompt.md" --out-dir "$out" --round round1

  summary="${out}/round1/summary.json"
  expect_rc 0 "$RUN_RC" "dispatch"
  answer="$(sage_field "$summary" PROBESAGE answer)"
  argv_line="$(jq -r '.sages[0].answer | split("\n")[0]' "$summary")"
  # The sage echoes stdin after its argument list, so one answer shows both that
  # the prompt arrived and that it arrived off the command line (design §8).
  expect_text_has "$answer" "MAGI-ARGV-LEAK-MARKER" "the prompt reaches the sage on stdin"
  expect_text_lacks "$argv_line" "MAGI-ARGV-LEAK-MARKER" "the sage's argument list"
  end_case
}

case_prompt_file_preconditions() {
  begin_case "dispatch is refused when the prompt file is missing or empty"
  local dir out
  dir="$(case_dir prompt-preconditions)"
  out="${dir}/out"
  : > "${dir}/empty.md"

  RUN_CONFIG="${FIXTURES}/sages-ok.json"
  run_magi "$dir" --prompt-file "${dir}/no-such-prompt.md" --out-dir "$out" --round round1
  expect_rc 2 "$RUN_RC" "dispatch with a missing prompt file"
  expect_contains "$RUN_ERR" "prompt file not found" "the error names the problem"

  RUN_CONFIG="${FIXTURES}/sages-ok.json"
  run_magi "$dir" --prompt-file "${dir}/empty.md" --out-dir "$out" --round round1
  expect_rc 2 "$RUN_RC" "dispatch with an empty prompt file"
  expect_contains "$RUN_ERR" "prompt file is empty" "the error names the problem"

  expect_absent "${out}/round1/summary.json" "no summary is written"
  end_case
}

case_round_label_validation() {
  begin_case "dispatch is refused when the round label contains path characters"
  local dir out
  dir="$(case_dir round-label)"
  out="${dir}/out"
  printf 'Round label probe.\n' > "${dir}/prompt.md"

  RUN_CONFIG="${FIXTURES}/sages-ok.json"
  run_magi "$dir" --prompt-file "${dir}/prompt.md" --out-dir "$out" --round "../escape"

  expect_rc 2 "$RUN_RC" "dispatch with a traversing round label"
  expect_contains "$RUN_ERR" "invalid --round" "the error names the round label"
  expect_absent "${dir}/escape" "no directory is created outside the run directory"
  expect_absent "$out" "the run directory is not created"
  end_case
}

# --- driver ----------------------------------------------------------------

printf 'magi-run.sh fake-sage tests\n'
printf 'script:    %s\n' "$SCRIPT"
printf 'artifacts: %s\n\n' "$WORK_ROOT"

case_sources_parse
case_three_ok_answers
case_parallel_dispatch
case_timeout_status
case_error_isolation
case_unreadable_answer
case_preflight_missing_cli
case_refuses_missing_cli
case_env_override
case_project_over_home_config
case_bundled_default_config
case_rejects_prompt_in_argv
case_per_sage_prompt
case_sages_filter
case_unknown_sage_name
case_schema_args_appended
case_schema_args_omitted
case_prompt_body_not_in_argv
case_prompt_file_preconditions
case_round_label_validation

rm -f "$CASE_LOG"

printf '\n%s cases: %s passed, %s failed\n' \
  "$((PASS_COUNT + FAIL_COUNT))" "$PASS_COUNT" "$FAIL_COUNT"
printf 'artifacts kept for inspection: %s\n' "$WORK_ROOT"
[ -z "$OK_OUT_DIR" ] || printf '  happy-path out-dir: %s\n' "$OK_OUT_DIR"
[ -z "$OK_SUMMARY" ] || printf '  happy-path summary: %s\n' "$OK_SUMMARY"

[ "$FAIL_COUNT" -eq 0 ] || exit 1
