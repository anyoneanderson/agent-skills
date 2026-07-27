---
name: spec-inspect
description: |
  Specification quality checker for spec-generator documents.

  Validates requirement.md, design.md, tasks.md for consistency, completeness, and quality.
  Detects requirement ID mismatches, missing sections, contradictions, and ambiguous expressions.

  English triggers: "inspect specs", "check specification quality", "validate requirements"
  日本語トリガー: 「仕様書を検査」「品質チェック」「仕様を検証」「spec-inspect実行」
license: MIT
---

# spec-inspect — Specification Quality Checker

Automatically validates spec-generator output (requirement.md, design.md, tasks.md) and reports quality issues.

## Language Rules

1. **Auto-detect input language** → output in the same language
2. Japanese input → Japanese report output
3. English input → English report output
4. Explicit override takes priority (e.g., "in English", "日本語で")

## When to Run

- After spec-generator completes (auto-suggested)
- Before registering Issues with spec-to-issue
- After updating specification documents

## Execution Flow

### Step 1: Locate Project Path

Identify the `.specs/{project-name}/` path from user input or current context.

**Validation**:
- `.specs/{project-name}/requirement.md` exists
- `.specs/{project-name}/design.md` exists
- `.specs/{project-name}/tasks.md` exists

If any file is missing, display an error message and exit.

### Step 2: Read Specifications

Read all three specification files:

```
requirement_content = Read(".specs/{project-name}/requirement.md")
design_content = Read(".specs/{project-name}/design.md")
tasks_content = Read(".specs/{project-name}/tasks.md")

# Optional: acceptance test plan (only present for full-workflow / pipeline specs).
# Absence is expected for legacy three-document specs — do NOT treat as an error.
test_content = Read(".specs/{project-name}/test.md") or None

# Optional: load coding rules if available
coding_rules = Read("docs/coding-rules.md") or None
# Also check CLAUDE.md / AGENTS.md for alternative path
```

Detect the specification language, resolve `spec-writing` by name from the currently available skills, and read its complete `SKILL.md` plus the matching `references/abstract-verbs.md` or `references/abstract-verbs.ja.md` once as the primary vocabulary source. Read the matching [abstract-process-check.md](references/abstract-process-check.md) and [projection-consistency-check.md](references/projection-consistency-check.md) references (`*.ja.md` for Japanese), and run both checks in Step 3. If the skill, vocabulary, required columns, or IDs cannot be read, follow the abstract-process reference's vocabulary-error procedure without inferring a pattern list; all other checks must continue.

### Step 3: Run Quality Checks

Execute the following checks sequentially. Add detected issues to an issues list.

#### Check 1: Requirement ID Consistency [CRITICAL]
**Purpose**: Verify that requirement IDs defined in requirement.md are correctly referenced in design.md, tasks.md, and test.md when present.

**Procedure**:
1. Extract requirement IDs from requirement.md (regex: `\[(REQ|NFR|CON|ASM|T)-\d{3,}\]`)
2. Extract referenced requirement IDs from design.md, tasks.md, and test.md when present

**Detection patterns**:

- **[CRITICAL]** ID referenced in design.md, tasks.md, or test.md but not defined in requirement.md
  ```
  ID: CRITICAL-{seq}
  Title: "Requirement ID {req_id} does not exist"
  File: design.md, tasks.md, or test.md
  Line: {line_number}
  Description: "{req_id} is referenced in {file} but not defined in requirement.md"
  Suggestion: "Add {req_id} to requirement.md or fix the reference"
  ```

- **[INFO]** ID defined in requirement.md but never referenced
  ```
  ID: INFO-{seq}
  Title: "Requirement ID {req_id} is unreferenced"
  File: requirement.md
  Line: {line_number}
  Description: "{req_id} is not linked to any design or task"
  Suggestion: "Is this requirement still needed? Consider removing if unnecessary"
  ```

- **[WARNING]** Insufficient requirement coverage (calculate design.md reference rate for all IDs including [NFR-XXX]; warn if below 100%)
  ```
  ID: WARNING-{seq}
  Title: "Requirement coverage: {covered}/{total} ({percentage}%)"
  Description: "The following requirements are not mentioned in design.md: {uncovered_list}"
  Suggestion: "Add coverage for each requirement in design.md"
  ```

