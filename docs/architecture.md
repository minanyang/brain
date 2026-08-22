# Architecture

## Layers

### 0 — Streams

Raw, append-only, machine-local. Never copied into any repository.

| Stream | Location | Notes |
| --- | --- | --- |
| Claude Code transcripts | `~/.claude/projects/<cwd-slug>/<session-id>.jsonl` | One line per event (`user`, `assistant`, `system`, tool results, `ai-title`, …). Full history survives context compaction — compaction only affects what the model sees, not the file. Sessions grow while open and when resumed. |
| Calendar, Notion, Slack | via MCP or exports | Later phases. Pulled, not pushed. |

Claude Code is the reference stream and the only one implemented. Adding another agent means one adapter that yields `(timestamp, role, text, cwd)` from wherever that agent keeps its history; nothing downstream changes.

### 1 — Sources

Immutable once written. Live under `sources/` in the vault — one directory, so the machine-written material stays out of the way of the pages a human actually browses. Each is small, dated, carries provenance, and records whether ingest has consumed it (`ingested:` in its frontmatter; nothing is moved after processing).

- `sources/sessions/<YYYY-MM-DD>-<slug>.md` — one digest per session. Slug comes from the transcript's `ai-title` when present, else from the first user message.
- `sources/refs/<YYYY-MM-DD>-<slug>.md` — material the human hands over deliberately: an article, a link, a document, meeting notes. Frontmatter records the URL or origin, the date, and one line from the human on why it matters — that line is what tells ingest where the content belongs. The body is the extracted text itself: a ref is an immutable copy, because links rot and pages change. A link merely mentioned in a session does not become a ref; the digest cites it and moves on. Refs arrive either by hand (drop a file in) or, later, through `/brain:clip <url>`.

#### Why digests are their own layer

The obvious design is three layers — transcripts straight into the wiki. Digests earn a layer of their own for three reasons:

- **Transcripts are read once.** Everything downstream — re-integrating after a schema change, lint, rebuilding the wiki from scratch — re-reads the digests, never the JSONL. Distill is the only step that touches the expensive, noisy stream, and it runs with a small model.
- **Provenance is a chain.** A wiki claim cites a digest; a digest cites a session id and timestamp; the session id locates the exact transcript on the machine that produced it. Each hop is checkable, and the wiki never has to embed raw transcript text to be auditable.
- **Two perspectives, one layer.** Session digests are the collaboration's view of the work: what was built, decided, learned with the agent. Refs are the human's deliberate additions: the article that shaped a decision, the meeting notes, the document a project is built on. Neither alone describes the job; stacked, they do — which is what lets the wiki come to understand the work and the people around it rather than only the codebase. There is deliberately no daily journal in the defaults: a source that only has value if the human writes in it every day is a source that goes empty in two weeks. What happened outside a session gets in by being mentioned in the next one. A vault whose owner does keep a journal declares the directory in its `CLAUDE.md`, like any extra page type.

### 2 — Wiki

Owned entirely by the agent. Humans read and correct; they do not author.

| Directory | Page = | Typical contents |
| --- | --- | --- |
| `me/` | a facet of how the user works | preferences, recurring frictions, tooling, stated goals |
| `people/` | a person or a team | who they are to you, what they own, how to work with them |
| `projects/` | a project or repository | purpose, stack, status, history, open threads |
| `decisions/` | one decision | context, options, choice, why, date, source session |
| `topics/` | a technical or domain concept, or a process or system | what was learned, where it applies, the release process, the fragile service |

These five are the defaults and are deliberately situation-neutral. A vault declares any further page types it needs in its `CLAUDE.md` — `company/` for an employer's org units and processes, `clients/` for a freelancer, `papers/` for a researcher — and ingest files into them like any other. The digest tag vocabulary extends the same way.

Plus three special files:

- `index.md` — catalog of every page with a one-line summary, grouped by directory. Read first on every query.
- `log.md` — append-only timeline. Entries start with `## [YYYY-MM-DD] <op> | <subject>` so `grep '^## \[' log.md | tail` works.
- `brief.md` — compiled, not authored. The ~30 lines most worth loading into every session. Regenerated after each ingest from pages tagged `brief: true`.

### 3 — Schema

The default schema shipped in this repository ([schema.md](schema.md)) plus the vault's `CLAUDE.md`, which holds only local overrides (extra page types, a glossary, emphasis). The plugin injects the schema at session start when the working directory is a vault; it is never referenced by path, because the plugin's install path changes with every version. `templates/vault/CLAUDE.md` is the starter.

## Scope and routing

Which sessions get distilled, and into which vault, is decided by the session's working directory. `~/.brain/config.json` lists vaults in order, each with `include` globs and optional `exclude` globs:

