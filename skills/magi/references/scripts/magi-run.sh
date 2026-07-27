#!/usr/bin/env bash
# magi-run.sh — parallel headless dispatch to the MAGI council sages.
#
# This script is the public contract between skills/magi/SKILL.md (the host) and
# the sage CLIs. It does five things and nothing more:
#   1. resolves the sage adapter config (env > project > home > bundled default)
#   2. preflight: checks jq and every selected sage command with `command -v`
#   3. launches each sage in parallel, each wrapped in a hard timeout
#   4. stores every sage's raw stdout / stderr for the audit trail
#   5. writes <out-dir>/<round>/summary.json and prints its path
#
# It never interprets an answer. Comparing positions, judging duplicate research
# findings, running the debate and building the result matrix belong to the host
# (CON-002), because those are semantic judgements and this script must stay a
# mechanical dispatcher.
#
# Notes for maintainers:
#   - Target bash 3.2: stock macOS ships it. No mapfile, no associative arrays,
#     no `wait -n`.
#   - No GNU `timeout`: it is absent on macOS (CON-003). A `perl -e 'alarm N'`
#     wrapper enforces the limit instead; the alarm survives exec, so the sage
#     process itself dies of SIGALRM and bash reports exit 142.
#   - The question never reaches argv. A sage receives it either on stdin
#     (`"input": "stdin"`) or as the path in {PROMPT_FILE}, because arguments are
#     world-readable through `ps` on the same machine (design §8).
#   - Sage command elements are substituted per array element, never through a
#     shell, so a path or schema cannot be re-parsed as shell syntax.

set -euo pipefail

# The prompt carries the user's question, which may be confidential, and the raw
# outputs quote it back. Keep everything this script creates owner-only.
umask 077

# --- constants -------------------------------------------------------------

DEFAULT_TIMEOUT_SECONDS=600
# The tally rules in SKILL.md assume three sages (or a degraded two).
MAX_SAGES=3
# 128 + SIGALRM(14) — the perl alarm wrapper firing. Same number on macOS/Linux.
SIGALRM_EXIT=142

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SELF")"
BUNDLED_SAGES_FILE="${SCRIPT_DIR}/sages.default.json"

# `alarm` is armed before exec and inherited by the sage process. The indirect
# object form of exec never falls back to a shell, even for a one-word command.
ALARM_WRAPPER='alarm shift @ARGV; exec { $ARGV[0] } @ARGV or die "magi-run: cannot execute $ARGV[0]: $!\n"'

# --- arguments -------------------------------------------------------------

PROMPT_FILE=""
OUT_DIR=""
ROUND=""
SAGES_FILTER=""
SCHEMA_FILE=""
PREFLIGHT_ONLY=0

# --- resolved state --------------------------------------------------------

SAGES_FILE=""
TIMEOUT_SECONDS="$DEFAULT_TIMEOUT_SECONDS"
ROUND_DIR=""
PREFLIGHT_FILE=""
SUMMARY_FILE=""
SCHEMA_TEXT=""
# Index / name / cli of the selected sages, in config order (parallel arrays,
# because bash 3.2 has no nested arrays).
SEL_IDX=()
SEL_NAME=()
SEL_CLI=()
MISSING_CLIS=""
# Out-parameters of read_sage_argv / substitute_placeholder (no namerefs in 3.2).
RAW_ARGV=()

usage_text() {
  cat <<'EOF'
Usage: magi-run.sh --prompt-file <path> --out-dir <dir> --round <label>
       [--sages NAME1,NAME2] [--schema-file <path>] [--preflight-only]

  --prompt-file     File holding the prompt for every selected sage. Required
                    unless --preflight-only is set, or every selected sage has a
                    per-sage prompt file (see below).
  --out-dir         Run directory. preflight.json is written at its root.
  --round           Round label (round1, debate1, ...). Sage artifacts and
                    summary.json go to <out-dir>/<round>/. Required unless
                    --preflight-only is set.
  --sages           Comma-separated sage names to dispatch to. Default: every
                    sage in the config.
  --schema-file     JSON schema file. Appended to the command of each sage that
                    declares schema_args, with {SCHEMA} replaced by its text.
  --preflight-only  Check jq and the sage commands, write preflight.json, stop.

Per-sage prompts: when <out-dir>/<round>/prompt-<SAGE>.md exists it overrides
--prompt-file for that sage. A debate round uses this to send each sage its own
anonymised prompt within a single parallel dispatch.

Prompt delivery: a sage with "input": "stdin" in the config reads the prompt file
on standard input; otherwise the file path replaces {PROMPT_FILE} in its command.
The prompt body is never placed in a command-line argument, where `ps` would
expose the question to every local process.

A command may also use {MAGI_SCRIPTS_DIR}, the absolute directory holding this
script, to run a wrapper shipped next to it — the default codex adapter does that
to switch off the operator's MCP servers (references/sages.md).

Sage config resolution, first match wins: $MAGI_SAGES_FILE, ./.magi/sages.json,
~/.magi/sages.json, bundled sages.default.json.

Keep prompt files inside --out-dir so the run directory stays a self-contained
audit trail (NFR-003).

Exit codes: 0 = dispatched (read summary.json) | 2 = precondition error
The absolute path of summary.json is printed as the last line of stdout.
EOF
}

