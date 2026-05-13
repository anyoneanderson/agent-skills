<!-- handover:start -->
## Session Handover

At session start, if local handover files exist (`handover.md` or `.handover/current.md`), read them before making changes.

Verify the handover against the current repository state before trusting it:

- current branch
- current HEAD
- working tree status
- referenced important files

Summarize inherited context, note stale or conflicting information, and continue from `Next Action` only when it is safe and obvious. Ask before destructive, external-facing, or ambiguous actions.
<!-- handover:end -->
