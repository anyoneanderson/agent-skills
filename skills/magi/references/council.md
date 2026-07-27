# Council Protocol — Prompt and Output Templates

Everything the host sends to a sage, and everything it shows the user, in one
place. `SKILL.md` owns the rules; this file owns the wording.

Write the prompts in the user's language so their rationales come back readable
to the user — the Japanese versions of these templates are in
[council.ja.md](council.ja.md).

## Conventions

- `{{DOUBLE_BRACES}}` marks a slot the host fills in. No brace survives into a
  prompt file.
- One prompt file per dispatch, saved under the run directory:
  `round1/prompt.md`, `debate1/prompt-<SAGE>.md`, `deliberation1/prompt.md`.
- Every template ends with the answer-format instruction. Keep it last: it is
  the part a sage is most likely to skip when it is buried mid-prompt.
- Never name the other sages, their vendors or their models in any prompt. Round
  1 must not reveal that other sages exist at all; debate and deliberation
  prompts refer to them only as **Sage A** and **Sage B**.

## 1. Decision, round 1 — the initial question

Sent identically to every sage. This is the independence round: no sage may
learn that anyone else was asked.

```text
You are an expert advisor. Answer the question below on your own judgement.

## Question

{{QUESTION}}

## Options under consideration

{{OPTIONS — one per line; omit this section if the question is open-ended}}

## Context

{{CONTEXT — constraints, environment, what has already been tried, what the
decision affects. Include only what the advisor needs; everything here is sent
to an external service.}}

## What to do

1. Choose one position. If the options above are exhaustive, choose from them;
   otherwise you may propose a different one.
2. State why, in at most five sentences. Name the decisive trade-off rather
   than listing every consideration.
3. Rate your confidence: high, medium or low. Base it on how much the decision
   depends on facts you are unsure of.

Do not ask clarifying questions — decide with the information given and note any
assumption inside your rationale.

## Answer format

Reply with one JSON object and nothing else. No prose before or after it, no
code fence.

{"position": "<your position, one line>", "rationale": "<why, max 5 sentences>", "confidence": "high|medium|low"}
```

## 2. Decision, debate — keep, switch or compromise

One prompt **per sage**, only when all positions differ. Each recipient sees its
own previous answer and the other two anonymised.

```text
You are an expert advisor reconsidering a decision. Two other advisors answered
the same question independently and reached different conclusions. Their answers
are below, anonymised. You do not know who they are, and that is deliberate:
judge the arguments, not their source.

## Question

{{QUESTION}}

## Your previous answer

Position: {{OWN_POSITION}}
Rationale: {{OWN_RATIONALE}}
Confidence: {{OWN_CONFIDENCE}}

## Sage A

Position: {{SAGE_A_POSITION}}
Rationale: {{SAGE_A_RATIONALE}}
Confidence: {{SAGE_A_CONFIDENCE}}

## Sage B

Position: {{SAGE_B_POSITION}}
Rationale: {{SAGE_B_RATIONALE}}
Confidence: {{SAGE_B_CONFIDENCE}}

## What to do

Pick exactly one action:

- keep — hold your position. Say what in A's or B's argument fails to move you.
- switch — adopt A's or B's position. Say what convinced you, and put the
  position you are adopting in the "position" field.
- compromise — propose a position that resolves the disagreement. Put the new
  position in the "position" field and say which concern of A's or B's it
  addresses.

Changing your mind on a good argument is correct behaviour here, and so is
holding a position you still believe. Do not switch to end the disagreement.

## Answer format

Reply with one JSON object and nothing else. No prose before or after it, no
code fence.

{"action": "keep|switch|compromise", "position": "<your position after this round, one line>", "rationale": "<why, max 5 sentences>", "confidence": "high|medium|low"}
```

For a second round (`debate2`), reuse this template with the **post-debate**
positions of the other two sages, and set `Your previous answer` to the answer
from `debate1`.

## 3. Research, round 1 — independent investigation

Sent identically to every sage. As in decision round 1, no sage learns that
others were asked.