```json
{
  "vaults": [
    { "name": "work",     "path": "~/vaults/work",
      "include": ["~/Repos/acme/**"] },
    { "name": "personal", "path": "~/vaults/personal",
      "include": ["~/**"],
      "exclude": ["~/Repos/acme/**", "~/Repos/client-nda/**", "/tmp/**"] }
  ]
}
```

- A session's `cwd` is matched against the vaults in order; the first match wins. **A session goes to exactly one vault** — no fan-out, so work content cannot land in a personal vault by accident.
- A `cwd` that matches no vault is not distilled. Scope is therefore whatever the `include` lists cover; global exclusions go on the last vault.
- Sessions whose `cwd` is inside a vault are never distilled.
- Every operation follows the same routing. The `SessionStart` hook injects the reminder (and brief, if enabled) of the vault the current `cwd` routes to, so the agent sees the work brief in work repositories and the personal one elsewhere. `/brain:ingest`, `query`, and `lint` act on the current `cwd`'s vault by default and accept `--vault <name>`.
- `.state/`, the `brain/last-ingest` tag, and the one-ingesting-machine rule are all per vault.

Routing controls *where* a session is filed, not *what was said in it*: a work conversation held in a personal directory ends up in the personal vault. That is a habit, not something the tooling can fix; lint can flag claims carrying a vault-defined tag (say `[company]`) appearing in a vault that does not declare that type.

## Where things live

| Component | Lives in | Installed to |
| --- | --- | --- |
| `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | this repo | the repo is its own marketplace: `/plugin marketplace add minanyang/brain`, then `/plugin install brain@brain` |
| `/brain:*` skills (`init`, `distill`, `ingest`, `query`, `lint`, `clip`), one directory each, Agent Skills standard `SKILL.md` | this repo (`skills/`) | `~/.claude/plugins/` via the plugin; or into any other agent with `npx skills add minanyang/brain` |
| Hooks (`SessionEnd` → distill, `SessionStart` → catch-up distill + pending-digest reminder) | this repo (`hooks/hooks.json`) | registered by the plugin |
| Deterministic scripts: transcript extractor, distill runner, secret gate, vault init, status, routing (`resolve-vault.sh`), ingest prep, `finish.sh` (gate → mark sources → regenerate `index.md` and `brief.md` → log → commit → tag, shared by every op), `index.sh`, `lint.sh`, `ref.sh` | this repo (`scripts/`) | called by skills and hooks via `${CLAUDE_PLUGIN_ROOT}` |
| Default schema, page and digest templates | this repo (`docs/schema.md`, `templates/`) | read by the skills from the plugin root; the schema is injected into in-vault sessions by the `SessionStart` hook |
| Per-machine config (vaults and their routing globs, transcript roots, model names, brief switch) | nowhere in git | `~/.brain/config.json` |
| Vault `CLAUDE.md`, sources, wiki, `.state/` | the vault | — |
| `brief.md` injection | the plugin's `SessionStart` hook, switched by a flag in `~/.brain/config.json` | nothing in the user's own config (whether to inject by default is still open) |

Updating Brain is a plugin update. Nothing is copied into the user's own skills, scripts, rules, or global instruction file, so it never gets entangled with whatever else they keep in their agent config. The plugin is one unit; the only per-machine state outside it is `~/.brain/config.json` and the vault.

Each skill is a thin wrapper by design: the deterministic work is a script, the page format is the injected schema, and what stays in the skill is the judgment that belongs to that operation and the prohibitions with the reason attached. Descriptions say when to use a skill, never what it does, because a description that summarizes the workflow gets followed in place of the body.

Why a plugin rather than a standalone CLI: ingest, query, and lint are agentic work — reading the index, judging where facts belong, rewriting pages — and a CLI would only have wrapped agent runs in shell. Skills are their native shape. Distill is the exception: it is mechanical, so it stays a script the skill and the hooks call, and is never itself a skill.

## Operations

### distill

```
for the transcript named by the SessionEnd payload,
or (on SessionStart) for each transcript newer than its recorded state:
    read from the stored byte offset
    drop: tool_result bodies beyond ~300 chars, file-history events, attachments, system noise
    keep: user messages, assistant text, tool_use command summaries, timestamps, cwd, branch
    → clean conversation text
    → cheap model + digest template → sources/sessions/<date>-<slug>.md   (or append a "## Continued" section if the digest already exists)
    record {session_id: {offset, digest_path, last_ts}} in .state/distilled.json