#### Check 2: Required Structure and Requirement Boundaries [WARNING]
**Purpose**: Confirm each spec has the expected sections, a non-empty scope boundary, and testable requirements.

**Procedure**:
1. Run the selected `references/requirement-boundary-check.md` / `.ja.md` against requirement.md.
2. For design.md, require Architecture Overview, Technology Stack, Data Model, API Design when applicable, and Security Design. For tasks.md, require Task List and Priority.

**Output**: One `WARNING-{seq}` per missing required section, empty selected out-of-scope section, or `REQ` / `NFR` block without a non-empty acceptance-criteria list.

#### Check 3: Contradiction Detection [WARNING]
**Purpose**: Detect contradictory statements across specification documents.

**Detection examples**:
- Technology stack mismatch (e.g., requirement says PostgreSQL, design says MySQL)
- Numeric mismatch (e.g., requirement says "100 users", design says "1000 users")
- API endpoint mismatch
- Components designed in design.md but missing from tasks.md implementation plan

**Procedure**:
1. Extract technical proper nouns from requirement.md (database names, library names, etc.)
2. Check if the same concept is referred to by a different name in design.md
3. Detect numeric data inconsistencies

**Detection pattern**:
- **[WARNING]** Contradictory statements
  ```
  ID: WARNING-{seq}
  Title: "Contradiction: {concept}"
  File: requirement.md, design.md
  Line: {line_number}
  Description: "requirement.md states {value1}, but design.md states {value2}"
  Suggestion: "Unify to one value"
  ```

#### Check 4: Ambiguous Expression Detection [INFO]
**Purpose**: Detect vague expressions that lack the specificity needed for implementation.

**Detection keywords** (English):
- "appropriately", "as much as possible", "reasonable", "adequate"
- "fast", "large amount", "many" (without numeric criteria)
- "to be determined", "under consideration", "planned" (not finalized)

**Detection keywords** (Japanese):
- 「適切に」「できる限り」「なるべく」「ある程度」
- 「高速に」「大量の」「多くの」（数値基準なし）
- 「検討する」「考慮する」「予定」（確定していない）

**Procedure**:
1. Search all three specs for ambiguous keywords
2. List all occurrences

**Detection pattern**:
- **[INFO]** Ambiguous expression
  ```
  ID: INFO-{seq}
  Title: "Ambiguous expression: '{keyword}'"
  File: {filename}
  Line: {line_number}
  Description: "The expression '{context}' may be interpreted differently by implementors"
  Suggestion: "Specify concrete numbers or criteria"
  ```

#### Check 5: Terminology Consistency [WARNING]
**Purpose**: Ensure consistent terminology usage across all specifications.

**Detection patterns**:
- Same concept expressed with different terms (e.g., "user" vs "member", "delete" vs "remove")
- Inconsistent abbreviations (e.g., "DB" and "database" mixed)
- Terms deviating from glossary definitions (if a glossary section exists)

**Procedure**:
1. Extract key nouns/concepts from all three specs
2. Detect synonym/near-synonym pairs
3. Cross-reference with glossary section if present

**Output**: `WARNING-{seq}` "Terminology inconsistency: '{term1}' vs '{term2}'" + recommendation to unify

#### Check 6: Design-to-Task Coverage [WARNING]
**Purpose**: Verify that design.md components have corresponding implementation tasks in tasks.md.

**Detection patterns**:
- Designed component/module with no corresponding task
- DB schema design with no migration task
- API design with no implementation task

**Procedure**:
1. Extract major component/module names from design.md
2. Check if each component has a corresponding task in tasks.md
3. List uncovered design elements

**Output**: `WARNING-{seq}` "Design element '{component}' has no corresponding task"

#### Check 7: Dependency Validation [WARNING]
**Purpose**: Verify that task dependencies are logically correct.

**Detection patterns**:
- Circular dependencies (Task A depends on B, B depends on A)
- Undefined prerequisite tasks (dependency on non-existent task)
- Obviously reversed dependency order (e.g., test task before implementation task)

