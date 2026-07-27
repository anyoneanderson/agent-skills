---
name: magi
description: |
  Put a hard question to three independent LLM CLIs from different vendors and
  return a tallied verdict (decision mode) or a cross-checked research report
  (research mode), always with a matrix showing who said what. The three sages
  are MELCHIOR (Claude), BALTHASAR (Codex) and CASPER (Grok); they are
  configurable. Use it when one model's blind spot would be expensive: choosing
  between options, or checking whether a "current" fact is still true.

  English triggers: "ask the MAGI council", "put this to the MAGI", "three-model
  council", "get three independent opinions", "cross-check this with three models"
  日本語トリガー: 「MAGI に諮って」「3賢者で合議」「3体で合議」「3モデルで多数決」「3つのモデルで裏取りして」
license: MIT
---

# magi — Three-Sage Council for Decisions and Research

Ask three independently running LLM CLIs the same question, then tally or merge
their answers. You are the host: you run the council and edit the record, and
you never cast a vote.

The runnable interface is `references/scripts/magi-run.sh`. It dispatches the
sages in parallel and writes a summary file; every semantic judgement below is
yours. Prompt and output templates are in
[references/council.md](references/council.md) (日本語:
[council.ja.md](references/council.ja.md)); the sage configuration format and
CLI setup are in [references/sages.md](references/sages.md) (日本語:
[sages.ja.md](references/sages.ja.md)).

## Language Rules

1. **Auto-detect input language** → output in the same language
2. Japanese input → Japanese output, use `references/*.ja.md`
3. English input → English output, use `references/*.md`
4. Explicit override takes priority (e.g., "in English", "日本語で")

The prompts sent to the sages should be written in the user's language, so their
rationales come back in a language the user can read.

## The Council

| Display name | Default CLI | Model family |
|---|---|---|
| MELCHIOR | `claude` | Anthropic Claude |
| BALTHASAR | `codex` | OpenAI GPT |
| CASPER | `grok` | xAI Grok |

Three sages, or two in a degraded council. There is no fourth seat: the tally
rules below assume three. Which CLI fills each seat is configuration, not part
of this skill — see `references/sages.md` to swap one out.

## Prerequisites

- **The question is sent to every configured sage's provider.** By default that
  means three separate companies (Anthropic, OpenAI, xAI) receive the full text
  of the question and any context pasted into it. Before convening the council
  on anything confidential — customer data, credentials, unreleased plans,
  client-identifying details — show the user which sages are configured and
  confirm that sending the question to all of them is acceptable. If it is not,
  do not convene the council; either narrow the question until it is safe to
  send, or use a single trusted agent instead.
- The sage CLIs must be installed and authenticated. Setup and login commands
  are in `references/sages.md`. Missing CLIs are detected by preflight, not
  assumed.
- `jq` must be on PATH; the script needs it to read its configuration.
- **Research mode depends on the sages being able to search the web**, and each
  CLI gates tool use differently when running headless. The bundled config carries
  the flags that permit it for the three default sages. If a sage has been swapped
  out, check its search permissions before convening a research council: a CLI
  that denies its own search tool answers from training data instead, and one that
  waits for tool approval ends the run cancelled with no usable answer. The
  per-sage details are in `references/sages.md`.
- Answers are stored unencrypted under the run directory (default
  `${TMPDIR:-/tmp}/magi-runs/`), which the skill never deletes. Tell the user
  where it is; deleting it is their call.

## Your Role as Host

Two rules govern everything that follows.

**You do not vote (CON-001).** You have no position in the tally, even when you
believe all three sages are wrong. Your opinions belong nowhere in the output —
not in the tally, not in the matrix, not in a note beside it. When you think the
council reached a poor conclusion, the only thing you may add is a note about the
council's own workings: how many sages answered, which round produced the result,
what a sage stated it was unsure of, that a claim rests on training data. Such a
note carries no recommendation of your own, stated or implied; if it would steer
the user toward a different choice, it is a vote wearing a different hat, and it
does not belong in the output. Never alter what a sage said: do not write a
sage's answer for it, complete a truncated one, or "correct" a rationale.

