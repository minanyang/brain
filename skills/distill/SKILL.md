---
name: distill
description: Distill Claude Code transcripts into session digests in the routed vault. Use for backfilling existing sessions (--all) or distilling one transcript by hand; hooks do this automatically for normal use.
argument-hint: [--all] [--days N] [--jobs J] [<transcript.jsonl>]
allowed-tools: Bash
---

Run the distill runner with the user's arguments:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/distill.sh" $ARGUMENTS
```

- `--all` walks every transcript under the configured roots; add `--days N` to limit to recently modified ones. Each transcript is routed by its `cwd`; those matching no vault are skipped and listed.
- With no arguments, ask whether the user wants `--all` (full backfill, one small-model call per session) or `--all --days 30`. For a large history add `--jobs 4`: writes are serialized by the vault lock, so parallel runners are safe and cut a month of sessions from about an hour to twenty minutes.
- The runner is idempotent; re-running it is a no-op for transcripts that have not grown.

Afterwards report the `done:` line — one per runner with `--jobs` — plus any line that names a session: `secret gate blocked` (nothing was written, and it will be blocked again on every run until the transcript changes or the pattern is fixed), `model call failed` and `malformed digest` (state is untouched, so simply re-running retries them). If it prints `no config`, run `/brain:init` first.

Do not open, summarize, or quote the transcripts yourself. Raw transcripts skip the credential redaction and the secret gate the runner applies, and anything you write by hand is invisible to `.state/distilled.json`, so the next run would duplicate it.