**Procedure**:
1. Extract inter-task dependencies from tasks.md
2. Build dependency graph and detect cycles
3. Flag logically inconsistent ordering

**Output**: `WARNING-{seq}` "Circular dependency: {taskA} ⇄ {taskB}" or "Illogical dependency order"

#### Check 8: Infeasible Requirement Warning [WARNING]
**Purpose**: Detect technically difficult or contradictory requirements.

**Detection patterns**:
- Conflicting non-functional requirements (e.g., "response under 1ms" + "encrypt all data")
- Features difficult to achieve with the chosen technology stack
- Unrealistic resource requirements (e.g., unlimited storage, zero downtime)

**Output**: `WARNING-{seq}` "Potentially infeasible: {requirement}" + alternative suggestion

#### Check 9: Missing Requirement Detection [WARNING]
**Purpose**: Detect clearly necessary but undocumented requirements.

**Detection patterns**:
- Authentication present → no security requirements
- Database used → no backup/recovery requirements
- External API integration → no error handling/retry requirements
- File upload → no size/format restrictions
- User data storage → no privacy/data protection requirements

**Procedure**:
1. Extract feature characteristics from requirement.md / design.md
2. Match against detection patterns and check for corresponding requirements

**Output**: `WARNING-{seq}` "Possible missing requirement: {requirement_type} for {feature} is undefined"

#### Check 10: Naming Convention Consistency [INFO]
**Purpose**: Verify consistent naming conventions across specifications.

**Detection patterns**:
- Mixed kebab-case / camelCase / snake_case
- Naming variations in the same context (e.g., `user_id` vs `userId` vs `userID`)
- Convention violations in constants, table names, component names

**Procedure**:
1. Extract code-related names (variable names, table names, API names, etc.) from design.md / tasks.md
2. Gather naming pattern statistics and flag minority patterns

**Output**: `INFO-{seq}` "Naming convention inconsistency: {pattern1} ({count1} occurrences) vs {pattern2} ({count2} occurrences)"

#### Check 11: Directory Structure Consistency [INFO]
**Purpose**: Verify consistent directory structure and placement rules.

**Detection patterns**:
- Inconsistent placement of similar components (e.g., `src/features/A/` vs `src/components/B/`)
- Mixed test file placement (`tests/` vs `__tests__/`)
- Scattered configuration files

**Output**: `INFO-{seq}` "Directory structure inconsistency: {pattern description}"

#### Check 12: Reinvention Detection [INFO]
**Purpose**: Detect custom implementations of functionality already available in declared libraries.

**Detection patterns**:
- Reimplementation of features provided by libraries in the technology stack
  - e.g., Custom date handling when date-fns is included
  - e.g., Custom validation when Zod is included
- Reimplementation of standard library features

**Procedure**:
1. Extract library list from the "Technology Stack" section of design.md
2. Compare against implementation tasks in tasks.md to detect overlapping functionality

**Output**: `INFO-{seq}` "Possible reinvention: {task} could be handled by {library_name}"

#### Check 13: Project Rule Compliance [WARNING]
**Purpose**: Check that specifications comply with project-specific rules defined in CLAUDE.md / AGENTS.md and coding-rules.md.

**Procedure**:
1. Read `CLAUDE.md`, `AGENTS.md`, and `.claude/` from the project root
2. Read `docs/coding-rules.md` if it exists (or path from CLAUDE.md/AGENTS.md)
3. Extract `[MUST]` rules from coding-rules.md
4. Extract coding conventions, prohibited patterns, and required patterns
5. Cross-reference with design.md / tasks.md

**Detection examples**:
- "TypeScript strict mode required" → not mentioned in design.md
- "JWT authentication required" → design.md uses a different approach
- "console.log prohibited" → tasks.md describes console.log usage

**coding-rules.md specific checks**:
- Naming rules vs design.md file/class naming (e.g., coding-rules: `[MUST] kebab-case` vs design: `UserProfile.service.ts`)
- Test coverage requirements vs tasks.md test planning (e.g., coding-rules: `[MUST] 80%+ coverage` vs tasks.md has no test tasks)
- Required libraries vs design.md technology choices (e.g., coding-rules: `[MUST] Use Prisma` vs design: direct SQL)
- Prohibited patterns vs design.md/tasks.md descriptions