**You make the semantic judgements; the script does not (CON-002).** Deciding
whether two differently worded positions mean the same thing, whether two
findings describe the same fact, who says what to whom in a debate, and how the
matrix reads — all yours. `magi-run.sh` starts processes, enforces timeouts,
saves raw output and aggregates status. Never ask it to interpret an answer, and
do not add retry or fallback logic around it (see REQ-010 in Error Handling).

## Execution Flow

### Step 1: Create the run directory

One directory per council, so the audit trail stays self-contained (NFR-003).

```bash
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
out_dir="${TMPDIR:-/tmp}/magi-runs/${run_id}"
mkdir -p "${out_dir}/round1"
# Every command below uses this; the path is relative to this skill's directory,
# which is not the working directory once the skill is installed elsewhere.
magi_run="<this skill directory>/references/scripts/magi-run.sh"
```

Save the user's question verbatim to `${out_dir}/question.md` before rewriting
it into a prompt, so the record shows what was actually asked.

### Step 2: Detect the mode

Read the question and classify it:

| Signal in the question | Mode |
|---|---|
| Named alternatives to compare, "should we…", "which one", "A or B" | `decision` |
| "look into", "what is the current state of", "find out", "summarize" | `research` |
| Both, or neither clearly | Ask the user |

When it is genuinely ambiguous, do not guess. Ask with bilingual options:

- question: "How should the council handle this?" / "MAGI にどう諮りますか？"
- options:
  - "Decision (vote)" / "decision（採決）" — three positions, tallied to a verdict
  - "Research (aggregate)" / "research（調査統合）" — three investigations, cross-checked

### Step 3: Preflight

```bash
preflight="$("$magi_run" --out-dir "$out_dir" --preflight-only | tail -1)"
```

