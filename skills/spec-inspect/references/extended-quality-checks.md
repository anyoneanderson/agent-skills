# Extended Quality Checks

Run Checks 14 through 19 in order after the project-rule checks in `SKILL.md`.

## Check 14: API and UI Naming Consistency [WARNING]

For web or API specifications, extract endpoints from design.md and screen names or routes from tasks.md. Determine the majority convention and report minority forms, including singular versus plural resources, verb-based REST paths, path casing, parameter syntax, and `Screen` versus `Page` suffixes.

Output `WARNING-{seq}` with `API naming inconsistency: {details}` and a concrete unification suggestion.

## Check 15: Documentation Update Analysis [INFO]

Inspect README.md, CLAUDE.md, AGENTS.md, the detected coding-rules.md or
`docs/coding-rules.md`, the detected issue-to-pr-workflow.md or
`docs/issue-to-pr-workflow.md`, and documentation directories parsed from
CLAUDE.md. Apply these routings:

- New feature → README feature list
- New endpoint → API documentation
- Technology change → setup guide
- New convention → CLAUDE.md or AGENTS.md
- Shared library or utility change → coding-rules.md
- Workflow change → issue-to-pr-workflow.md
- New quality gate or standard → coding-rules.md

Output `INFO-{seq}` with `Documentation update needed: {filename} — {reason}`.
Suggest this tasks.md shape: `- [ ] DOC-001: Update {section} in {filename}
({reason})` under `### Documentation Update Tasks (auto-detected)`.

## Check 16: Acceptance Test Coverage [WARNING]

test.md uses headings such as `## T-A{nn}: [REQ-XXX] ...` and a `Verify:` or `検証方法:` field whose value is `playwright`, `command`, or `file-check`.

1. If test.md is absent, emit one INFO finding and skip the remaining coverage steps. Legacy three-document specs remain valid.
2. Extract every test ID and the `REQ` or `NFR` IDs referenced by its heading.
3. Report each requirement with no referencing test case.
4. Report each test case with a missing, empty, or unsupported verification method.

Use these outputs:

- Missing test.md: `INFO-{seq}` titled `Acceptance test plan (test.md) not found`, explaining that coverage was not checked and the full workflow can generate it.
- Missing coverage: `WARNING-{seq}` titled `Acceptance coverage: {covered}/{total} requirements have a test case`, listing uncovered IDs and requesting one `T-A` case per ID.
- Missing method: `WARNING-{seq}` titled `Test case {case_id} has no verification method`, requesting one of the three supported values.

## Check 17: Referenced Path Existence and Mode [CRITICAL]

A specification is unimplementable when a path it requires the implementation to read is untracked or is a symlink that git tree access does not follow.

1. Extract repository-relative content-source paths that a step reads, parses, or diffs. Ignore examples and output destinations.
2. Run `git ls-files -s -- <path>` for each path. No output means untracked;
   mode `120000` means a symlink. `git show HEAD:<path>` returns a symlink's
   target string, not the target file content.
3. Flag a symlink only when the read uses git object or tree access, or when the read side is unspecified. Plain working-tree reads may follow symlinks.

Use distinct outputs:

- Untracked: `CRITICAL-{seq}` titled `Referenced path {path} is not tracked by git`; instruct the author to track the file or point at the real tracked path.
- Symlink: `CRITICAL-{seq}` titled `Referenced path {path} is a symlink (mode 120000) used as a content source`; instruct the author to point at the symlink target.

## Check 18: Abstract Process Description [WARNING]

Report only when a primary-vocabulary candidate lacks evidence needed to
determine concrete behavior. Run the selected `abstract-process-check`
reference with the selected `spec-writing` vocabulary. Keep the Pattern list only in `spec-writing`.
Output `WARNING-{seq}` with the file, line, missing
process elements, concrete rewrite, and matching `AV-*` rule.

## Check 19: Projection Consistency [WARNING]

Run the selected `projection-consistency-check` reference and use its finding contract.