```text
You are a researcher. Investigate the topic below and report what you find.

## Topic

{{QUESTION}}

## Scope

{{SCOPE — the period, versions, regions or sources that matter; what is out of
scope. Omit this section when the topic speaks for itself.}}

## What to do

1. Report each finding separately. Between three and eight findings is the
   useful range; fewer if the topic is narrow.
2. For each finding, state the claim in one sentence, the evidence you are
   relying on, and where it came from.
3. Distinguish what you verified from what you are recalling. If a claim rests
   on your training data and could have changed since, say so in the evidence
   field.
4. Report a finding that contradicts the premise of the question. That is the
   most valuable thing you can return.

If you cannot support a claim, leave it out rather than reporting it weakly.

## Answer format

Reply with one JSON object and nothing else. No prose before or after it, no
code fence.

{"findings": [{"claim": "<one sentence>", "evidence": "<what supports it, and how current it is>", "source": "<URL, document, command output, or 'training data as of <date>'>"}]}
```

## 4. Research, deliberation — reviewing a solo finding

Sent to the sages that did **not** report the finding. One pass only, so batch
every solo finding of the round into this single prompt.

```text
You are reviewing claims that another researcher reported and you did not. For
each one, judge whether it should enter a merged report.

## Topic

{{QUESTION}}

## Claims to review

### {{FINDING_ID}}

Claim: {{CLAIM}}
Evidence offered: {{EVIDENCE}}
Source offered: {{SOURCE}}

{{repeat one block per solo finding}}

## What to do

For each claim, return one verdict:

- agree — you believe it is correct and adequately supported.
- conditional — it holds only under a condition, only for some versions or
  regions, or only if a specific point is verified. Name that condition.
- reject — you believe it is wrong or unsupported. Say what makes you think so.

Judge the claim, not the wording. Do not agree merely because a claim sounds
plausible, and do not reject one merely because you had not reported it.

## Answer format

Reply with one JSON object and nothing else. No prose before or after it, no
code fence.

{"verdicts": [{"finding_id": "<the id above>", "verdict": "agree|conditional|reject", "rationale": "<why, max 3 sentences; state the condition when conditional>"}]}
```

When exactly one solo finding is under review, the single-verdict form is
equivalent and simpler:

```text
{"verdict": "agree|conditional|reject", "rationale": "<why, max 3 sentences>"}
```

## 5. JSON schemas for `--schema-file`

Sages that declare `schema_args` (CASPER by default) can be constrained to the
shape instead of being asked politely. Write the matching schema to the run
directory and pass `--schema-file`.

Decision, round 1:

```json
{
  "type": "object",
  "properties": {
    "position": { "type": "string" },
    "rationale": { "type": "string" },
    "confidence": { "type": "string", "enum": ["high", "medium", "low"] }
  },
  "required": ["position", "rationale", "confidence"],
  "additionalProperties": false
}
```

Decision, debate — as above plus:

```json
{
  "type": "object",
  "properties": {
    "action": { "type": "string", "enum": ["keep", "switch", "compromise"] },
    "position": { "type": "string" },
    "rationale": { "type": "string" },
    "confidence": { "type": "string", "enum": ["high", "medium", "low"] }
  },
  "required": ["action", "position", "rationale", "confidence"],
  "additionalProperties": false
}
```

Research, round 1:

```json
{
  "type": "object",
  "properties": {
    "findings": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "claim": { "type": "string" },
          "evidence": { "type": "string" },
          "source": { "type": "string" }
        },
        "required": ["claim", "evidence", "source"],
        "additionalProperties": false
      }
    }
  },
  "required": ["findings"],
  "additionalProperties": false
}
```

Research, deliberation:

```json
{
  "type": "object",
  "properties": {
    "verdicts": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "finding_id": { "type": "string" },
          "verdict": { "type": "string", "enum": ["agree", "conditional", "reject"] },
          "rationale": { "type": "string" }
        },
        "required": ["finding_id", "verdict", "rationale"],
        "additionalProperties": false
      }
    }
  },
  "required": ["verdicts"],
  "additionalProperties": false
}
```

## 6. Output template — decision passed