usage() { usage_text >&2; exit 2; }
show_help() { usage_text; exit 0; }
err() { printf 'magi-run: %s\n' "$*" >&2; }

utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
# BSD date has no %N, so perl (already required for the timeout) owns the clock.
now_ms() { perl -MTime::HiRes=time -e 'printf "%.0f\n", time() * 1000'; }

abs_path() {
  local target="$1" dir base
  dir="$(dirname "$target")"
  base="$(basename "$target")"
  printf '%s/%s' "$(cd "$dir" && pwd)" "$base"
}

is_uint() { case "$1" in '' | *[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# --- sage config -----------------------------------------------------------

resolve_sages_file() {
  local candidate
  # An explicit override that does not exist is a caller mistake, not a reason
  # to silently fall back to the bundled defaults.
  if [ -n "${MAGI_SAGES_FILE:-}" ]; then
    [ -f "$MAGI_SAGES_FILE" ] || {
      err "sage config from MAGI_SAGES_FILE not found: ${MAGI_SAGES_FILE}"
      exit 2
    }
    SAGES_FILE="$(abs_path "$MAGI_SAGES_FILE")"
    return 0
  fi
  for candidate in "./.magi/sages.json" "${HOME}/.magi/sages.json" "$BUNDLED_SAGES_FILE"; do
    if [ -f "$candidate" ]; then
      SAGES_FILE="$(abs_path "$candidate")"
      return 0
    fi
  done
  err "no sage config found (searched MAGI_SAGES_FILE, ./.magi/sages.json, ~/.magi/sages.json, ${BUNDLED_SAGES_FILE})"
  exit 2
}

# Reports every structural problem at once, so a broken config takes one run to
# fix rather than one run per field.
config_problems() {
  jq -r '
    def sage_problems($i; $s):
      if ($s | type) != "object" then
        ["sages[\($i)] must be an object"]
      else
        [ (if ($s.name | type) != "string" or ($s.name | test("^[A-Za-z0-9_-]+$") | not)
              then "sages[\($i)].name must be a string of [A-Za-z0-9_-] (it becomes an output file name)"
              else empty end),
          (if ($s.cli | type) != "string" or ($s.cli | length) == 0
              then "sages[\($i)].cli must be a non-empty string"
              else empty end),
          (if ($s.command | type) != "array" or ($s.command | length) == 0
              then "sages[\($i)].command must be a non-empty array"
            elif any($s.command[]; type != "string")
              then "sages[\($i)].command must contain only strings"
            elif any($s.command[]; contains("{PROMPT}"))
              then "sages[\($i)].command uses the withdrawn {PROMPT} placeholder: the prompt body must never appear in argv, where any local process can read it with ps. Use {PROMPT_FILE} or \"input\": \"stdin\" instead"
            elif (any($s.command[]; contains("{PROMPT_FILE}")) | not) and ($s.input? // "") != "stdin"
              then "sages[\($i)] has no way to receive the prompt: put the {PROMPT_FILE} placeholder in command, or set \"input\": \"stdin\""
              else empty end),
          (if ($s | has("input")) and ($s.input != "stdin")
              then "sages[\($i)].input must be the string \"stdin\" when present (the only supported input mode; omit it to pass the prompt path with {PROMPT_FILE})"
              else empty end),
          (if ($s.extract | type) != "string" or ($s.extract | length) == 0
              then "sages[\($i)].extract must be a non-empty string (jq filter, \"answer-file\" or \"raw\")"
            elif $s.extract == "answer-file" and (($s.command | type) != "array"
                  or (any($s.command[]; type == "string" and contains("{ANSWER_FILE}")) | not))
              then "sages[\($i)].extract is \"answer-file\" but command has no {ANSWER_FILE} placeholder"
              else empty end),
          (if ($s | has("schema_args")) and (($s.schema_args | type) != "array"
                or any($s.schema_args[]; type != "string"))
              then "sages[\($i)].schema_args must be an array of strings"
              else empty end)
        ]
      end;
    [ (.sages | to_entries[] | sage_problems(.key; .value)),
      (if ([.sages[]? | objects | .name] | length) != ([.sages[]? | objects | .name] | unique | length)
         then ["sage names must be unique"] else [] end)
    ] | flatten | .[]
  ' "$SAGES_FILE"
}

load_sages_file() {
  local problems count
  jq -e 'type == "object"' "$SAGES_FILE" >/dev/null 2>&1 || {
    err "invalid sage config: root is not a JSON object (file: ${SAGES_FILE})"
    exit 2
  }
  jq -e '.sages | type == "array" and length > 0' "$SAGES_FILE" >/dev/null 2>&1 || {
    err "invalid sage config: 'sages' must be a non-empty array (file: ${SAGES_FILE})"
    exit 2
  }
  count="$(jq -r '.sages | length' "$SAGES_FILE")"
  if [ "$count" -gt "$MAX_SAGES" ]; then
    err "invalid sage config: ${count} sages configured but at most ${MAX_SAGES} are supported (file: ${SAGES_FILE})"
    exit 2
  fi
  problems="$(config_problems)"
  if [ -n "$problems" ]; then
    err "invalid sage config (file: ${SAGES_FILE}):"
    printf '%s\n' "$problems" | while IFS= read -r line; do err "  - ${line}"; done
    exit 2
  fi
  TIMEOUT_SECONDS="$(jq -r --argjson fallback "$DEFAULT_TIMEOUT_SECONDS" '.timeout_seconds // $fallback | tostring' "$SAGES_FILE")"
  if ! is_uint "$TIMEOUT_SECONDS" || [ "$TIMEOUT_SECONDS" -le 0 ]; then
    err "invalid sage config: timeout_seconds must be a positive integer, got '${TIMEOUT_SECONDS}' (file: ${SAGES_FILE})"
    exit 2
  fi
}

# Selection keeps config order so summary.json rows and the host's matrix stay
# in a predictable sequence regardless of how --sages was written.
select_sages() {
  local -a requested=()
  local idx=0 name cli item trimmed found
  if [ -n "$SAGES_FILTER" ]; then
    IFS=',' read -r -a requested <<< "$SAGES_FILTER"
    for item in "${requested[@]+"${requested[@]}"}"; do
      trimmed="$(printf '%s' "$item" | tr -d '[:space:]')"
      [ -n "$trimmed" ] || continue
      found=0
      while IFS= read -r name; do
        if [ "$name" = "$trimmed" ]; then found=1; fi
      done < <(jq -r '.sages[].name' "$SAGES_FILE")
      [ "$found" -eq 1 ] || {
        err "unknown sage '${trimmed}' in --sages; configured sages are: $(jq -r '[.sages[].name] | join(", ")' "$SAGES_FILE") (file: ${SAGES_FILE})"
        exit 2
      }
    done
  fi
  while IFS= read -r name; do
    if [ -n "$SAGES_FILTER" ]; then
      case ",$(printf '%s' "$SAGES_FILTER" | tr -d '[:space:]')," in
        *",${name},"*) : ;;
        *) idx=$((idx + 1)); continue ;;
      esac
    fi
    cli="$(jq -r --argjson idx "$idx" '.sages[$idx].cli' "$SAGES_FILE")"
    SEL_IDX+=("$idx")
    SEL_NAME+=("$name")
    SEL_CLI+=("$cli")
    idx=$((idx + 1))
  done < <(jq -r '.sages[].name' "$SAGES_FILE")
  [ "${#SEL_IDX[@]}" -gt 0 ] || {
    err "no sage selected: --sages '${SAGES_FILTER}' matched nothing in ${SAGES_FILE}"
    exit 2
  }
}

# --- preflight -------------------------------------------------------------

write_preflight() {
  local parts="${OUT_DIR}/.preflight-parts.jsonl" tmp="${PREFLIGHT_FILE}.tmp.$$"
  local i name cli path available
  : > "$parts"
  MISSING_CLIS=""
  i=0
  while [ "$i" -lt "${#SEL_IDX[@]}" ]; do
    name="${SEL_NAME[$i]}"
    cli="${SEL_CLI[$i]}"
    path="$(command -v "$cli" 2>/dev/null || true)"
    if [ -n "$path" ]; then
      available=true
    else
      available=false
      MISSING_CLIS="${MISSING_CLIS}${MISSING_CLIS:+, }${name} (${cli})"
    fi
    jq -nc --arg name "$name" --arg cli "$cli" --argjson available "$available" \
      --arg path "$path" \
      '{name: $name, cli: $cli, available: $available, path: (if $path == "" then null else $path end)}' \
      >> "$parts"
    i=$((i + 1))
  done
  jq -n --arg checked_at "$(utc_now)" --arg sages_file "$SAGES_FILE" \
    --argjson timeout_seconds "$TIMEOUT_SECONDS" --slurpfile sages "$parts" \
    '{checked_at: $checked_at, jq_available: true, sages_file: $sages_file,
      timeout_seconds: $timeout_seconds, sages: $sages,
      missing: [$sages[] | select(.available == false) | .cli],
      available_count: ([$sages[] | select(.available)] | length)}' > "$tmp"
  mv -f "$tmp" "$PREFLIGHT_FILE"
  rm -f "$parts"
  [ -z "$MISSING_CLIS" ] || err "sage commands not found on PATH: ${MISSING_CLIS}"
}

