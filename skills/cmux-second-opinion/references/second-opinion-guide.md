# cmux-second-opinion Reference Guide

## Overview

cmux-second-opinion requests an independent code or spec review from a different AI agent via cmux. The reviewer runs in a separate workspace, providing a fresh perspective without the biases of the original author or primary reviewer.

## Full Flow

```
1. Environment check (CMUX_SOCKET_PATH)
2. Determine review type (code or spec)
3. Determine criteria mode (default / no criteria / criteria only)
4. Select reviewer agent (default: different from parent)
5. Gather review material (diff or spec files)
6. Create workspace + launch reviewer
7. Detect prompt (polling)
8. Send review prompt
9. Monitor completion (graduated polling)
10. Collect results (read-screen --scrollback)
11. Structure results into report
12. Report to user in parent session
13. Cleanup workspace
```

## Usage Examples

### Code Review (Default)

```
User: "Get a second opinion on this diff"
User: 「このdiffをセカンドオピニオンして」
Agent: Gets diff → launches Codex → sends review prompt → collects → reports
```

### Spec Review

```
User: "Get a second opinion on the auth-feature specs"
User: 「auth-featureの仕様書のセカンドオピニオンをもらって」
Agent: Reads .specs/auth-feature/ → launches Codex → sends spec review prompt → reports
```

### Free Review (No Criteria)

```
User: "Have Codex freely review this code"
User: 「自由にレビューしてもらって」
Agent: Does not pass review_rules.md → reviewer uses own judgment
```

### Strict Criteria Review

```
User: "Review strictly against the rules"
User: 「ルールに従って厳密にレビューして」
Agent: Passes review_rules.md only, no "also share" instruction
```

### Specify Reviewer

```
User: "Have Claude Code review this instead of Codex"
User: 「Claude Codeにレビューさせて」
Agent: Launches Claude Code as reviewer instead of default Codex
```

## Review Criteria Modes Explained

### Default Mode (Recommended)

Passes review_rules.md to the reviewer AND asks for additional insights. This balances consistency (same standards) with the value of a fresh perspective.

### No Criteria Mode

Does not pass review_rules.md. The reviewer uses its own knowledge and judgment. Best when you want a completely independent viewpoint, or when review_rules.md doesn't exist.

### Criteria Only Mode

Passes review_rules.md and asks the reviewer to strictly follow it. Best for compliance checks or when you want to verify that the primary review didn't miss rule violations.

## Why Not Pass inspection-report.md?

For spec reviews, the existing spec-inspect report is deliberately NOT passed to the reviewer. This ensures the second opinion is truly independent — the reviewer may catch issues that spec-inspect missed, or validate concerns that spec-inspect raised.

Comparing the two reports afterward is the user's (or parent agent's) responsibility.

## Prompt Tips

- For large diffs, the prompt may be truncated. Focus on the most critical files if the diff exceeds ~2000 lines.
- For spec reviews, all three files (requirement.md, design.md, tasks.md) are included in the prompt.
- The reviewer sees the content but does NOT have file system access — it reviews based on what's in the prompt.

## Error Cases

### Reviewer agent not installed

If `codex` (or the specified agent) is not found, the skill suggests alternatives:

```
"Codex is not installed. Would you like to use Claude Code or Gemini CLI instead?"
```

### Empty diff

If `git diff HEAD` returns nothing, there's nothing to review. Make changes first, or specify a different diff range.

### review_rules.md not found

This is not an error — the skill falls back to "no criteria" mode automatically. To generate review_rules.md, run `spec-rules-init --with-review-rules`.

## Related Skills

- **cmux-delegate**: General task delegation (not review-specific). Use when you want an agent to do work, not just review.
- **cmux-fork**: Fork the current conversation. Use when you want to continue the same conversation in a new pane.
- **spec-inspect**: Automated spec quality checks (different from second opinion — spec-inspect uses predefined checks, second opinion uses AI judgment).
