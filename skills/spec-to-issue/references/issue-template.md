# Issue Template and Selection Rules

## Document Role and Reader

The Issue body is an execution contract, not a copy of the specification or a planning diary.
Its reader is an implementer who has not followed the earlier discussion and must decide what problem to solve, what result is required, which boundaries apply, and how completion will be judged.

Link to the specification for supporting detail.
Keep in the Issue only information whose removal would change an implementation decision or completion judgment.

## Project Template Takes Priority

Before composing the body, inspect the repository's Issue forms, Issue templates, contribution rules, and required fields.
When a project template exists, preserve its headings, order, fields, and checkboxes.
Map the selected information into that structure instead of appending the default template below.

Use the default template only when no project template applies.
Omit an optional section when the specifications provide no relevant content; do not invent filler.

## Default Issue Body Template

```markdown
## Problem

{The current behavior or missing capability and the concrete problem it causes.}

## Outcome

{One or two sentences describing the observable state after completion.}

## Current Behavior

{What the system does now. For a new capability, state the missing path or manual workaround.}

## Expected Behavior

{What triggers the behavior, which component acts, what it does, and where the result is stored or returned.}

## Scope

### Included

- {Work required to deliver the expected behavior.}

### Excluded

- {A nearby responsibility that is intentionally not part of this Issue.}

## Acceptance Criteria

- [ ] {An observable result that proves the outcome.}
- [ ] {A failure or boundary behavior that must hold.}

## Binding Decisions

- {A design choice the implementer must preserve and the reason it is constrained.}

## Open Questions

- {An undecided choice, the decision criterion, and who must decide it.}

## Specification

- [Requirements](../blob/{BRANCH}/.specs/{FEATURE_DIR}/requirement.md)
- [Design](../blob/{BRANCH}/.specs/{FEATURE_DIR}/design.md)
- [Tasks](../blob/{BRANCH}/.specs/{FEATURE_DIR}/tasks.md)
```

## Selection Procedure

Read `requirement.md`, `design.md`, and `tasks.md` as candidate sources rather than sections to copy.
Select information in this order:

1. Identify the problem and the observable completed state from the requirements.
2. Describe current and expected behavior with the actor, trigger, processing, and destination when those details affect implementation.
3. Separate included and excluded scope so adjacent work cannot be mistaken for a requirement.
4. Convert requirement-level acceptance criteria into checkboxes that can be verified from observable behavior.
5. Keep a design decision only when changing it would violate a constraint, compatibility requirement, security boundary, or external contract; include the reason.
6. Keep an open question only when implementation cannot safely choose an answer; state the decision criterion and decision owner.
7. Link the specification for architecture detail, task decomposition, estimates, and background evidence.

Do not automatically reproduce key-feature lists, phase-by-phase tasks, task estimates, a technology stack, investigation history, or every note from the specification.
Include one of those details only when it changes how the implementer must build the feature or how the reviewer will decide that it is complete.

## Title

Use `[Feature] {FEATURE_NAME}` unless the project's template or contribution rules define another title format.

Determine `FEATURE_NAME` by:

1. reading the first `# ` heading in `requirement.md`;
2. stripping `Requirements Document`, `Requirements`, `Specification`, `Spec`, `要件定義書`, `要件定義`, or `仕様書`; and
3. trimming surrounding whitespace.

Examples:

- `# Member Management Requirements Document` becomes `[Feature] Member Management`.
- `# メンバー管理機能 要件定義書` becomes `[Feature] メンバー管理機能`.

## Source Mapping

Use the source documents as follows:

- `requirement.md`: problem, outcome, current and expected behavior, scope, and acceptance criteria.
- `design.md`: binding decisions, constraints, compatibility boundaries, and unresolved design choices.
- `tasks.md`: supporting implementation detail and additional completion evidence; do not copy its phase structure or task headings by default.

If the specification lacks a concrete acceptance criterion, report the omission before creating the Issue.
Do not replace it with generic statements such as "tests pass" or "code review is complete," because those do not prove the feature outcome.

## GitHub Issue Creation

Create the Issue with the repository's supported GitHub client using the selected title, body, labels, and assignee.
Avoid shell interpolation of untrusted body content; pass the body through a file or an equivalent literal-input mechanism when available.

## Project Assignment

If `--project` is specified, add the created Issue URL to that project using the repository owner resolved from the current repository.

## Specification Link Branch

Resolve `{BRANCH}` in this order:

1. `--branch` argument
2. `.specs/.config.yml` `default-branch`
3. Repository workflow instructions
4. `main`
