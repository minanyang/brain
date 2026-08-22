---
name: distill
description: Use when the user asks to backfill past sessions into the vault, or to distill one transcript by hand. Hooks distill each session automatically, so this is for backfills and one-offs.
argument-hint: "[--all] [--days N] [--jobs J] [<transcript.jsonl>]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/distill.sh *)
disable-model-invocation: true
---

Run the distill runner with the user's arguments:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/distill.sh" $ARGUMENTS
```

- `--all` walks every transcript under the configured roots; add `--days N` to limit to recently modified ones. Each transcript is routed by its `cwd`; those matching no vault are skipped and listed. A session held **inside** a vault also prints `no vault for <vault path>` — that is deliberate, not a misconfiguration: the conversation in which the wiki is tidied must not become a source.
- A first backfill can never reach further back than about 30 days, because Claude Code deletes transcripts on that schedule. On a fresh install `--all` and `--all --days 30` return nearly the same set.
- With no arguments, ask whether the user wants `--all` (full backfill, one small-model call per session) or `--all --days 30`. For a large history add `--jobs 4`: writes are serialized by the vault lock, so parallel runners are safe and cut a month of sessions from about an hour to twenty minutes.
- The runner is idempotent; re-running it is a no-op for transcripts that have not grown. A resumed session is the exception: it appends `## Continued` to its digest and resets `ingested: false`, so a digest the user already ingested legitimately reappears in the pending count — do not report that as a regression.

Never open, summarize, or quote the transcripts yourself: raw transcripts skip the credential redaction and the secret gate the runner applies, and anything you write by hand is invisible to `.state/distilled.json`, so the next run duplicates it.

Never hand-edit a digest to repair a malformed one — the runner sees the transcript has grown since its recorded offset and appends a second copy. Delete the digest and its state entry, then re-run.

Never raise `--jobs` far past 4: writes serialize on the vault lock, so extra runners queue instead of parallelizing while each still holds a model call open.


Afterwards report the `done:` line — one per runner with `--jobs` — and triage the lines that name a session:

- **Retries on its own**: `model call failed`, `malformed digest`. State was left untouched, so say so and offer to re-run.
- **Will never clear itself**: `secret gate blocked`. Nothing was written and it is blocked again on every run until the transcript changes or the gate's patterns do; name the session id and stop — only the human can decide.
- **Normal, not a problem**: `long session, N parts` (a transcript too long for one model call, split at turn boundaries into `## Part k of n`) and `too short, skipped` on a backfill.

If it prints `no config`, run `/brain:init` first.