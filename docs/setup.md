# Setup

What you do, in order, and what exists afterwards. Everything here is Phase 1–2 behaviour; commands marked *(later)* belong to a later phase.

## 1. Install the plugin

Inside Claude Code:

```
/plugin marketplace add minanyang/brain
/plugin install brain@brain
```

Afterwards: the `/brain` skills exist, the hooks are registered, nothing else has changed. No vault yet, no config, so the hooks do nothing.

## 2. Create a vault

From any session:

```
/brain:init ~/vaults/personal
```

It asks one question — *which directories should feed this vault?* — with `~/**` as the default. Then it:

1. Creates the directory, runs `git init`, and lays down the vault skeleton from `templates/vault/`:

   ```
   ~/vaults/personal/
   ├── CLAUDE.md        local overrides and glossary — starts almost empty
   ├── .gitignore       .state/
   ├── sources/sessions/  sources/refs/
   ├── me/  people/  projects/  decisions/  topics/
   ├── index.md         empty catalog
   ├── log.md           one entry: ## [date] init | vault created
   └── brief.md         empty
   ```

2. Registers the vault in `~/.brain/config.json`, creating the file if needed:

   ```json
   {
     "transcripts": ["~/.claude/projects"],
     "distill_model": "haiku",
     "inject_brief": false,
     "vaults": [
       { "name": "personal", "path": "~/vaults/personal", "include": ["~/**"] }
     ]
   }
   ```

3. Makes the first commit and prints the next step.

Whether the vault gets a remote is up to you (`git remote add origin <private repo>`); nothing in Brain needs one.

### A second vault

```
/brain:init ~/vaults/work
```

Answer the directory question with `~/Repos/acme/**`. New vaults are inserted at the **front** of the `vaults` list, so a specific vault added after a catch-all one takes precedence without editing anything. Reorder or add `exclude` globs in `config.json` by hand when the defaults are not right.

## 3. Backfill what already exists

```
/brain:distill --days 7
/brain:distill --all --jobs 4
```

Start with a week, read a few digests, then run the rest. Claude Code keeps transcripts for 30 days by default (`cleanupPeriodDays`), so the backlog is at most a month unless you raised that; a heavy month is on the order of 150 sessions and half a gigabyte of JSONL, which `--jobs 4` distills in about 20 minutes with a small model.

Walks every transcript under `transcripts`, routes each by its `cwd`, skips the ones that match no vault, and writes a digest per session into the right vault's `sources/sessions/`. Prints what it skipped and why (no vault matched, too short, secret gate tripped). Safe to run again; it is a no-op the second time. One small-model call per session, so on a long history start with `--days 30` and look at a few digests before running the rest.

## 4. Use Claude as usual

Nothing to do. When a session ends, its digest appears in the routed vault's `sources/sessions/`. When a session starts, the hook prints one line if there is anything waiting:

```
[brain] 3 digests pending since 2026-08-19, 1 unresolved conflict — run /brain:ingest
```

## 5. Ingest when you want to

```
/brain:ingest
```

Acts on the vault the current directory routes to (or `--vault work`). Collects your hand edits since the last ingest, integrates pending digests and refs into the wiki in batches — each batch regenerates `index.md` and `brief.md`, appends to `log.md`, and commits — and finishes by asking you to decide each conflict it recorded. It uses the session's model, so pick one with `/model` first; a strong model is worth it here.

The first ingest after a backfill is the big one: a month of sessions is ~130 digests, which the skill splits into clusters by working directory and hands to subagents (parallel across clusters, sequential within the largest), committing after every batch. Open a fresh session inside the vault for it; you can stop at any point and resume later with the same command. Day to day it is a few digests and one call.

Open the vault in Obsidian or any editor and read what it wrote. Correct anything wrong directly in the page; the next ingest treats your edit as the highest-priority source.

## 6. Optional switches

- `inject_brief: true` in `config.json` — the session-start hook adds the routed vault's `brief.md` to every session's context, so the agent starts each conversation already knowing your working style and main projects. Off by default; flip it once you trust the wiki. Per machine; nothing in your Claude config changes.
- `distill_model` — the model the distill runner passes to `claude -p`. Small is fine; distill is mechanical.
- `/brain:lint` — health report: unresolved conflicts, stale pages, orphans, names without a page, digests never ingested, claims that contradict Claude's built-in memory, human claims lost by an ingest. Weekly is plenty.
- `/brain:clip <url>` — keep an article or document: it is fetched, you say in one line why it matters, and it lands in `sources/refs/` for the next ingest. Paste text instead of a URL when the page cannot be fetched.

## Where to run what

Every command looks at the current working directory and acts on the vault it routes to; `--vault <name>` overrides that.

| Command | Run it from | Acts on |
| --- | --- | --- |
| `/brain:init <path>` | anywhere | creates and registers `<path>` |
| `/brain:distill` | anywhere | every transcript under the configured roots, each routed to its own vault |
| hooks | automatic, every session | the vault the session's directory routes to |
| `/brain:ingest`, `/brain:query`, `/brain:lint` | anywhere, preferably inside the vault | the vault the directory routes to, or `--vault` |

Two reasons to run ingest and query from inside the vault: the session-start hook injects the schema there, and sessions held inside a vault are never distilled — so the conversation in which you tidy the wiki does not itself become a source.

## Working inside the vault

Opening Claude with the vault as the working directory is how you query it (`/brain:query <question>`, or just ask — the vault's `CLAUDE.md` plus the schema the hook injects tell the agent how the vault is organised). Answers cite pages and digests; a synthesis worth keeping is filed as a page. Sessions held inside a vault are never distilled; they are not sources.

## What the hook does with the schema

The plugin is installed under a version-specific path (`~/.claude/plugins/cache/<marketplace>/brain/<version>/`), which changes on every update. A vault therefore never references the plugin by path. Instead, when a session starts with a vault as its working directory, the `SessionStart` hook injects the installed version's `docs/schema.md` into the session. The vault's own `CLAUDE.md` holds only local overrides, which win.

## Removing

`/plugin uninstall brain` removes the skills and hooks. Vaults and `~/.brain/config.json` are yours and stay where they are.
