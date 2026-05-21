# Foundation-Sprint Guide

Greenfield (or near-greenfield) projects do not yet have the runtime harness-loop assumes: no `pnpm dev` that boots, no test runner config, no OAuth client in the external provider, no database to migrate. Running `/harness-loop` in that state leaves the Evaluator with nothing to score — every acceptance scenario fails on "command not found" rather than on a genuine rubric failure.

`harness-plan` handles this via the **foundation-sprint** concept: a special sprint type inserted at `n=0` whose job is to stand up the dev loop itself. It is **not** rubric-scored; its completion is human-attested.

This guide defines:

1. When a foundation-sprint is inserted
2. The `type: foundation` contract schema and its deliverables-based "rubric replacement"
3. `generator_mode` — how much of the foundation-sprint the Generator handles
4. How `harness-loop` treats a foundation-sprint differently from feature sprints
5. Interactions with existing rules (bundling, dependencies, sprint cap)

## When is a foundation-sprint inserted?

A foundation-sprint is inserted when `harness-plan` Step 3.5 (Foundation Readiness Check) reports severity `YELLOW` or `RED` **and** the user chose to continue (rather than abort and manually bootstrap). See [../SKILL.md §Step 3.5](../SKILL.md) and [../../harness-init/references/scripts.md §foundation-readiness.sh](../../harness-init/references/scripts.md).

The Planner knows via `_state.json.foundation_sprint_needed == true`, which Step 3.5 sets before dispatching the roadmap Planner.

Exactly one foundation-sprint per epic, always `n=0`. If Step 3.5 reports `GREEN`, no foundation-sprint is inserted and all sprints start at `n=1` as before.

## Foundation readiness check (Step 3.5)

`harness-plan` Step 3.5 runs the checker before any Planner sub-agent
dispatch:

```bash
.harness/scripts/foundation-readiness.sh --epic <epic>
```

The script writes `.harness/<epic>/foundation-readiness.md` and emits a
JSON summary to stdout:

```json
{"severity":"GREEN|YELLOW|RED","verified_at":"<ISO-8601>","ok":[...],"missing":[...],"unknown":[...]}
```

Severity is classified as follows:

- `GREEN`: all probes are ok
- `YELLOW`: 1-2 probes are missing and `package_manifest` is ok
- `RED`: `package_manifest` is missing, or 3 or more probes are missing

When severity is `RED`, `harness-plan` must ask:

```text
Near-greenfield detected. Harness cannot score sprints without a working dev loop. How do you want to proceed?
```

Options:

- `Abort and set up foundation manually (Recommended)`
  Print the missing-probes checklist from `foundation-readiness.md`
  plus a project-appropriate bootstrap outline derived from product-spec
  Constraints (for example `pnpm create next-app`, `prisma init`, GCP
  OAuth client setup, `.env.example`, and similar). Exit cleanly.
- `Insert Sprint 0 (foundation-sprint) and continue`
  Set `foundation_sprint_needed=true` and continue into roadmap
  generation. Planner inserts sprint-0 in Step 5.
- `Cancel`
  Exit without changing state beyond `_state.json.current_epic`.

When `--auto-approve-roadmap` is set, a `RED` result auto-selects
`Insert Sprint 0 (foundation-sprint) and continue` instead of aborting.
The flag's contract is to skip interactive approvals while staying on
the continue path.

Write `_state.json.foundation_readiness` with the JSON summary as soon
as the check finishes. Write `_state.json.foundation_sprint_needed=true`
when severity is `YELLOW`, or when severity is `RED` and the selected
path is `Insert Sprint 0 (foundation-sprint) and continue`. Step 5
Planner reads these keys when deciding whether sprint-0 must be
inserted.

## Schema — `type: foundation` sprint entry

In `roadmap.md.sprints[]`:

