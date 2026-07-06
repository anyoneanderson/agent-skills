# Pipeline Config and State — pipeline.yml and pipeline-state.json

The orchestrator owns two data files: `pipeline.yml` (static configuration, one
per repository) and `pipeline-state.json` (live run state, one per feature). This
file specifies both and the resume behavior that reads state on startup.

日本語版: [pipeline-config.ja.md](pipeline-config.ja.md)

## pipeline.yml

Location: `.specs/pipeline.yml` (one per repository). When absent, the defaults
below apply, `app` is empty (no launch recipe), and `limits` use their defaults.

```yaml
roles:
  spec_author: claude
  spec_reviewer: codex
  impl_ui: claude
  impl_backend: codex
  impl_test: codex
  e2e_runner: claude
app:                      # spec-evaluate launch recipe (required only when UI cases exist)
  start: "npm run dev"
  url: "http://localhost:3000"
  ready_pattern: "ready in"
  stop: "auto"            # auto = kill the launched process; else a stop command
  auth: none              # none | a references path describing the auth steps
limits:
  role_swap_max: 1        # auto arbitration owner-swap cap (see stall-detection.md)
improve:                  # retrospective auto-improvement — see improve-apply.md
  skills_repo: "~/Documents/zenchaine/agent-skills"
  auto_apply: true
  line_budget: 300
```

- **roles**: each value is `claude` or `codex`. Consumed by `role-dispatch.md`.
- **app**: the launch recipe spec-evaluate uses. Required only when a `test.md`
  case uses `playwright`. Missing/incomplete `app` when a `playwright` case
  exists is handled by mode:
  - manual: warn and ask the human (add the recipe, or skip the case).
  - auto: mark the case **blocked** and route to arbitration. Never skip an
    unverified UI requirement silently in an unattended run.
  - In both modes, "config missing (blocked)" is distinct from "test failed".
- **limits.role_swap_max**: the arbitration owner-swap cap; the detector and
  adjudication that consume it are in `stall-detection.md`.
- **improve**: the retrospective self-improvement block. Its fields and behavior
  are in `improve-apply.md`; this file only fixes their place in the schema.

## pipeline-state.json

Location: `.specs/{feature}/pipeline-state.json`, one per feature.

```json
{
  "feature": "user-auth",
  "mode": "auto",
  "issue": 42,
  "language": "en",
  "phase": "spec_review",
  "completed_phases": ["intake", "spec_generate", "inspect"],
  "inspect": {"critical": 0, "warning": 0, "info": 2, "gate": "PASS"},
  "rounds": {
    "spec_review": [
      {"round": 1, "critical": 3, "improvement": 2, "minor": 1,
       "fingerprints": ["a1b2..", "c3d4.."], "gate": "FAIL"}
    ],
    "evaluate": []
  },
  "threads": {"spec_reviewer": "codex-thread-abc"},
  "role_overrides": {},
  "arbitrations": [
    {"phase": "spec_review", "signal": "S1", "decision": "continue", "note": "...", "ts": "..."}
  ],
  "ts_updated": "2026-07-03T00:00:00Z"
}
```

| Field | Meaning |
|-------|---------|
| `feature` / `mode` / `issue` | Run identity (issue is null in manual) |
| `language` | Detected I/O language, set at intake |
| `phase` | Current phase; the loop reads this to decide what to run next |
| `completed_phases` | Phases finished at least once (for the resume summary) |
| `inspect` | Summary of the last inspect result: CRITICAL / WARNING / INFO counts and the gate (`PASS` when no CRITICAL/WARNING). inspect is a single machine check, not a review loop, so it is one summary object here, not a `rounds` array |
| `rounds` | Per-loop round history (`spec_review`, `evaluate`); each entry carries severity counts, finding fingerprints, and the gate. `evaluate` entries also carry a `blocked` count (blocked cases are neither critical nor improvement; see `phases/evaluate.md`). Consumed by stall detection (`stall-detection.md`) |
| `threads` | Peer session ids for resume (e.g. `spec_reviewer`) |
| `role_overrides` | Roles reassigned this run (capability fallback or arbitration swap) |
| `arbitrations` | Stall adjudication records (see `stall-detection.md`) |
| `ts_updated` | Last write timestamp |

### Ownership: orchestrator writes, workers do not even read

The orchestrator is the **only** writer of `pipeline-state.json`. Workers neither
write nor read it — they are coupled to the pipeline only through result files
(`review-spec-{n}.md`, `evaluate-{n}.md`, `report.json`). This keeps a worker
from depending on state shape and keeps state single-writer, so it never races.

### Operations (jq / awk idiom)

Read a field:
```bash
phase="$(jq -r .phase "$state")"
mode="$(jq -r .mode "$state")"
```

Write atomically (never edit in place — write a temp file then move):
```bash
jq '.phase = "inspect"
    | .completed_phases += ["spec_generate"]
    | .ts_updated = (now | todate)' "$state" > "$state.tmp" && mv "$state.tmp" "$state"
```

Append a review round:
```bash
jq --argjson r '{"round":1,"critical":3,"improvement":2,"minor":1,"fingerprints":[],"gate":"FAIL"}' \
   '.rounds.spec_review += [$r]' "$state" > "$state.tmp" && mv "$state.tmp" "$state"
```

Reading a role value from `pipeline.yml` without a YAML parser (awk idiom for the
flat `roles:` block):
```bash
awk '/^roles:/{f=1;next} f&&/^[a-z]/{exit} f&&/spec_reviewer:/{print $2}' "$pipeline"
```

## Resume Behavior

Resume is the default: on startup, if `pipeline-state.json` exists for the target
feature, the orchestrator does not start over.

1. Read the state file.
2. Print a one-block summary: mode, feature, `completed_phases`, the current
   `phase`, and the next action (what running `phase` will do).
3. Continue the loop from `phase`. Completed phases are not re-run; a phase left
   mid-flight (its completion not recorded) is re-entered from its start, which
   is safe because every phase verifies its own output before advancing.

A multi-hour run that is interrupted or crashes resumes from the last recorded
phase — this is the normal path, not an exception.
