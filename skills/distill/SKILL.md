---
name: distill
description: Distill Claude Code transcripts into session digests in the routed vault. Use for backfilling existing sessions (--all) or distilling one transcript by hand; hooks do this automatically for normal use.
argument-hint: [--all] [--days N] [<transcript.jsonl>]
allowed-tools: Bash
---

Run the distill runner with the user's arguments:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/distill.sh" $ARGUMENTS
```

- `--all` walks every transcript under the configured roots; add `--days N` to limit to recently modified ones. Each transcript is routed by its `cwd`; those matching no vault are skipped and listed.
- With no arguments, ask whether the user wants `--all` (full backfill, one small-model call per session — on a large history this takes a while) or `--all --days 30`.
- The runner is idempotent; re-running it is a no-op for transcripts that have not grown.

Afterwards, report the last line (`done: N written, N skipped, N blocked`) and any `secret gate blocked` lines — those sessions were not written and the user decides what to do with them. Do not open, summarize, or quote the transcripts yourself; the runner does the distilling.
