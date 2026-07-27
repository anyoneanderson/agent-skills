# Requirement Boundary Check

Validate that `requirement.md` closes its scope and gives every requirement an observable completion condition.

## Required Sections

Require headings for Overview, Functional Requirements, Non-Functional Requirements, Constraints, Assumptions, and Out of Scope. Accept `Non-Goals` as an English alias for Out of Scope. Ignore an optional numeric prefix such as `## 6.`, and apply case-insensitive matching to English headings.

## Out-of-Scope Validation

1. Locate the Out of Scope or Non-Goals level-two section.
2. Read from that heading until the next level-two heading or end of file.
3. Require at least one non-empty list item that names a concrete excluded capability, scenario, or responsibility.
4. Treat a section containing only comments, headings, or placeholders such as `None`, `TBD`, or `N/A` as empty.

Emit a WARNING for a missing section or an empty section. Include the file, heading line when present, and a suggestion to add a concrete excluded item.

## Acceptance-Criteria Validation

1. Within the Functional Requirements and Non-Functional Requirements level-two sections only, find every definition whose ID matches `REQ-\d+` or `NFR-\d+`. Accept both `### [REQ-001] Name` and the legacy line-leading `[REQ-001] Name` form; ignore ID mentions outside those sections.
2. Treat the content from that definition through the next requirement definition or level-two heading as the requirement block.
3. Require an `Acceptance Criteria:` label, optionally wrapped in Markdown emphasis. Accept either one non-empty inline criterion after the colon or at least one non-empty list item beneath the label before the block ends.
4. Treat unchecked or checked task markers as list items, but reject placeholders such as `TBD`, `N/A`, or an ellipsis as empty criteria.
5. The criterion must state an observable result or threshold. A restatement of the requirement title alone does not satisfy the check.

Emit one WARNING per requirement block that lacks a valid acceptance-criteria list. Include the requirement ID, its definition line, and a suggestion to add an observable pass/fail condition.

## Finding Titles

- Missing section: `Required section 'Out of Scope' is missing`
- Empty section: `Out of Scope section has no concrete item`
- Missing criteria: `Requirement {requirement_id} has no acceptance criteria`