Read the file it names and branch on **`available_count`**, not on `missing`. A
config that lists only two sages leaves `missing` empty and still gives you a
two-sage council, so an empty `missing` is not evidence that the council is
complete. Fewer than three available sages means
[Degraded Council](#degraded-council): confirm with the user before dispatching
anything.

### Step 4: Round 1 — ask all three, independently

Write one prompt from the templates in `references/council.md` to
`${out_dir}/round1/prompt.md`. It must contain the question, the required answer
format, and nothing about the other sages: **round 1 must not reveal that other
sages exist or what they might say.** Independence is what makes agreement
meaningful.

Required answer shapes (full templates in `references/council.md`):

| Mode / round | JSON the sage must return |
|---|---|
| decision, round 1 | `{"position": "...", "rationale": "...", "confidence": "high\|medium\|low"}` |
| decision, debate | `{"action": "keep\|switch\|compromise", "position": "...", "rationale": "...", "confidence": "..."}` |
| research, round 1 | `{"findings": [{"claim": "...", "evidence": "...", "source": "..."}]}` |
| research, deliberation | `{"verdicts": [{"finding_id": "...", "verdict": "agree\|conditional\|reject", "rationale": "..."}]}` |

Deliberation always uses the batched shape above, because one prompt normally
carries several findings and the `finding_id` is what ties a verdict back to the
claim it judges. The single-object form
`{"verdict": "...", "rationale": "..."}` is acceptable only when that sage's
prompt holds exactly one finding. A schema passed with `--schema-file` must be
the batched one for the same reason.

Optionally write the matching JSON schema to `${out_dir}/schema.json` and pass
`--schema-file`. Sages that declare `schema_args` (CASPER by default) are then
constrained to the shape; the others rely on the prompt instruction alone.

```bash
summary="$("$magi_run" \
  --prompt-file "${out_dir}/round1/prompt.md" \
  --out-dir "$out_dir" --round round1 | tail -1)"
# Add --schema-file "${out_dir}/schema.json" to constrain the sages that support
# it, and --sages MELCHIOR,BALTHASAR to dispatch to a subset.
```

The last line of stdout is the path of `summary.json`. Exit 2 means a
precondition failed and nothing was dispatched.

### Step 5: Read the answers

`summary.json` holds one entry per sage: `name`, `cli`, `status`
(`ok` / `timeout` / `error`), `exit_code`, `duration_ms`, `answer`,
`stdout_file`, `stderr_file`, `prompt_file`.

For each sage with `status: "ok"`, parse `answer` as JSON. Sages wrap JSON in
code fences or add a sentence of prose more often than they should, so strip
fences and take the first complete JSON object before deciding an answer is
broken. If nothing parses, or a required field is missing, treat that sage as
**invalid answer** — the same degraded case as a timeout (REQ-010). Never
reconstruct the missing content yourself.

Then continue with [Tally](#tally-decision-mode) or
[Research Aggregation](#research-aggregation-research-mode).

## Tally (decision mode)

1. Take each sage's `position`.
2. Group positions **by meaning, not by string**. "TOML", "I'd go with TOML" and
   "TOML, for the schema stability" are one position. A position that merely
   overlaps — same choice but a materially different scope or condition — is a
   different position.
3. When you cannot tell whether two positions are the same, treat them as
   **different**. The cost of being wrong that way is one debate round; the cost
   of the reverse is silently discarding a disagreement the user needed to see.
4. Write the grouping down as a position → supporting sages table. This table
   feeds the matrix, so keep it even when the answer is obvious.
5. Any position held by two or more sages **passes**. Go straight to
   [Result Matrix](#result-matrix) — no debate, no confirmation round.
6. All three positions different → [Debate](#debate-decision-mode).

Confidence never overrides the count: a `low`-confidence pair beats a
`high`-confidence single. Report the confidences in the matrix and let the user
weigh them.

## Debate (decision mode)

Only when all sages hold different positions.

1. Create `${out_dir}/debate1/` and write **one prompt per sage** to
   `prompt-<SAGE>.md` (e.g. `prompt-MELCHIOR.md`). Each contains: the original
   question, that sage's own previous answer, and the other two positions with
   rationales, attributed to **Sage A** and **Sage B**.
2. **Anonymize the others.** Never name the model or CLI behind Sage A or Sage B.
   A sage that learns which vendor it is arguing with weights the brand instead
   of the argument. Keep the mapping (which real sage is A and which is B, per
   recipient) in your own notes so you can attribute positions in the matrix, and
   keep it out of every prompt.
3. Ask for `keep` (hold the position), `switch` (adopt another) or `compromise`
   (propose a third), each with a rationale and a confidence.
4. Dispatch once. All sages have per-sage prompt files, so `--prompt-file` is
   not needed:

   ```bash
   summary="$("$magi_run" --out-dir "$out_dir" --round debate1 | tail -1)"
   # In a degraded council, add --sages with the two available names.
   ```

5. Re-tally with the same rules. A `compromise` is a new position, compared by
   meaning against everything else — two sages proposing compatible compromises
   is a pass.
6. Still three different positions → run `debate2` the same way, showing each
   sage the other two **post-debate** positions.
7. After `debate2`, stop. **At most two debate rounds.** If nothing has two
   supporters, the council reaches **no consensus**: report the final positions
   plus a breakdown of what they actually disagree about, and hand the decision
   back to the user. Do not break the tie yourself, and do not run a third round.

## Research Aggregation (research mode)

1. Split each sage's `findings` into individual claims.
2. Cluster claims that assert the same fact, even when the wording, framing or
   granularity differs. Two claims that agree on the fact but disagree on a
   detail (a date, a number, a version) are one cluster with a noted conflict,
   not two findings.
3. **Two or more sages → adopted.** Record the support count and keep each
   sage's evidence and source.
4. **One sage only → deliberation.** Assign each solo finding an id, then write
   **one prompt per sage** to `${out_dir}/deliberation1/prompt-<SAGE>.md`
   containing only the findings that sage did **not** report, each with its claim,
   evidence, source and id. Ask for `agree` / `conditional` / `reject` with a
   rationale per finding.

   Per-sage prompts are what keep a sage from reviewing its own claim. A single
   shared prompt cannot: as soon as two sages each have a solo finding, that
   prompt either asks each of them to judge its own finding or omits a review
   that was needed. Dispatch all of them in one parallel run — with per-sage
   prompt files, `--prompt-file` is not used:

   ```bash
   summary="$("$magi_run" --out-dir "$out_dir" --round deliberation1 | tail -1)"
   # A sage with nothing to review has no prompt file, so exclude it with
   # --sages; the script refuses to dispatch a sage it has no prompt for.
   ```

   Batch every finding a sage must review into that sage's prompt. There is
   **one deliberation pass**, so a second circulation is not available.

5. Classify each solo finding from the verdicts:

   | Verdicts | Result |
   |---|---|
   | both `agree` | adopted |
   | `agree` + `conditional`, or both `conditional` | conditionally adopted, note the conditions |
   | both `reject` | rejected |
   | `agree` + `reject` | conditionally adopted, note that the council split and quote both sides |
   | `conditional` + `reject` | conditionally adopted, note the condition and the rejection side by side |

   A sage that fails to answer the deliberation does not veto: classify on the
   verdicts you have, and record the missing one. With a single verdict (degraded
   council), `agree` → adopted, `conditional` → conditionally adopted,
   `reject` → rejected.

6. Assemble the report: adopted facts with support counts, conditionally adopted
   with notes, rejected with reasons, then a per-sage summary. A rejected claim
   stays in the report — the fact that one sage believed it is a signal.

## Result Matrix

Every answer ends with a matrix. Full templates are in
`references/council.md`; the required elements are:

- **A verdict headline first**: the position that passed and the count
  (`passed — TOML (2 to 1)`), or `no consensus — returned to the user`, or for
  research a one-paragraph summary of the merged report.
- **One row per sage**, in configuration order, showing the display name with
  its actual CLI (`MELCHIOR (claude)`), the position, the gist of the rationale,
  the confidence, and what the debate changed. The debate column is part of the
  matrix even when the vote passed in round 1: fill it with `not held` rather
  than removing it, so the reader can tell a council that never debated from one
  whose debate you did not report.
- **The minority opinion, always.** Name the sage, state its position and
  rationale, and say plainly that it lost the vote but is recorded. A council
  whose dissent is not written down is a single model with extra steps.
- **A row for every sage that could not answer**, reading
  `no answer (timeout)`, `no answer (error)` or `no answer (invalid answer)`.
  Never drop the row — a silent sage is different from an absent one, and the
  user cannot see the difference if you delete it.
- **The audit log line**: the run directory path, noting that it holds every
  prompt and every raw answer.

For no consensus, add a breakdown of the disagreement: for each contested point,
what each sage claimed. That breakdown is what makes the failed vote useful.

## Degraded Council

### Fewer than three sages, found before dispatch

`preflight.json` reports `available_count` (sages whose CLI was found), `missing`
(CLIs that were not) and `sages_file` (the config actually read). Branch on
`available_count` alone. A council can be short for two different reasons, and
only one of them shows up in `missing`: a CLI is not installed, or the config
lists fewer than three sages in the first place.

**`available_count` ≥ 3** — proceed normally.

**`available_count` == 2** — confirm before dispatching, and say which reason
applies: name the missing CLI with its install command from
`references/sages.md`, or name `sages_file` as a config with only two sages. Then
ask:

- question: "Only two sages are available. Continue with a two-sage council?" / "利用できる賢者が2体だけです。2体で合議を続けますか？"
- options:
  - "Continue with two" / "2体で続行" — two-sage rules below: 2-0 passes, a 1-1 split gets one debate round
  - "Abort" / "中止" — stop now; install the missing CLI or fix the config, then re-run

Ask this question on both paths. A two-sage roster produces a two-sage verdict
whether or not anything was missing, and the user is entitled to know the vote
they are about to receive comes from two models.

When a CLI is missing, pass `--sages` listing exactly the available sages: the
script refuses to dispatch a round while any selected sage's CLI is missing, so
narrowing the selection is required, not optional. When the roster itself holds
two sages, the default selection is already those two and `--sages` is
unnecessary.

**`available_count` ≤ 1** — do not dispatch. A single model is not a council.
Report which CLIs are missing or how the config is short, give the install and
login commands, and stop.

### Two-sage rules

These apply however the council became two — a missing CLI, a roster of two, or a
sage lost mid-round.

- decision: agreement 2-0 passes. A 1-1 split gets **one** debate round
  (`debate1`), never two; if the positions still differ after it, the result is
  no consensus and goes back to the user.
- research: two sages reporting the same fact → adopted. A solo finding
  circulates to the one remaining sage (still a single pass), and that single
  verdict decides it: `agree` → adopted, `conditional` → conditionally adopted,
  `reject` → rejected.

### Failure during the round

A sage with `status` `timeout` or `error`, or an answer you could not parse, is
out of this round. Continue with the sages that did answer, under the two-sage
rules, and record the reason in the matrix.

**Do not re-send the prompt to a failed sage within the same round (REQ-010).**
One sage, one round, one answer — that is what makes the run directory readable
as a record, and a retry also spends the timeout budget twice.

If fewer than two sages produced a usable answer, there is nothing to tally.
Show the answers you did get, name the failures and their reasons, point to the
audit log, and stop.

## Error Handling

| Situation | Response |
|---|---|
| Question may contain confidential material | Show the configured sages and confirm external transmission before dispatching |
| `jq` missing | Script exits 2 and records `jq_available: false`; report the install command and stop |
| `available_count` is 2 (a CLI is missing, or the config lists only two sages) | Ask "continue with two / abort" (bilingual) before dispatching |
| `available_count` is 0 or 1 | Stop; report install and login commands, or the short config |
| Script exits 2 | A precondition failed and nothing was sent; read its stderr, fix the cause, then dispatch again |
| `status: timeout` | Sage exceeded `timeout_seconds` (default 600). Continue degraded, record `no answer (timeout)` |
| `status: error` | Sage failed or printed an unusable envelope; check its `stderr_file`. Quota exhaustion arrives this way |
| Answer is not valid JSON after fence stripping | Treat as invalid answer; degrade, never rewrite it |
| Fewer than two usable answers | Do not tally; present what arrived plus failure reasons and stop |
| Debate exhausted (two rounds with three sages, one with two) | Report no consensus with the disagreement breakdown, stating how many rounds ran; do not decide for the user |
| Config declares more than three sages | Script exits 2; the tally rules support three at most |
| Sage asks a clarifying question instead of answering | Treat as invalid answer for this round; if two or more do it, stop and sharpen the question with the user |
| Research answer shows no sign of searching, or the sage reports a denied tool or a cancelled run | Its adapter is missing the flags that permit web search (`references/sages.md`). Record the sage as degraded for this round, fix the config before the next council, and do not re-send inside this one |

## Usage Examples

```bash
# Decision: three positions, tallied
run_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"; out_dir="${TMPDIR:-/tmp}/magi-runs/${run_id}"
mkdir -p "${out_dir}/round1"
# ... write question.md, round1/prompt.md, schema.json ...
"$magi_run" --out-dir "$out_dir" --preflight-only
"$magi_run" --prompt-file "${out_dir}/round1/prompt.md" \
  --out-dir "$out_dir" --round round1 --schema-file "${out_dir}/schema.json"

# Debate: one anonymised prompt per sage, single dispatch
# ... write debate1/prompt-MELCHIOR.md, prompt-BALTHASAR.md, prompt-CASPER.md ...
"$magi_run" --out-dir "$out_dir" --round debate1

# Deliberation: per-sage prompts holding only the findings that sage did not report
# ... write deliberation1/prompt-BALTHASAR.md, prompt-CASPER.md ...
"$magi_run" --out-dir "$out_dir" --round deliberation1 --sages BALTHASAR,CASPER

# Degraded council: dispatch to the sages that exist
"$magi_run" --prompt-file "${out_dir}/round1/prompt.md" \
  --out-dir "$out_dir" --round round1 --sages BALTHASAR,CASPER
```

Run the script with `--help` for the full argument contract.

## Notes

- Agreement between three models is evidence, not proof. Shared training data
  produces shared errors, and the matrix exists so the user can see how thin or
  broad the agreement was.
- A council is slow and costs three inferences. Use it where a wrong answer is
  expensive — architectural choices, "is this still true" checks on fast-moving
  facts — not for questions one agent can answer.
- The run directory is the deliverable when the council disappoints. Point the
  user at it rather than paraphrasing what a sage "basically said".