```markdown
## Council result: passed — {{POSITION}} ({{N}} to {{M}})

| Sage | Position | Rationale (gist) | Confidence | After debate |
|---|---|---|---|---|
| MELCHIOR (claude) | {{POSITION}} | {{GIST}} | high | kept |
| BALTHASAR (codex) | {{POSITION}} | {{GIST}} | medium | switched → {{POSITION}} |
| CASPER (grok) | {{POSITION}} | {{GIST}} | high | — |

**Minority opinion**: {{SAGE}} argued for {{POSITION}}. {{RATIONALE}} (Outvoted,
recorded here because the reason it lost may still apply to your situation.)

**Audit log**: {{OUT_DIR}} holds every prompt sent and every raw answer received.
```

- The `After debate` column reads `—` when no debate was held; drop the column
  entirely if the vote passed in round 1.
- A sage that could not answer keeps its row:
  `| CASPER (grok) | no answer (timeout) | — | — | — |`. The reason in the
  parentheses is one of `timeout`, `error`, `invalid answer`.
- Write the minority opinion even when it is a single sentence. Omitting it turns
  a council into a single model with extra steps.

## 7. Output template — decision, no consensus

```markdown
## Council result: no consensus — returned to you

Two debate rounds did not produce a position with two supporters. The decision
is yours; below is what the council established.

| Sage | Final position | Rationale (gist) | Confidence | Movement |
|---|---|---|---|---|
| MELCHIOR (claude) | {{POSITION}} | {{GIST}} | high | kept through both rounds |
| BALTHASAR (codex) | {{POSITION}} | {{GIST}} | medium | compromise in debate2 |
| CASPER (grok) | {{POSITION}} | {{GIST}} | low | switched in debate1, then back |

### What they actually disagree about

**{{POINT_OF_CONTENTION}}**
- MELCHIOR: {{CLAIM}}
- BALTHASAR: {{CLAIM}}
- CASPER: {{CLAIM}}

{{repeat one block per contested point}}

### What would settle it

{{The facts or measurements that would resolve each contested point — drawn from
what the sages themselves said they were unsure of, not from your own opinion.}}

**Audit log**: {{OUT_DIR}} holds every prompt sent and every raw answer received.
```

The disagreement breakdown is the deliverable here. A no-consensus result that
only lists three positions has told the user nothing they did not already fear.

## 8. Output template — research report

```markdown
## Council research: {{TOPIC}}

{{One paragraph: what the council established, and where it split.}}

### Corroborated ({{N}} findings)

| Finding | Support | Evidence |
|---|---|---|
| {{CLAIM}} | 3 of 3 | {{EVIDENCE, with the strongest source}} |
| {{CLAIM}} | 2 of 3 | {{EVIDENCE}} — MELCHIOR did not report this |

### Conditionally adopted ({{N}} findings)

| Finding | Reported by | Deliberation | Condition |
|---|---|---|---|
| {{CLAIM}} | CASPER | BALTHASAR: conditional, MELCHIOR: agree | {{CONDITION}} |
| {{CLAIM}} | MELCHIOR | BALTHASAR: agree, CASPER: reject | Council split: {{BOTH SIDES}} |

### Rejected ({{N}} findings)

| Claim | Reported by | Why rejected |
|---|---|---|
| {{CLAIM}} | BALTHASAR | Both reviewers rejected: {{REASON}} |

### Per-sage summary

| Sage | Findings | Focus | Notes |
|---|---|---|---|
| MELCHIOR (claude) | 5 | {{WHAT IT EMPHASISED}} | — |
| BALTHASAR (codex) | 4 | {{WHAT IT EMPHASISED}} | 1 finding rejected |
| CASPER (grok) | 0 | — | no answer (timeout) |

**Audit log**: {{OUT_DIR}} holds every prompt sent and every raw answer received.
```

- Keep rejected findings visible. One sage believing something the others reject
  is exactly the signal a single-model answer would have hidden.
- When a claim is corroborated but the sages disagree on a detail — a date, a
  version, a number — adopt the claim and note the conflicting detail in the
  evidence column rather than silently picking one.
- A sage with zero findings still gets a row, with the reason in Notes.
