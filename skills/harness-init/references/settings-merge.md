# settings.json Non-Clobbering Merge

Algorithm for injecting harness hooks into `.claude/settings.json` without
destroying user-authored or other-skill-authored entries.

## Input

- `existing`: current `.claude/settings.json` (may be absent or empty `{}`)
- `patch`: hook block for the chosen level, from
  [hooks-templates.md](hooks-templates.md)

## Output

One of:

- `applied`: new `.claude/settings.json` written after user approval
- `proposed`: `.claude/settings.harness.json.proposed` written instead
  (user rejected the diff)
- `unchanged`: patch is a subset of existing — nothing to do

## Algorithm

```
1. If existing missing or empty:
     merged := patch
     goto (6)

2. Parse existing as JSON. If malformed:
     ERROR with line number; do NOT clobber; exit.

3. merged := deep-copy(existing)
   ensure merged.hooks is an object (create if absent).

4. For each event in patch.hooks (PreToolUse / PostToolUse / Stop / SessionStart):
     if merged.hooks[event] is absent:
         merged.hooks[event] := patch.hooks[event]
         continue

     # event already exists — merge at matcher granularity
     For each matcher_entry in patch.hooks[event]:
         # matcher_entry = { "matcher": "...", "hooks": [ {command: ...} ] }
         find existing entry in merged.hooks[event] with same matcher

         if none found:
             append matcher_entry to merged.hooks[event]
         else:
             # same matcher — merge hook commands, de-duplicate by command string
             for cmd in matcher_entry.hooks:
                 if cmd.command already present in existing entry.hooks:
                     skip
                 else:
                     append cmd to existing entry.hooks

5. If deep-equal(merged, existing):
     return "unchanged"

6. Compute diff := unified-diff(existing, merged)  # for display only

7. AskUserQuestion (bilingual):
     "Apply this hooks patch to .claude/settings.json? / この hooks パッチを適用しますか？"
     options:
       - "Apply" / "適用"
       - "Save as .proposed and stop" / ".proposed として保存して中断"
       - "Cancel harness-init" / "harness-init を中止"

8. On "Apply":
     atomic-write .claude/settings.json (write-temp + rename)
     return "applied"
   On "Save as .proposed":
     write .claude/settings.harness.json.proposed
     return "proposed"
   On "Cancel":
     exit harness-init with partial-state notice.
```

## Matching rules

- **Event keys** (`PreToolUse`, `PostToolUse`, etc.) are compared case-sensitively.
- **Matcher strings** (`"Edit|Write"`, `"Bash"`, `"mcp__.*"`, `"compact"`) are
  compared as opaque strings — no regex normalisation. If the user's matcher
  is `"Write|Edit"` and the patch is `"Edit|Write"`, they are treated as
  different matchers (both kept).
- **Command de-duplication** compares the full `command` field literally.

## Example: before / after

**existing**:
```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit", "hooks": [ { "type": "command", "command": "my-linter.sh" } ] }
    ]
  }
}
```

**patch** (minimal level):
```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": ".harness/scripts/progress-append.sh" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": ".harness/scripts/stop-guard.sh" } ] }
    ]
  }
}
```

**merged** (both PostToolUse matchers preserved, new Stop added):
```json
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Edit", "hooks": [ { "type": "command", "command": "my-linter.sh" } ] },
      { "matcher": "Edit|Write", "hooks": [ { "type": "command", "command": ".harness/scripts/progress-append.sh" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": ".harness/scripts/stop-guard.sh" } ] }
    ]
  }
}
```

## Why non-clobbering matters

`.claude/settings.json` is shared territory — multiple skills and the user
may have configured hooks, permissions, env vars, and model overrides.
Overwriting would silently break those. Merging at matcher granularity
preserves everything while still letting harness enforce its policy.

If the user later wants to remove harness hooks, they delete the
`.harness/scripts/*` command entries; the merge algorithm leaves their
other hooks untouched.

## Preserving non-hooks keys

Top-level keys other than `hooks` (`permissions`, `env`, `model`, `theme`,
custom skill keys) are copied forward untouched. Only `hooks` is touched.

## Atomic write

```bash
tmp=$(mktemp "$(dirname .claude/settings.json)/.settings.XXXXXX")
printf '%s\n' "$merged_json" > "$tmp"
mv "$tmp" .claude/settings.json
```

Never truncate-then-write — a crash mid-write would leave a half-written
JSON and break every subsequent Claude Code session.