# jq is needed to read the config, so its absence is reported before anything
# else — including in preflight.json, which the host reads either way.
require_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  err "jq not found on PATH; install it (macOS: brew install jq / Debian: apt-get install jq) and re-run magi-run.sh"
  if [ -n "$OUT_DIR" ] && mkdir -p "$OUT_DIR" 2>/dev/null; then
    printf '{"checked_at":"%s","jq_available":false,"sages":[],"missing":["jq"],"available_count":0}\n' \
      "$(utc_now)" > "${OUT_DIR}/preflight.json"
  fi
  exit 2
}

# --- prompts ---------------------------------------------------------------

prompt_file_for() {
  local name="$1" per_sage="${ROUND_DIR}/prompt-${name}.md"
  if [ -f "$per_sage" ]; then printf '%s' "$per_sage"; else printf '%s' "$PROMPT_FILE"; fi
}

check_prompts() {
  local i name resolved
  i=0
  while [ "$i" -lt "${#SEL_NAME[@]}" ]; do
    name="${SEL_NAME[$i]}"
    resolved="$(prompt_file_for "$name")"
    [ -n "$resolved" ] || {
      err "no prompt for sage ${name}: pass --prompt-file or create ${ROUND_DIR}/prompt-${name}.md"
      exit 2
    }
    [ -f "$resolved" ] || { err "prompt file not found for sage ${name}: ${resolved}"; exit 2; }
    [ -s "$resolved" ] || { err "prompt file is empty for sage ${name}: ${resolved}"; exit 2; }
    i=$((i + 1))
  done
}

