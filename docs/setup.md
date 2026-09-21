# Setup

What you do, in order, and what exists afterwards.

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
   ├── CLAUDE.md        shared local overrides and glossary — starts almost empty
   ├── AGENTS.md        Codex bridge to the shared rules
   ├── .gitignore       .state/
   ├── sources/sessions/claude/  sources/sessions/codex/
   ├── sources/refs/  sources/memory/
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
/brain:distill --all --days 7
/brain:distill --all --jobs 4
```

Start with a week, read a few digests, then run the rest. Claude Code keeps transcripts for 30 days by default (`cleanupPeriodDays`), so the backlog is at most a month unless you raised that; a heavy month is on the order of 150 sessions and half a gigabyte of JSONL, which `--jobs 4` distills in about 20 minutes with a small model.

Walks every Claude transcript under `transcripts`, routes each by its `cwd`, skips the ones that match no vault, and writes a digest per session into the right vault's `sources/sessions/claude/`. Prints what it skipped and why (no vault matched, too short, secret gate tripped). Safe to run again; it is a no-op the second time. One small-model call per session, so on a long history start with `--days 30` and look at a few digests before running the rest.

## 4. Use Claude as usual

Nothing to do. When a session ends, its digest appears in the routed vault's `sources/sessions/claude/`. When a session starts, the hook prints one line if there is anything waiting:

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

- `inject_brief: true` in `config.json` — the session-start hook adds the routed vault's `brief.md` to every session's context, so the agent starts each conversation already knowing your working style and main projects, plus a short list of the wiki pages that recent sessions in the current directory fed, so it knows which pages to read before answering. Off by default; flip it once you trust the wiki. Per machine; nothing in your Claude config changes.
- `distill_model` — the model the distill runner passes to `claude -p`. Small is fine; distill is mechanical.
- `auto_ingest` — run one ingest in the background at session start when the backlog has grown. Distilling is already automatic, so without this the digests sit in `sources/` until you notice the reminder and run `/brain:ingest`; the first vault's own figures were a median under a day but a p90 of 102 h, with the oldest digest waiting 11 days. Off by default, because it spends model budget without asking and rewrites the `brief.md` every later session reads. Turn it on with:

  ```json
  "auto_ingest": {
    "enabled": true,
    "min_pending": 20,
    "max_age_hours": 24,
    "min_interval_hours": 6,
    "model": "sonnet"
  }
  ```

  It fires when either `min_pending` digests are waiting or any one of them is older than `max_age_hours`, and never more often than `min_interval_hours`. Pick a model that can split an overgrown page and notice a file missing from its own batch; `haiku` is enough for distill and is not enough for this. An unattended run leaves every conflict `[open]` for you: it has no access to `git` or the cloud to verify against, and a guess recorded as a decision cannot be found later. Watch it in `~/.brain/logs/ingest.log`, and run `scripts/auto-ingest.sh --force --dry-run` to see what it would do right now.
- Memory sync needs no switch: after every distill, any memory file Claude wrote under `~/.claude/projects/*/memory/` that changed since the last sync is copied into the routed vault's `sources/memory/` and waits for the next ingest like a digest. Nothing is written back to the memory directory.
- `/brain:lint` — health report: unresolved conflicts, stale pages, orphans, names without a page, digests never ingested, claims that contradict Claude's built-in memory, human claims lost by an ingest. Weekly is plenty.
- `/brain:clip <url>` — keep an article or document: it is fetched, you say in one line why it matters, and it lands in `sources/refs/` for the next ingest. Paste text instead of a URL when the page cannot be fetched.

## Codex

Codex shares the vault already registered in `~/.brain/config.json`. From the Brain checkout:

```sh
./scripts/install-codex.sh
```

The installer adds six `$brain-*` skills, Brain `SessionStart` and `SessionEnd` hooks, Codex transcript roots in the existing Brain config, and an `AGENTS.md` bridge in each registered vault. It preserves unrelated hooks and saves the previous hook file as `hooks.json.brain-backup`. `CLAUDE.md` remains the one shared glossary and override file.

Restart Codex and use `/hooks` to review and trust the two commands. Codex requires explicit trust whenever a hook definition is new or changes. New Codex sessions are then distilled into `sources/sessions/codex/`. Installation records its time and only catches up sessions active afterwards, so it does not silently backfill existing history.

To include older Codex sessions deliberately:

```text
$brain-distill --all --days 30
```

Codex uses its configured model for distillation unless `codex_distill_model` is set in `~/.brain/config.json`. `distill_model` continues to control Claude distillation. Both source trees enter the same ingest queue and produce the same wiki pages, index, and brief.

When `CODEX_HOME` is not exported by the environment that launches Codex, pass it explicitly:

```sh
./scripts/install-codex.sh --codex-home /absolute/path/to/codex-home
```

Re-run the installer after updating Brain. It refreshes only Brain-managed files and starts no backfill.

## Where to run what

Every command looks at the current working directory and acts on the vault it routes to; `--vault <name>` overrides that.

| Command | Run it from | Acts on |
| --- | --- | --- |
| `/brain:init <path>` | anywhere | creates and registers `<path>` |
| `/brain:distill`, `$brain-distill` | anywhere | the invoking host's transcripts under its configured roots, each routed to its own vault |
| hooks | automatic, every session | the vault the session's directory routes to |
| `/brain:ingest`, `/brain:query`, `/brain:lint` | anywhere, preferably inside the vault | the vault the directory routes to, or `--vault` |

Two reasons to run ingest and query from inside the vault: the session-start hook injects the schema there, and sessions held inside a vault are never distilled — so the conversation in which you tidy the wiki does not itself become a source.

## Working inside the vault

Opening Claude or Codex with the vault as the working directory is how you query it (`/brain:query <question>` or `$brain-query <question>`). Answers cite pages and digests; a synthesis worth keeping is filed as a page. Sessions held inside a vault are never distilled; they are not sources.

## What the hook does with the schema

The plugin is installed under a version-specific path (`~/.claude/plugins/cache/<marketplace>/brain/<version>/`), which changes on every update. A vault therefore never references the plugin by path. Instead, when a session starts with a vault as its working directory, the `SessionStart` hook injects the installed version's `docs/schema.md` into the session. The vault's own `CLAUDE.md` holds only local overrides, which win.

## Removing

`/plugin uninstall brain` removes the Claude skills and hooks. For Codex, remove the six Brain-managed `brain-*` skill directories, the two Brain entries in `<CODEX_HOME>/hooks.json`, and `<CODEX_HOME>/brain-hook.sh`; restore `hooks.json.brain-backup` only if no other hook changes followed installation. Vaults and `~/.brain/config.json` are yours and stay where they are.