commit sources/sessions/ and log.md
```

Properties that matter:

- **Idempotent.** Re-running with the same state produces no changes.
- **Incremental.** A resumed session is processed from where it was left.
- **Mechanical.** The model is asked to summarize into a fixed template, not to exercise judgment about the wiki. A small model is enough — but a small model on a very long input drifts, so the instruction is repeated after the transcript, the output is checked for the expected headings, and a malformed answer is retried once and otherwise not written.
- **Bounded.** Transcripts longer than the model should see in one call are split at turn boundaries and summarized in parts; the digest carries `## Part k of n` sections. Long sessions are common — a day of work can be tens of megabytes of JSONL.
- **Gated.** Credential patterns are redacted from the transcript text before the model sees it, and the output passes the secret gate before it is written. See [privacy.md](privacy.md).
- **Commits only its own files.** Distill commits `sources/sessions/` and `log.md` and nothing else, so every change under the wiki directories between two ingests is still a human edit (see ingest step 0).

### ingest

**Step 0 — collect human corrections.** The vault is a git repository and ingest is the only non-human process that commits wiki pages. After each ingest it moves the tag `brain/last-ingest`. Before the next ingest it runs `git diff brain/last-ingest -- me/ people/ projects/ decisions/ topics/` (plus any directories the vault declares) (working tree included, so an edit saved in Obsidian counts without a commit). Every hunk in that diff is a human edit. The hunks are handed to ingest as a source that outranks every digest, and the claims they carry are cited as `(→ human, YYYY-MM-DD)` when the page is rewritten.

Then, in batches of pending sources (oldest first, ~15 at a time, so that progress is committed and a long run can stop and resume):