# --- dispatch --------------------------------------------------------------

sage_stdout_file() { printf '%s/%s.stdout' "$ROUND_DIR" "$1"; }
sage_stderr_file() { printf '%s/%s.stderr' "$ROUND_DIR" "$1"; }
sage_answer_file() { printf '%s/%s.answer.txt' "$ROUND_DIR" "$1"; }
sage_meta_file() { printf '%s/.%s.meta' "$ROUND_DIR" "$1"; }

# Reads one sage's argv from the config. jq -r prints one element per line, so a
# line count that disagrees with the array length means an element contained a
# newline and the argv cannot be reconstructed safely.
read_sage_argv() {
  local idx="$1" filter="$2" expected line count=0
  RAW_ARGV=()
  expected="$(jq -r --argjson idx "$idx" "${filter} | length" "$SAGES_FILE")"
  while IFS= read -r line; do
    RAW_ARGV+=("$line")
    count=$((count + 1))
  done < <(jq -r --argjson idx "$idx" "${filter}[]" "$SAGES_FILE")
  [ "$count" = "$expected" ] || {
    err "sage config element contains a newline, which cannot be passed as an argument (file: ${SAGES_FILE}, sages[${idx}])"
    return 1
  }
}

# Replaces every occurrence of a placeholder, leaving the result in SUBST_OUT
# (bash 3.2 has no namerefs). Bash's own ${var//pat/rep} is unusable here: an `&`
# in the replacement expands to the matched text, so a directory name or schema
# containing an ampersand would come out with the placeholder spliced into it.
# Splitting on the placeholder with prefix/suffix removal keeps it byte-for-byte.
SUBST_OUT=""
substitute_placeholder() {
  local text="$1" placeholder="$2" value="$3" out=""
  while :; do
    case "$text" in
      *"$placeholder"*)
        out="${out}${text%%"$placeholder"*}${value}"
        text="${text#*"$placeholder"}"
        ;;
      *)
        out="${out}${text}"
        break
        ;;
    esac
  done
  SUBST_OUT="$out"
}