**Output**: `WARNING-{seq}` "Project rule violation: {rule} conflicts with {violation_location}"

#### Check 14: API / UI Naming Convention Consistency [WARNING]

Before starting Check 14, read
[references/extended-quality-checks.md](references/extended-quality-checks.md)
completely (`.ja.md` for Japanese). Execute its Checks 14 through 19 in order
and use each check's severity and output contract without modification.

### Step 4: Generate Summary

Aggregate detected issues by severity:
- Critical: {count}
- Warning: {count}
- Info: {count}

### Step 5: Generate Report

Write a Markdown report to `.specs/{project-name}/inspection-report.md`.

**Template**: `# spec-inspect Report — {project_name}` → Inspection summary (date, targets, counts) → Severity sections (CRITICAL / WARNING / INFO). Each issue: `### [{issue.id}] {issue.title}` + file:line, details, suggestion. Display "None" for sections with 0 issues.

Save with Write tool to `.specs/{project-name}/inspection-report.md`.

### Step 6: Console Output

Display a user-friendly summary:

```
spec-inspect complete

Results:
  CRITICAL: {count}
  WARNING:  {count}
  INFO:     {count}

{if critical_count > 0}
Critical issues found. Fix before implementation.

{if critical_count == 0}
No critical issues found.

Report: .specs/{project-name}/inspection-report.md
```

### Step 7: Next Action Suggestion (Workflow Integration)

Use AskUserQuestion to suggest the next action based on results (header: "Next action" / "次のアクション", multiSelect: false):

| Result | Question | Options |
|--------|----------|---------|
| Critical issues | "{count} critical issue(s) found. Action needed." / "Critical問題が{count}件。修正が必要です" | "Fix and re-run" / "修正して再実行", "Skip to Issue registration" / "スキップしてIssue登録", "Cancel" / "キャンセル" |
| Warning/Info only | "{count} warning(s) found. Proceed to Issue registration?" / "Warningが{count}件。Issue登録しますか？" | "Register Issue" / "Issue登録する", "Fix and re-run" / "修正して再実行", "Cancel" / "キャンセル" |
| No issues | "Quality check passed. Register Issues?" / "品質チェック完了。Issue登録しますか？" | "Register Issue" / "Issue登録する", "Cancel" / "キャンセル" |

**Handling user selection**:
- "Register Issue" / "Skip to Issue registration" → invoke spec-to-issue skill
- "Fix and re-run" → exit (user fixes and re-runs manually)
- "Cancel" → exit

### Step 8: Save Handoff Data for spec-to-issue

Save inspection results as a temporary file for the next skill:

```json
{
  "project_path": ".specs/{project-name}",
  "project_name": "{project-name}",
  "critical_count": 0,
  "warning_count": 0,
  "info_count": 0,
  "report_path": ".specs/{project-name}/inspection-report.md",
  "timestamp": "{ISO 8601}"
}
```

Save with Write tool:
```
Write(".specs/{project-name}/.inspection_result.json", json_content)
```

## Error Handling

- **File not found / read error**: "Error: Required file not found" or "Error: Failed to read file" + filename and details, with path verification guidance
- **ID extraction error**: Continue processing and display "Warning: Partial error during requirement ID extraction"

## Implementation Notes

- **Efficiency**: Minimize Read operations for large files; use search tools; show progress after each check.
- **Accuracy / UX**: Use partial matching for section names, consider context for contradiction detection, match Japanese and English content flexibly; errors carry concrete fix suggestions with emoji indicators.

## Constraints

- Supports Markdown specifications in Japanese and English only (natural language analysis has inherent accuracy limits); depends on spec-generator output format

## Success Criteria

- Requirement ID reference errors, missing required sections, and uncovered REQ/NFR (when test.md is present) detected at 100%; test.md absence reported as INFO without failing legacy specs
- Contradiction detection accuracy: Best effort (depends on LLM reasoning capability)
- Processing time: Under 30 seconds for combined spec files under 3000 lines
