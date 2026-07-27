# Completion and Sprint Transition

Run these steps after a sprint reaches a terminal checkpoint.

## Step 8: Pull Request Creation

Read `pr-creation-guide.md` completely. When `contract.status == "done"`:

1. Confirm commits are on `harness/<epic>/sprint-<n>-<feature>`.
2. Run `git push -u origin <branch>` unless `tracker == none`.
3. Create one PR per sprint for `bundling: split`, or one PR listing all bundled features for `bundled`.
4. Build the body from the guide, quote `shared_state.md/Evaluation`, and link `_state.json.sprint_issues[<n>]`.
5. Store the PR URL in `_state.json.sprint_prs[<n>]` and append progress.md.

When aborted, skip PR creation, record the decision in shared_state.md and progress.md, and keep the branch for inspection.

## Step 9: Sprint Transition

If `aborted_reason` is non-null, stop, show the reason, and do not advance `current_sprint`.

When another roadmap sprint remains:

1. Increment `current_sprint`; set `iteration = 0` and `phase = "negotiation"`.
2. Reset `start_time` to now, `rubric_stagnation_count` to zero, and `features_pass_fail` to an empty list.
3. Reset `sprint_branch`, `effective_generator_backend`, and `last_agent` to null, and `negotiation_round` to zero.
4. Re-run Step 1's four-layer backend resolution and log any backend change to progress.md.
5. Set `pending_worker_exit = true` as the final durable write of the turn.
6. In interactive mode, use AskUserQuestion to ask `Proceed to sprint <n+1>?`; then return to Step 3.

When no sprint remains, assert that every completed sprint has a non-null PR, set `completed = true`, `phase = "done"`, and `pending_worker_exit = true`, then continue to Step 10.

`cumulative_cost_usd` persists across the epic. Never write `phase = "ready-for-loop"` during transition; the supervisor must observe `phase = "negotiation"` and start the next worker from that cursor.

## Step 10: Final Summary

When completed, report the epic name, sprints, PR URLs, total cost, wall time, iteration count, and aborted sprints with reasons. Append `decision: epic=<name> completed sprints=<N> cost=<$> iters=<total>` to progress.md.

Suggest `/harness-rules-update` after an abort or `rubric_stagnation` trigger.

## Error Handling

| Situation | Response |
|---|---|
| `.harness/_config.yml` missing | Tell the user to run `/harness-init` first |
| roadmap.md missing | Tell the user to run `/harness-plan` first |
| `jq` or `git` missing | Stop and request installation |
| `gh` missing with `tracker=github` | Abort; never change tracker silently |
| Generator dispatch fails | Log to the phase-specific feedback file, retry once, then set `pending_human=true` |
| Evaluator tool unavailable | Record `verdict: fail, reason: tool-unavailable`; let rubric stagnation stop the loop |
| `git commit` fails | Log and continue; never bypass hooks |
| Planner ruling absent after round 3 | Set `pending_human=true` and halt |
| `_state.json` cannot be parsed | Halt without overwriting; require restoration from git |
| AskUserQuestion reached in non-interactive mode | Treat as a bug; use the `_config.yml` default and warn in progress.md |
