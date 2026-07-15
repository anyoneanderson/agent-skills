#!/usr/bin/env bash
# pipeline-state-check.sh — verify pipeline-state.json against on-disk evidence.
#
# The state file is the orchestrator's own claim about where the run is; this
# script cross-checks that claim against evidence the state cannot fake: the
# tasks.md checkboxes, run-record files, and (when gh is available) the PR for
# the current branch. Run it after every state write and as the first step of a
# resume. A drift means the state was left behind (e.g. a phase ran without its
# state update) — reconcile state to the evidence before continuing
# (pipeline-config.md §State integrity check).
#
# Usage: pipeline-state-check.sh <spec-dir>       e.g. .specs/user-auth
# Exit:  0 = consistent, 1 = drift found (one "DRIFT:" line each), 2 = usage error

set -uo pipefail

SPEC_DIR="${1:-}"
[ -n "$SPEC_DIR" ] && [ -d "$SPEC_DIR" ] || { echo "usage: $0 <spec-dir>" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "pipeline-state-check: jq is required" >&2; exit 2; }

STATE="$SPEC_DIR/pipeline-state.json"
[ -f "$STATE" ] || { echo "pipeline-state-check: no state file at $STATE" >&2; exit 2; }
jq empty "$STATE" 2>/dev/null || { echo "DRIFT: $STATE is not valid JSON"; exit 1; }

drift=0
report() { echo "DRIFT: $1"; drift=1; }

phase="$(jq -r '.phase // empty' "$STATE")"
completed="$(jq -r '(.completed_phases // []) | join(",")' "$STATE")"
host_runtime="$(jq -r '.host_runtime // empty' "$STATE")"

has_completed() { case ",$completed," in *",$1,"*) return 0;; *) return 1;; esac; }

case "$phase" in
  intake|spec_generate|inspect|spec_review|approval|implement|evaluate|arbitration|pr|retrospective) ;;
  *) report "unknown phase '$phase'" ;;
esac

case "$host_runtime" in
  claude|codex) ;;
  *) report "host_runtime must be 'claude' or 'codex' (got '$host_runtime')" ;;
esac

# --- independent review fallback records ------------------------------------
# Older states may omit review_fallbacks. When present, every entry describes
# the only permitted same-AI review fallback: a fresh host-native reviewer used
# because the preferred cross-AI peer was unavailable. Its nested host_runtime
# is historical; the top-level host may change when another runtime resumes.
if ! jq -e '
  . as $state
  | ($state.review_fallbacks // []) as $fallbacks
  | (($fallbacks | type) == "array")
    and all($fallbacks[];
      ((.phase == "spec_review") or (.phase == "implement"))
      and ((.artifact | type) == "string") and ((.artifact | length) > 0)
      and ((.round | type) == "number") and (.round >= 1) and (.round == (.round | floor))
      and ((.preferred_role == "claude") or (.preferred_role == "codex"))
      and ((.actual_role == "claude") or (.actual_role == "codex"))
      and ((.host_runtime == "claude") or (.host_runtime == "codex"))
      and (.preferred_role != .actual_role)
      and (.actual_role == .host_runtime)
      and (.backend == "runtime-native")
      and (.reason == "peer_unavailable")
      and (.independence == "fresh_subagent")
    )
' "$STATE" >/dev/null 2>&1; then
  report "review_fallbacks must contain only self-contained fresh host-native peer_unavailable review records"
fi

# --- completed_phases gap check ------------------------------------------------
# Every phase that precedes the current one in the canonical order must be
# recorded in completed_phases. A gap means a phase ran without its state update
# (the exact failure the #184 dogfood exhibited: phase=retrospective while
# implement/evaluate/pr were never recorded).
#
# Exception: an arbitration draft-PR landing (stall-detection.md —
# arbitration → pr) legitimately reaches pr/retrospective without
# approval/implement/evaluate. It is always recorded as an arbitrations[] entry
# with decision "draft", so that record exempts those three legs.
CANONICAL="intake spec_generate inspect spec_review approval implement evaluate pr retrospective"
draft_landed="$(jq -r '[(.arbitrations // [])[] | select(.decision == "draft")] | length > 0' "$STATE")"
if [ "$phase" != "arbitration" ]; then
  missing=""
  for p in $CANONICAL; do
    [ "$p" = "$phase" ] && break
    if [ "$draft_landed" = "true" ]; then
      case "$p" in approval|implement|evaluate) continue;; esac
    fi
    has_completed "$p" || missing="$missing $p"
  done
  [ -n "${missing// /}" ] && report "phases preceding '$phase' missing from completed_phases:$missing"
fi

# --- tasks.md checkboxes vs implement.tasks_done -----------------------------
# Task ids are T-prefixed (T000, T012b, ...). Compare the set of checked boxes
# in tasks.md with the ids the state claims are done, in both directions.
if [ -f "$SPEC_DIR/tasks.md" ] && jq -e '.implement.tasks_done' "$STATE" >/dev/null 2>&1; then
  checked="$(grep -E '^\s*[-*] \[[xX]\]' "$SPEC_DIR/tasks.md" | grep -oE 'T[0-9]+[a-z]?' | sort -u)"
  recorded="$(jq -r '.implement.tasks_done[]' "$STATE" | sort -u)"
  only_checked="$(comm -23 <(printf '%s\n' $checked) <(printf '%s\n' $recorded) 2>/dev/null | tr '\n' ' ')"
  only_recorded="$(comm -13 <(printf '%s\n' $checked) <(printf '%s\n' $recorded) 2>/dev/null | tr '\n' ' ')"
  [ -n "${only_checked// /}" ] && report "tasks checked in tasks.md but missing from state.implement.tasks_done: $only_checked"
  [ -n "${only_recorded// /}" ] && report "tasks in state.implement.tasks_done but unchecked in tasks.md: $only_recorded"
fi

# --- run-record files vs phase progression -----------------------------------
if [ -f "$SPEC_DIR/retrospective.md" ] && [ "$phase" != "retrospective" ] && ! has_completed retrospective; then
  report "retrospective.md exists but state is at phase '$phase' (retrospective not recorded)"
fi

# "Either kind of evaluate output exists" — ls over both patterns would fail
# whenever one of them has no match, silently skipping the check.
if compgen -G "$SPEC_DIR/evaluate-*.md" >/dev/null 2>&1 || [ -f "$SPEC_DIR/evaluation-report.md" ]; then
  case "$phase" in evaluate|pr|retrospective) ;; *)
    if ! has_completed evaluate; then
      report "evaluate results exist on disk but state is at phase '$phase' (evaluate not recorded)"
    fi ;;
  esac
fi

# --- PR evidence vs phase ------------------------------------------------------
# If the current branch already has a PR but the state has not reached 'pr',
# the pr phase ran without its state update (or the wrong branch is checked out).
if command -v gh >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch="$(git branch --show-current 2>/dev/null)"
  if [ -n "$branch" ] && [ "$phase" != "pr" ] && [ "$phase" != "retrospective" ] && ! has_completed pr; then
    pr_state="$(gh pr view "$branch" --json state --jq .state 2>/dev/null || true)"
    if [ -n "$pr_state" ]; then
      report "a PR exists for branch '$branch' ($pr_state) but state is at phase '$phase' (pr not recorded)"
    fi
  fi
fi

if [ "$drift" -eq 0 ]; then
  echo "STATE OK: phase=$phase completed=[$completed]"
  exit 0
fi
exit 1