1. Extract facts and classify them by page type: the user, a person or team, a project, a decision, a topic, or any type the vault declares.
2. For each fact, find the page it belongs to (via `index.md` and the vault's glossary); create the page if missing.
3. Rewrite the page. If the fact contradicts an existing claim, do **not** overwrite and do **not** pick a winner — record both under `## Conflicts` as an `[open]` entry.
4. Finish the batch deterministically (`scripts/finish.sh --op ingest`): secret gate on every changed page, mark the sources `ingested: true`, regenerate `index.md` and `brief.md` from the pages, append to `log.md`, commit, move `brain/last-ingest`.
5. When the run stops, list every `[open]` conflict it created and ask the human to decide each one now or leave it. A decision is written immediately as a `(→ human, date)` claim on the page; the entry becomes `[resolved <date>]`.

Steps 1–3 are the skill's judgment; step 0 and step 4 are scripts (`ingest-prep.sh`, `finish.sh`). The split is the same as distill's: the agent decides what a fact means, and never touches the bookkeeping.

Pages with `locked: true` are never rewritten; ingest may only append under their `## Conflicts`.

A single session digest typically touches 3–10 pages. This step needs a stronger model than distill; it runs in the user's session, so it uses whatever model the session uses — Brain sets no default.

### query

Read `index.md` → pick pages → read them → answer with citations (`[[page]]`, digest path, session id). The vault answers from its pages, falls back to grepping `sources/` only when the pages are silent and says so, and names what it does not know rather than filling gaps from general knowledge. If the answer is a synthesis worth keeping — a comparison, a timeline, a post-mortem — it is filed as a page and committed through `finish.sh --op query`, which also logs it; a plain factual answer leaves no trace.

### clip

`/brain:clip <url or pasted text>` fetches the content, asks the one question that matters — *why should the vault keep this?* — and writes `sources/refs/<date>-<slug>.md` through `scripts/ref.sh` (slug, frontmatter from `templates/ref.md`, secret gate). Nothing is summarized or filed into the wiki at this point; the ref is `ingested: false` and the next ingest integrates it like a digest, citing it as `(→ sources/refs/…)`.

### lint

Weekly or on demand. Produces a report, not edits, unless told otherwise. `scripts/lint.sh` computes the mechanical rules (1, 2, 3, 5, 7 below) in a couple of seconds; the skill adds the two that need judgment (4 and 6) and logs the run:

- contradictions recorded under `## Conflicts` that are still unresolved
- claims older than N days on pages marked `volatile: true`
- orphan pages (no inbound `[[links]]`)
- entities mentioned on ≥3 pages that have no page of their own
- drift between `brief.md` / wiki and the agent's built-in memory (`~/.claude/projects/*/memory/`)
- digests that were never ingested

## Triggers

Distill and ingest are triggered differently because they are different kinds of work.

| Op | Trigger | Why |
| --- | --- | --- |
| distill | `SessionEnd` hook, forks to the background | The payload names the transcript; no scanning. `SessionEnd` hooks get about 1.5 s, so the hook only spawns the runner and returns; output goes to `~/.brain/logs/distill.log`. |
| distill (catch-up) | `SessionStart` hook `brain-catchup`, `startup` only, forks to the background | Sessions that ended without a clean `SessionEnd` (closed terminal, crash, `claude -p` runs) are picked up the next time the user opens the agent; it looks at transcripts modified in the last 7 days, so a fresh install does not silently backfill years of history — that is `/brain:distill --all`. Together the two hooks give complete coverage with no scheduler. |
| status reminder | `SessionStart` hook `brain-status`, **sync**, `startup\|resume\|clear\|compact` | Reads `.state/` only, so it is fast, and returns `hookSpecificOutput.additionalContext` with one line: `[brain] 3 digests pending since 2026-08-19, 1 unresolved conflict — run /brain:ingest`. If brief injection is enabled (open question), the brief rides in the same payload; if the working directory is a vault, so does the schema. Separate from the catch-up hook so the reminder never waits on a distill. |
| ingest | `/brain:ingest`, deliberate | Expensive, judgment-heavy, rewrites many pages. Running it in the background on random session starts would spend tokens invisibly, change `brief.md` unpredictably mid-day, and race across concurrent sessions. Automating it later is a one-line change in `hooks.json`, not an architecture change. |
| query, lint | `/brain:query`, `/brain:lint` | Interactive by nature. |

Rejected: `Stop` hook (fires every turn); a scheduler such as launchd or cron (an extra install step per machine, runs on days with nothing to do, and hooks already give complete coverage — documented as an alternative for anyone who wants fully unattended ingest); cloud scheduled agents (cannot read local transcripts).

Two guards the hooks need:

- **Recursion.** The distill runner calls `claude -p` for the summary, and that inner run could fire hooks too. The runner sets `BRAIN_INNER=1` (hook scripts exit immediately when it is set), runs with `--no-session-persistence` so no transcript is written, and loads no settings. Sessions whose `cwd` is the vault are also skipped — the `/brain:ingest` conversation is not itself a source.
- **Concurrency.** Several sessions can end or start at once. Distill takes an atomic lock (`mkdir .state/lock`) and the catch-up pass skips if the lock is held.

## Relationship to built-in agent memory

Claude Code's auto-memory (`~/.claude/projects/<project>/memory/`) is a per-project hot cache written during the session. Brain is the cross-project cold store written after the fact. They are complementary, and they will drift — so:

- Memory stays authoritative for "things the agent must know in this repo right now".
- The vault is authoritative for history, synthesis, and anything cross-project.
- `brief.md` is the bridge: when `inject_brief` is `true` in `~/.brain/config.json`, the plugin's `SessionStart` hook adds the routed vault's brief to every session (it passes the secret gate first). The default is `false`: injection costs tokens on every session, and a wrong synthesized fact would reach every conversation until lint catches it — so the switch is flipped once the owner has read a few weeks of the wiki and trusts it.
- Lint checks the two for contradictions; humans resolve them.

## Multi-device

If the vault is synced across machines with git:

- Each machine distills **its own** transcripts into `sources/sessions/`. These are new files or appends — they merge cleanly.
- **Ingest runs on one machine only.** Two machines rewriting `index.md`, `brief.md`, and entity pages will conflict daily. The `brain/last-ingest` tag therefore lives on that machine; human edits made elsewhere are seen once they are pushed.
- State files under `.state/` are per-machine and gitignored; distill discovers "what is new" from the vault's `sources/sessions/` directory, not only from local state.

## Porting to another host

Brain is built and tested as a Claude Code plugin. The pattern is host-neutral; the automation is not. On another agent you get the documents and the skills and supply the plumbing:

1. **Skills.** `skills/*/SKILL.md` follow the Agent Skills standard; `npx skills add` or copying the directories into the agent's skills folder gives you `/brain:init`, `ingest`, `query`, and `lint`. Untested until the skills exist.
2. **Schema.** Nothing injects `docs/schema.md`. Put it where the agent reads vault instructions — the vault's `AGENTS.md` — and refresh it when Brain updates.
3. **Transcripts.** `scripts/extract-transcript.sh` reads Claude Code's JSONL. Write a converter from the other agent's transcript format to the same intermediate form: one line per turn with `timestamp`, `role`, `text`, `cwd`. The distill runner does not care what produced it.
4. **Trigger.** Nothing fires distill. Run `/brain:distill` by hand, or wire `scripts/distill.sh` into a session-end hook if the agent has one, otherwise cron.

A native port packages exactly these: the host-specific files are `hooks/` and the extractor; everything else is shared.

## Non-goals

- Embedding search. `index.md` plus grep is enough at hundreds of pages; revisit only when it stops being enough.
- A UI. Obsidian or any markdown viewer works on the vault as-is.
- A scheduler. Hooks piggyback on actual usage; a day with no sessions needs no run.
- Automatic ingest, for now. Distill is automatic; ingest stays deliberate until the schema has settled and its output has been trusted for a while.
- A second host before it has been tested end to end.

## Cost model

Distill: a few thousand tokens per session with a small model — negligible. Ingest: one agentic run over the pending digests whenever the user invokes it, reading a handful of pages — on the order of a few interactive turns. Lint: weekly-ish. The whole system costs less per day than one real conversation.