# Runs as a background job: builds argv, execs the sage under the alarm wrapper,
# and records exit code plus wall time for the parent to collect.
run_sage() {
  local idx="$1" name="$2" prompt_file="$3"
  local stdout_file stderr_file answer_file meta_file
  local element input_mode stdin_src rc=0 started ended duration
  local -a argv=()

  stdout_file="$(sage_stdout_file "$name")"
  stderr_file="$(sage_stderr_file "$name")"
  answer_file="$(sage_answer_file "$name")"
  meta_file="$(sage_meta_file "$name")"

  # A sage reads the prompt from stdin or from the path in {PROMPT_FILE}. Sages
  # without stdin input get /dev/null, so one waiting on stdin fails fast instead
  # of consuming the host's input or hanging until the alarm fires.
  input_mode="$(jq -r --argjson idx "$idx" '.sages[$idx].input // ""' "$SAGES_FILE")"
  stdin_src="/dev/null"
  if [ "$input_mode" = "stdin" ]; then stdin_src="$prompt_file"; fi

  read_sage_argv "$idx" '(.sages[$idx].command)' || return 1
  argv=("${RAW_ARGV[@]}")
  if [ -n "$SCHEMA_FILE" ]; then
    read_sage_argv "$idx" '(.sages[$idx].schema_args // [])' || return 1
    if [ "${#RAW_ARGV[@]}" -gt 0 ]; then
      argv=("${argv[@]}" "${RAW_ARGV[@]}")
    fi
  fi

  # Element-wise substitution: only paths and the schema go into argv, and none of
  # them passes through a shell, so their contents cannot be re-parsed.
  local -a cmd=()
  for element in "${argv[@]}"; do
    substitute_placeholder "$element" '{PROMPT_FILE}' "$prompt_file"
    substitute_placeholder "$SUBST_OUT" '{ANSWER_FILE}' "$answer_file"
    substitute_placeholder "$SUBST_OUT" '{SCHEMA}' "$SCHEMA_TEXT"
    # Lets an adapter reach a wrapper shipped beside this script (codex-sage.sh)
    # without the config hard-coding an install path.
    substitute_placeholder "$SUBST_OUT" '{MAGI_SCRIPTS_DIR}' "$SCRIPT_DIR"
    cmd+=("$SUBST_OUT")
  done

  started="$(now_ms)"
  # The subshell keeps any shell-level notice about the sage process (bash prints
  # "Alarm clock: 14" in some versions) inside that sage's stderr file.
  ( perl -e "$ALARM_WRAPPER" "$TIMEOUT_SECONDS" "${cmd[@]}" ) \
    < "$stdin_src" > "$stdout_file" 2> "$stderr_file" || rc=$?
  ended="$(now_ms)"
  # A killed sage often leaves no stderr at all; state the reason so the run
  # directory alone explains the outcome (NFR-003).
  if [ "$rc" = "$SIGALRM_EXIT" ]; then
    printf 'magi-run: sage %s exceeded the %s second timeout and was stopped by SIGALRM\n' \
      "$name" "$TIMEOUT_SECONDS" >> "$stderr_file"
  fi
  duration=$((ended - started))
  [ "$duration" -ge 0 ] || duration=0
  printf 'exit_code=%s\nduration_ms=%s\n' "$rc" "$duration" > "$meta_file"
}