```yaml
- n: 0
  feature: dev-environment-foundation   # or project-appropriate slug
  type: foundation                      # third value beyond split|bundled
  deliverables:                         # replaces `rubric`
    - package_manifest                  # e.g. package.json committed
    - runtime_boots                     # `pnpm dev` returns 200 on /
    - test_runner_configured            # playwright.config.ts / pytest.ini present
    - env_example_committed             # .env.example covers all required keys
    - external_setup_doc                # SETUP.md explains GCP/Slack/etc.
    - dev_db_available                  # docker-compose up or SQLite file
  human_attestation_required: true      # always true for foundation
  generator_mode: scaffold              # none | scaffold | optional
  dependencies: []                      # always empty (foundation is first)
  risk: medium                          # for human tracking only; not scored
```

Fields:

| Field | Type | Required | Notes |
|---|---|---|---|
| `type` | literal `"foundation"` | yes | enables all the special handling below |
| `deliverables` | string[] | yes | must be a subset of the well-known keys below |
| `human_attestation_required` | bool | yes | foundation-sprints require it — set true |
| `generator_mode` | `none` \| `scaffold` \| `optional` | yes | see next section |

A `type: foundation` entry MUST NOT have `rubric`, `acceptance_scenarios`, `bundling`, `bundled_with`. The `contract.md` generated by the Planner omits those fields entirely.

### Well-known deliverable keys

These map 1:1 to `foundation-readiness.sh` probes so Step 3.5 can auto-populate the list from missing probes:

| Key | Probe | "Done" means |
|---|---|---|
| `package_manifest` | manifest file exists | language-appropriate manifest committed |
| `runtime_boots` | runtime command returns 0 | e.g. `pnpm dev` serves the index route with a 2xx |
| `test_runner_configured` | config file present | evaluator_tools chosen in `_config.yml` can run a trivial smoke |
| `env_example_committed` | `.env.example` or equivalent exists | all secrets required by Constraints have placeholder lines |
| `external_setup_doc` | `SETUP.md` / `docs/setup.md` exists | manual external provider steps (GCP console, Slack app, etc.) are written down |
| `dev_db_available` | docker-compose or local DB file exists | Evaluator can run DB-dependent AS in later sprints |
| `tracker_wired` | `gh auth status` + remote origin | only meaningful when `tracker=github` |

Custom deliverables may be added beyond this list. They become human-attested checklist items with no automated probe.

## `generator_mode` — Generator involvement

The Generator writes code; foundation-sprints mix code with external (human-only) steps. `generator_mode` controls what the Generator attempts:

| Mode | Generator writes | Human must do |
|---|---|---|
| `none` | nothing | everything (manifest, scaffolding, external setup, env file, doc) |
| `scaffold` | manifest + minimal scaffolding (`pnpm create next-app` equivalent, `.env.example`, basic `SETUP.md` skeleton) | external provider setup (GCP, Slack), fill real secrets into `.env.local`, verify `runtime_boots` |
| `optional` | everything in `scaffold` + docker-compose.yml + ORM init (e.g. `prisma init`) + test runner config skeleton | external provider setup, secrets, first migration run if interactive |

Default: `scaffold` (safest middle ground — Generator bootstraps what it can, human handles what requires external-system access).

The Planner chooses `generator_mode` based on how many deliverables are pure-code vs. pure-human. If every deliverable is external-setup-only (e.g. "GCP OAuth client"), degrade to `none`.

## `harness-loop` behavior on foundation-sprint

`harness-loop` detects `contract.type == "foundation"` in its Boot Sequence and branches:

1. **No negotiation phase** — there is no rubric to negotiate thresholds on. Skip directly from contract-draft to implementation.
2. **Generator runs at most once** — regardless of `_config.yml.max_iterations`. No G⇄E iteration loop.
3. **Evaluator is replaced by a deliverables verifier**:
   - For each deliverable, run the matching `foundation-readiness.sh --check <key>` probe
   - Record per-deliverable status in `feedback/verification-<iter>.md` (single iter)
   - No rubric scoring, no `metrics.jsonl` entry for rubric axes
