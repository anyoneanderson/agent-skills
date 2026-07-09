# Phase: intake

Turn the incoming request (manual dialogue or auto Issue) into a spec directory
and the initial state file. This is the only phase where the orchestrator gathers
input; every later phase reads state, not the human.

## Input

- Mode (`manual` / `auto`) and, for auto, the `--issue <N>` number.
- `pipeline.yml` (roles + app recipe) if present; otherwise default roles apply.
- The invoking language (detected from the request; recorded in state).

## Action

**manual:**
1. Confirm the working directory is a git repo. `gh auth` is **not** required
   here — manual mode does not fetch an Issue; `gh` is first needed at the pr
   phase.
2. Hand the natural-language request to spec-generator's interactive mode. The
   human dialogue happens inside the planner run, not here — the orchestrator
   does not itself interview the user beyond launching the planner.
3. The feature name is fixed during that dialogue; it becomes the
   `.specs/{feature}/` directory name.

**auto:**
1. Confirm git repo and `gh auth` (auto fetches the Issue, so `gh` must be
   authenticated now).
2. Fetch the Issue:
   ```bash
   gh issue view <N> --json title,body,labels
   ```
3. Reshape the JSON into a no-dialogue planner input (title + body as the
   requirement, labels as hints). No AskUserQuestion is called in auto mode.
4. Derive the feature name as kebab-case from the Issue title.

**Both modes — run-record `.gitignore`:**

Make sure `.specs/.gitignore` excludes the run records, so a project that tracks
`.specs/` never commits them. If the file does not exist, create it with exactly
this content. If it exists, append only the patterns that are missing — never
modify or remove existing lines (a project may have deliberately opted a record
back in by deleting one).

```
# spec-orchestrate run records — local only (see spec-orchestrate references/pipeline-config.md)
# Delete lines here if your project intentionally commits run records.
pipeline-metrics.jsonl
.orchestrate-active.json
*/pipeline-state.json
*/inspection-report.md
*/.inspection_result.json
*/review-*.md
*/evaluate-*.md
*/evidence/
*/retrospective.md
# agent-delegate artifacts (per-label report/log/pid) when .specs/{feature} is the --out-dir
*/*-report.json
*/*-last.txt
*/*-stdout.jsonl
*/*-stderr.log
*/*.pid
```

## Output

- A decided, writable `.specs/{feature}/` directory path.
- The initial `pipeline-state.json` (see State Update).
- A `.specs/.gitignore` that excludes the run records (created or updated).
- For auto: the reshaped, no-dialogue planner input derived from the Issue.

## Verification

- The `.specs/{feature}/` directory path is decided and writable.
- `.specs/.gitignore` exists and contains the run-record patterns above.
- auto: the Issue exists and was fetched (non-empty title/body). On a `gh`
  auth/not-found error, stop here per §Error Handling.

## State Update

Write the initial `pipeline-state.json`:
```json
{ "feature": "<name>", "mode": "manual|auto", "issue": <N|null>,
  "language": "en|ja", "phase": "spec_generate",
  "completed_phases": ["intake"], "rounds": {}, "threads": {},
  "role_overrides": {}, "arbitrations": [] }
```
The full schema and the jq/awk write idiom are in `../pipeline-config.md`;
intake writes the minimum required to enter spec_generate.

## Transitions

- manual: dialogue complete → **spec_generate**
- auto: Issue fetched and reshaped → **spec_generate**