# Applies the sage's extract rule and leaves the answer body in its answer file.
extract_answer() {
  local name="$1" extract="$2"
  local stdout_file answer_file tmp
  stdout_file="$(sage_stdout_file "$name")"
  answer_file="$(sage_answer_file "$name")"
  case "$extract" in
    answer-file)
      # The CLI wrote {ANSWER_FILE} itself; nothing to transform.
      [ -s "$answer_file" ] || return 1
      ;;
    raw)
      [ -s "$stdout_file" ] || return 1
      cp "$stdout_file" "$answer_file" || return 1
      ;;
    *)
      tmp="${answer_file}.tmp.$$"
      # -e turns a missing key or null result into a non-zero exit, which is the
      # same degraded case as a broken envelope.
      if ! jq -er "$extract" "$stdout_file" > "$tmp" 2>/dev/null || [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        return 1
      fi
      mv -f "$tmp" "$answer_file"
      ;;
  esac
}

dispatch_round() {
  local parts="${ROUND_DIR}/.summary-parts.jsonl" tmp="${SUMMARY_FILE}.tmp.$$"
  local -a pids=()
  local -a prompts=()
  local i name cli idx prompt_file extract meta_file
  local rc_wait exit_code duration_ms sage_status answer_src

  : > "$parts"
  i=0
  while [ "$i" -lt "${#SEL_NAME[@]}" ]; do
    name="${SEL_NAME[$i]}"
    prompt_file="$(abs_path "$(prompt_file_for "$name")")"
    prompts+=("$prompt_file")
    # A re-run of the same round must not inherit the previous attempt's answer
    # file, or a failed sage would look like it answered.
    rm -f "$(sage_stdout_file "$name")" "$(sage_stderr_file "$name")" \
      "$(sage_answer_file "$name")" "$(sage_meta_file "$name")"
    i=$((i + 1))
  done

  # All sages start before any wait: the round costs the slowest sage, not the
  # sum of the three (NFR-001).
  i=0
  while [ "$i" -lt "${#SEL_NAME[@]}" ]; do
    run_sage "${SEL_IDX[$i]}" "${SEL_NAME[$i]}" "${prompts[$i]}" &
    pids+=("$!")
    i=$((i + 1))
  done

  i=0
  while [ "$i" -lt "${#pids[@]}" ]; do
    rc_wait=0
    wait "${pids[$i]}" || rc_wait=$?
    idx="${SEL_IDX[$i]}"
    name="${SEL_NAME[$i]}"
    cli="${SEL_CLI[$i]}"
    meta_file="$(sage_meta_file "$name")"
    extract="$(jq -r --argjson idx "$idx" '.sages[$idx].extract' "$SAGES_FILE")"

    exit_code=""
    duration_ms=""
    if [ -f "$meta_file" ]; then
      exit_code="$(awk -F= '$1 == "exit_code" { print $2; exit }' "$meta_file")"
      duration_ms="$(awk -F= '$1 == "duration_ms" { print $2; exit }' "$meta_file")"
    fi
    is_uint "$duration_ms" || duration_ms=0
    if ! is_uint "$exit_code"; then
      # The job died before it could record a result (e.g. unusable argv), so the
      # only evidence left is the status the shell collected from the job.
      if is_uint "$rc_wait" && [ "$rc_wait" -ne 0 ]; then
        exit_code="$rc_wait"
      else
        exit_code=1
      fi
    fi

    if [ "$exit_code" = "$SIGALRM_EXIT" ]; then
      sage_status="timeout"
    elif [ "$exit_code" != "0" ]; then
      sage_status="error"
    elif extract_answer "$name" "$extract"; then
      sage_status="ok"
    else
      sage_status="error"
      err "sage ${name}: could not extract an answer with extract='${extract}' (see $(sage_stdout_file "$name"))"
    fi

    # Reading an empty answer from /dev/null keeps `answer` a string for every
    # status without a second jq invocation.
    answer_src="/dev/null"
    if [ "$sage_status" = "ok" ]; then answer_src="$(sage_answer_file "$name")"; fi
    # --rawfile keeps a long answer out of the argument list.
    jq -nc --arg name "$name" --arg cli "$cli" --arg sage_status "$sage_status" \
      --argjson exit_code "$exit_code" --argjson duration_ms "$duration_ms" \
      --rawfile answer "$answer_src" --arg stdout_file "$(sage_stdout_file "$name")" \
      --arg stderr_file "$(sage_stderr_file "$name")" --arg prompt_file "${prompts[$i]}" \
      '{name: $name, cli: $cli, status: $sage_status, exit_code: $exit_code,
        duration_ms: $duration_ms, answer: $answer, stdout_file: $stdout_file,
        stderr_file: $stderr_file, prompt_file: $prompt_file}' >> "$parts"
    rm -f "$meta_file"
    i=$((i + 1))
  done

  jq -n --arg round "$ROUND" --arg prompt_file "$PROMPT_FILE" --slurpfile sages "$parts" \
    '{round: $round, prompt_file: (if $prompt_file == "" then null else $prompt_file end),
      sages: $sages}' > "$tmp"
  mv -f "$tmp" "$SUMMARY_FILE"
  rm -f "$parts"
}