4. **Human attestation gate** — after verification, set `_state.json.phase = "foundation-attest"` and `pending_human = true`. Surface the verification report to the user via `AskUserQuestion`:
   - `"Foundation deliverables verified (N/M probes pass). Attest complete?"` options: `Attest / Fix & retry / Abort`
5. **On attestation** — re-run `foundation-readiness.sh --epic <epic>`, write the fresh summary back to `_state.json.foundation_readiness`, set `_state.json.foundation_sprint_needed=false`, then advance `_state.json.current_sprint` to 1 and continue to the next normal sprint's negotiation.
6. **PR creation** — a single PR for the foundation-sprint, title prefix `[sprint-0] foundation:`. Body lists deliverables and verification results, not rubric scores.

### Phase additions to `_state.json`

Two new `phase` values are introduced for foundation-sprints:

- `foundation-setup` — Generator is writing / human is doing external setup
- `foundation-attest` — verification ran, waiting for human attestation

Both are on the stop-guard non-loop phase allowlist (see [../../harness-init/references/scripts.md §stop-guard decision matrix](../../harness-init/references/scripts.md)).

## Interactions with existing rules

### Sprint cap

`roadmap-guide` limits epics to ≤6 sprints. The foundation-sprint does **not** count against this cap (it is infrastructure, not feature delivery). The limit of 6 applies to feature sprints `n≥1`.

### Dependencies

The foundation-sprint is always `n=0` with `dependencies: []`. All feature sprints with no other explicit dependencies should implicitly add `dependencies: [0]` after Planner inserts the foundation-sprint. The Planner handles this rewrite automatically.

### Bundling

A foundation-sprint cannot bundle with another sprint. It is always its own PR. If the Planner encounters a reason to bundle foundation work with a feature sprint, that's a signal the foundation-sprint scope is wrong — re-scope so feature sprint 1 starts from a bootable baseline.

### Replan

`/harness-plan --replan` on an epic whose foundation-sprint is already merged does NOT re-insert one. Step 3.5 re-runs readiness probes and finds `GREEN` because the foundation-sprint's merged PR now makes `runtime_boots` pass. If probes regress (e.g. dependency breakage), Planner inserts a **remediation sprint** at the current `n`, not at `n=0` — call it `foundation-remediation` and treat it like any feature sprint for accounting, but mark it `type: foundation` to skip rubric scoring.

## Contract template

See [../../harness-init/references/templates/foundation-sprint-checklist.md](../../harness-init/references/templates/foundation-sprint-checklist.md) for the full `contract.md` shape used when `type: foundation`.

## Authoring checklist (Planner-side)

When drafting a foundation-sprint contract, the Planner must:

1. Read `foundation-readiness.md` and copy the missing probes into `deliverables` verbatim
2. Set `generator_mode` based on the deliverables mix (see table above)
3. Write a short "Setup prerequisites" section in the contract body listing manual external steps (GCP console clicks, domain verification, Slack app creation) that no script can automate
4. Set `human_attestation_required: true` always
5. Do NOT write `acceptance_scenarios`, `rubric`, `bundling`, `bundled_with`
6. Do NOT set `max_iterations` or `threshold` placeholders (there is no iteration loop here)

## Authoring checklist (Issue-side)

The tracker Issue body for a foundation-sprint differs from a feature sprint. See [issue-create.md §Sprint-0 body template](issue-create.md) for the canonical format (deliverables checklist, external setup section, human attestation section).

## Summary

A foundation-sprint:

- is optional, inserted only on greenfield detection
- is identified by `type: foundation`
- replaces `rubric` / `acceptance_scenarios` with `deliverables`
- runs once, with no G⇄E loop
- requires human attestation to close
- lets harness-loop proceed to feature sprints from a verified baseline
