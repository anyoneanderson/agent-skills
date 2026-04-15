# Shared-read / Isolated-write Protocol

Covers REQ-030 and REQ-074. During a sprint, multiple agents
(Planner, Generator, Evaluator) plus the Orchestrator all read the
same `shared_state.md` ledger, but only the Orchestrator writes to it.
Every other agent writes to a private `feedback/{role}-{iter}.md`
file. This keeps the ledger race-free and auditable per-iteration.

## File layout (per sprint)

```
.harness/<epic>/sprints/sprint-<n>-<feature>/
├── contract.md                     ← frozen after negotiation (Orchestrator writes, all read)
├── shared_state.md                 ← Orchestrator only writes; all agents read
├── feedback/
│   ├── planner-ruling.md           ← Planner only writes (negotiation stalemate)
│   ├── planner-<iter>.md           ← Planner only writes (rare: replan requests)
│   ├── generator-<round>.md        ← Generator only writes (negotiation rounds)
│   ├── generator-<iter>.md         ← Generator only writes (impl iterations)
│   ├── evaluator-<round>.md        ← Evaluator only writes (negotiation rounds)
│   └── evaluator-<iter>.md         ← Evaluator only writes (impl iterations)
└── evidence/                       ← Evaluator writes run artefacts; all read
```

Negotiation rounds are keyed by `<round>` (1..3). Implementation
iterations are keyed by `<iter>` (1..max_iterations). Numbering spaces
do not overlap in filenames because the prefix (`-<round>.md` vs
`-<iter>.md`) is distinguished by `contract.status` at write time:
`negotiating` → `round`, `active` → `iter`.

Implementation inside harness-loop: keep both series in the same
directory with distinct numbering ranges so the Orchestrator can tell
round from iter via `contract.status` at read time.

## Write permissions (authoritative)

| Path | Orchestrator | Planner | Generator | Evaluator |
|---|---|---|---|---|
| `contract.md` frontmatter | ✅ freeze only | ❌ | ❌ | ❌ |
| `contract.md` Negotiation Log | ✅ copy from feedback | ❌ | ❌ | ❌ |
| `shared_state.md` | ✅ sole writer | ❌ | ❌ | ❌ |
| `feedback/planner-*.md` | ❌ | ✅ | ❌ | ❌ |
| `feedback/generator-*.md` | ❌ | ❌ | ✅ | ❌ |
| `feedback/evaluator-*.md` | ❌ | ❌ | ❌ | ✅ |
| `evidence/*` | ❌ | ❌ | ❌ | ✅ |
| `_state.json` | ✅ sole writer | ❌ | ❌ | ❌ |
| `metrics.jsonl` | ✅ sole writer | ❌ | ❌ | ❌ |
| `progress.md` | ✅ direct append | via PostToolUse hook | via PostToolUse hook | via PostToolUse hook |

`progress.md` is the one shared log where agent writes reach via the
`.harness/scripts/progress-append.sh` hook, not direct file
manipulation. The hook path is race-safe because `>>` appends are
atomic for small writes on POSIX filesystems.

## `shared_state.md` section ownership

The template already carries section comments declaring ownership. In
summary:

| Section | Populated when | Orchestrator action |
|---|---|---|
| `## Plan` | On sprint entry | Copy from contract.md `goal` + `acceptance_scenarios` |
| `## Contract` | On contract freeze | Write `sprint-<n>-contract.md @ <SHA>` |
| `## Negotiation` | After each round | Append 2 lines (G + E) per round; ruling line on stalemate |
| `## WorkLog` | After each Generator turn | Append 1 line: iter, agent, commit, summary pointer |
| `## Evaluation` | After each Evaluator turn | Append 1 line: iter, verdict, per-axis scores, evidence pointer |
| `## Decisions` | On state transitions | Append 1 line: decision type, reason, commit SHA |

Every append is a new line, never an in-place edit. The canonical
append implementation:

```bash
# Pseudocode; real Orchestrator path uses jq-driven values
printf '\n- %s\n' "$line" >> shared_state.md
```

`shared_state.md` must remain human-readable. Agents read it for
context — noise in the ledger costs them tokens.

## Read patterns

Every agent, at turn start, reads:

1. `contract.md` — ground truth for the sprint
2. `shared_state.md` — ledger summary of everything so far
3. The immediately prior counterpart's `feedback/*.md` file (if any)
4. `../../progress.md` tail (Boot Sequence)
5. `../../_state.json` (Boot Sequence)

Agents do NOT read other agents' historical feedback files by default.
If the Orchestrator wants a specific old file in context, it stitches
it into the prompt. Keeping feedback files out of default reads keeps
per-turn token budgets stable across long sprints.

## Atomic write discipline (Orchestrator side)

Three files demand atomicity:

1. **`_state.json`** — every write is:
   ```bash
   jq '<delta>' .harness/_state.json > .harness/_state.json.tmp
   mv .harness/_state.json.tmp .harness/_state.json
   ```
   `mv` within the same filesystem is atomic on macOS and Linux.

2. **`metrics.jsonl`** — always append a single JSON line; never edit.
   A partially-written line on crash is acceptable (tail reader skips
   invalid JSON).

3. **`shared_state.md`** — each append is one `printf` call. Readers
   tolerate the final line arriving mid-read because the parser is
   line-oriented.

The append-only discipline means recovery after crash is: `git
checkout -- path/to/file` restores the last committed state, and the
Orchestrator rebuilds from `_state.json` + the feedback files it can
see on disk.

## Feedback file schema (generic)

All `feedback/{role}-<n>.md` share a common shape:

```markdown
---
role: <planner|generator|evaluator>
iter: <n>              # or round: <r> during negotiation
sprint: <sprint-number>
ts: <ISO-8601-UTC>
# optional, role-specific: see negotiation-protocol.md
---

## Summary

<one paragraph, 1–3 sentences>

## Details

<freeform markdown; may include code, logs, evidence pointers>

## Next action

<what this agent expects to happen next; may be empty>
```

The Orchestrator reads `Summary` to build `shared_state.md` entries.
Details and evidence pointers stay in the feedback file for audit.

## Conflict cases and remediation

| Case | Remediation |
|---|---|
| Two agents wrote to the same `feedback/*` path in the same iter (bug) | Orchestrator renames the later file to `*.dup.<ts>.md`, logs to progress.md |
| Agent edits `shared_state.md` directly | `git status` shows the change at Step 7 commit; Orchestrator reverts the edit (`git checkout --`) and logs |
| Agent writes `_state.json` | Forbidden. Orchestrator overwrites with a correct value from memory + feedback file contents; logs. If `_state.json` was corrupted, halt and surface |
| Evaluator references missing evidence | Treat as test infrastructure failure: evaluator verdict becomes `fail` with `reason: evidence-missing`; Principal Skinner's stagnation logic catches repeated cases |

## Why Shared-read / Isolated-write

- **Race elimination**: multiple agents writing the same file under
  concurrent sub-agent dispatch causes torn writes; isolating writes
  removes the class entirely.
- **Per-agent audit**: reviewing "what did the Generator think on
  iter-5" is `cat feedback/generator-5.md` — one file, one author.
- **Summary vs detail separation**: the ledger stays short (one line
  per event) while feedback files hold the deliberation. Future agents
  paying only the ledger cost see O(sprint events) tokens, not
  O(all agent output).
- **Replay**: an auditor can reconstruct any iteration by reading
  contract.md + shared_state.md + feedback/*-<iter>.md in order.

Design reference: `.specs/harness-suite/design.md` §9.5.