# --- argument parsing ------------------------------------------------------

while [ $# -gt 0 ]; do
  case "$1" in
    --prompt-file) [ $# -ge 2 ] || { err "--prompt-file needs a value"; usage; }; PROMPT_FILE="$2"; shift 2 ;;
    --out-dir) [ $# -ge 2 ] || { err "--out-dir needs a value"; usage; }; OUT_DIR="$2"; shift 2 ;;
    --round) [ $# -ge 2 ] || { err "--round needs a value"; usage; }; ROUND="$2"; shift 2 ;;
    --sages) [ $# -ge 2 ] || { err "--sages needs a value"; usage; }; SAGES_FILTER="$2"; shift 2 ;;
    --schema-file) [ $# -ge 2 ] || { err "--schema-file needs a value"; usage; }; SCHEMA_FILE="$2"; shift 2 ;;
    --preflight-only) PREFLIGHT_ONLY=1; shift ;;
    -h | --help) show_help ;;
    *) err "unknown argument: $1"; usage ;;
  esac
done

# --- preconditions ---------------------------------------------------------

[ -n "$OUT_DIR" ] || { err "missing --out-dir"; usage; }
require_jq

if [ "$PREFLIGHT_ONLY" -ne 1 ]; then
  [ -n "$ROUND" ] || { err "missing --round"; usage; }
  case "$ROUND" in
    [A-Za-z0-9]*) : ;;
    *) err "invalid --round '${ROUND}': must start with a letter or digit"; exit 2 ;;
  esac
  case "$ROUND" in
    *[!A-Za-z0-9._-]*) err "invalid --round '${ROUND}': allowed characters are A-Z a-z 0-9 . _ -"; exit 2 ;;
  esac
fi

if [ -n "$SCHEMA_FILE" ]; then
  [ -f "$SCHEMA_FILE" ] || { err "schema file not found: ${SCHEMA_FILE}"; exit 2; }
  [ -s "$SCHEMA_FILE" ] || { err "schema file is empty: ${SCHEMA_FILE}"; exit 2; }
  jq -e . "$SCHEMA_FILE" >/dev/null 2>&1 || { err "schema file is not valid JSON: ${SCHEMA_FILE}"; exit 2; }
  SCHEMA_TEXT="$(cat "$SCHEMA_FILE")"
fi

mkdir -p "$OUT_DIR" || { err "cannot create --out-dir: ${OUT_DIR}"; exit 2; }
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
PREFLIGHT_FILE="${OUT_DIR}/preflight.json"

resolve_sages_file
load_sages_file
select_sages
write_preflight

if [ "$PREFLIGHT_ONLY" -eq 1 ]; then
  # Missing commands are data here, not a failure: the host asks the user whether
  # to continue with a degraded council (REQ-009).
  printf '%s\n' "$PREFLIGHT_FILE"
  exit 0
fi

if [ -n "$MISSING_CLIS" ]; then
  err "refusing to dispatch round '${ROUND}': install the missing CLIs or re-run with --sages listing only available sages (details: ${PREFLIGHT_FILE})"
  exit 2
fi

ROUND_DIR="${OUT_DIR}/${ROUND}"
mkdir -p "$ROUND_DIR" || { err "cannot create round directory: ${ROUND_DIR}"; exit 2; }
SUMMARY_FILE="${ROUND_DIR}/summary.json"

if [ -n "$PROMPT_FILE" ]; then
  [ -f "$PROMPT_FILE" ] || { err "prompt file not found: ${PROMPT_FILE}"; exit 2; }
  [ -s "$PROMPT_FILE" ] || { err "prompt file is empty: ${PROMPT_FILE}"; exit 2; }
  PROMPT_FILE="$(abs_path "$PROMPT_FILE")"
fi
check_prompts

dispatch_round

printf '%s\n' "$SUMMARY_FILE"
