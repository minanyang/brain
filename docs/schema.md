# Default schema

This is the default schema a vault inherits. A host integration loads it at the start of a session whose working directory is a vault; the vault's own `CLAUDE.md` contains shared local overrides, and overrides win.

## Layout

```
vault/
├── CLAUDE.md            shared local overrides and glossary
├── AGENTS.md            Codex entry point; points back to the shared rules
├── sources/             immutable, machine- or hand-written; never browsed, only ingested
│   ├── sessions/
│   │   ├── claude/      Claude Code session digests
│   │   └── codex/       Codex session digests
│   ├── refs/            articles, links, documents handed over on purpose
│   └── memory/          snapshots of the agent's built-in memory files, one per change
├── me/ people/ projects/ decisions/ topics/   default page types; vaults may add more
├── index.md  log.md  brief.md
└── .state/              per-machine, gitignored
```

## Page types

The default set is `me`, `person`, `project`, `decision`, `topic`, mapping to the five directories above. A vault may declare additional page types — and additional source directories under `sources/`, such as a daily journal — in its `CLAUDE.md`:

```markdown
## Page types
- `company/` (type `company`): org units, processes, and internal systems of my employer.
```

Ingest treats a declared type exactly like a default one: a directory, an `index.md` group, a digest tag (`[company]`), and a `type:` value. Undeclared types are never invented; a fact that fits no type goes to `topics/`.

## Page frontmatter

Every wiki page:

```yaml
---
title: Payments service
type: me | person | project | decision | topic   # or a type the vault declares
brief: false          # true → included when brief.md is compiled
volatile: false       # true → lint flags claims older than 30 days
locked: false         # true → ingest never rewrites this page; it may only append to ## Conflicts
updated: 2026-08-21
sources: [sources/sessions/claude/2026-08-05-invoice-retry.md, sources/refs/2026-08-12-idempotent-workers.md]
---
```

## Page body conventions

- Lead with a two-sentence summary. The rest is headed sections.
- Every non-obvious claim cites its source inline: `(→ sources/sessions/claude/2026-08-05-invoice-retry.md)`. A claim that came from a human edit is cited `(→ human, 2026-08-22)`.
- Human-sourced claims outrank digest-sourced ones. Ingest may not remove or alter them; a later digest that contradicts one is recorded under `## Conflicts`, not applied. Humans edit pages directly — ingest detects the edits from git (see architecture.md, ingest step 0); no special syntax is required.
- Link other pages with `[[directory/page]]`. Link liberally; a link to a page that does not exist yet is a TODO for ingest, not an error.
- Dates are absolute (`2026-08-21`), never relative ("last week").
- Contradictions live under `## Conflicts`, one line each: `- [open] 2026-08-21: "<existing claim>" (→ its source) vs "<new claim>" (→ new source)`. The agent never picks a winner. When a human decides, the winning claim goes into the body cited `(→ human, date)` and the entry becomes `- [resolved 2026-08-22] …`. The fixed prefix is what the reminder and lint grep for.
- Pages are rewritten, not appended to. History is in git, not in the page.

## Status claims

A status is a claim that stays true only until something moves: merged or not, deployed or not, fixed, open, blocked, who owns it. A present-tense status with no date reads as true forever, and it is the claim a page most often gets wrong.

- **Dated.** Write it as of a date: "As of 2026-09-22, the fix is on `main`." A dated status is still true after the branch moves, as history. An undated one silently becomes false.
- **Checked where git can settle it,** and marked so it can be checked again: `(verified 2026-09-22: ~/Repos/acme-billing a1b2c3d in origin/main)`, or `not-in`. The fields are fixed: the date, the repository's path, a commit, `in` or `not-in`, and a ref. `scripts/verify.sh` re-checks every marker; ingest prep and lint list the ones that no longer hold. Write what git shows, not what a session believed.
- **One home.** Each status lives on exactly one page, the page of the thing it is the status of (its project, or its ticket's topic page). Other pages link there with `[[…]]` and do not restate it. A status copied onto five pages is updated on one and stale on four.
- **Newer is an update, not a conflict.** A status dated later than the one on the page replaces it; keep the old one as a one-line dated event only if it matters. `## Conflicts` is for claims about the same moment that disagree.

## Primary documents

When the authority for a fact is a document in a repository — a spec, a runbook, a release record, an ADR — the page states the conclusion in a sentence and cites the document by path: `(→ ~/Repos/acme-billing/docs/adr/0007-retries.md)`. The reasons, the steps and the numbers stay in the document. A page that retells a spec is read instead of the spec, and what the retelling dropped is lost to every reader after it. The page's own value is what no single document holds: how the documents connect, what happened between them, and where to look.

## Session digest template

```markdown
---
session: 7f3a1c2e-0b4d-4e8a-9c1f-2d5e6a7b8c9d
date: 2026-08-05
cwd: ~/Repos/acme-billing
branch: main
title: Add retry policy to invoice worker
host: claude
ingested: false
---

## What happened
3–6 bullets. Past tense. What was built, fixed, investigated, decided.

## Decisions
- <decision> — because <reason>. (Omit section if none.)

## Learned
Facts worth keeping, each tagged:
- [me] prefers …
- [person:platform-team] owns CI and the deploy pipeline …
- [project:acme-billing] the invoice worker retries 3× with backoff …
- [topic:git-tags] …

## Open threads
- Things left unfinished or explicitly deferred.

## Continued (YYYY-MM-DD)
Appended when a session is resumed after it was first distilled. Same sections. Appending also resets `ingested` to `false`, so the new part is integrated by the next ingest; ingest prep reports the line the new part starts at, so the earlier part is not read again, and the pending reminder dates the file from its last append.

## Part 2 of N
Present when the session was too long for one model call. Same sections.
```

New digests are stored under the matching host directory. Digests created before host separation may remain directly under `sources/sessions/`; ingest and lint support both layouts so existing citations remain valid. The distiller is instructed: no code blocks longer than 5 lines, no tool output, no secrets or tokens, no speculation — only what the transcript supports.

## Ref template

```markdown
---
url: https://example.com/posts/idempotent-workers
title: Designing idempotent background workers
added: 2026-08-21
why: the retry design for the invoice worker should follow this
ingested: false
---

<extracted text of the article or document, as markdown>
```

`why` is written by the human and is the only part ingest treats as an opinion; the body is treated as an external source and cited as such.

## Memory snapshot template

```markdown
---
memory: ~/.claude/projects/-Users-me-Repos-acme-billing/memory/reconciler-retry-policy.md
project: ~/Repos/acme-billing
added: 2026-08-21
title: "reconciler-retry-policy"
ingested: false
---

<the memory file, verbatim, frontmatter included>
```

Written by `scripts/memory-sync.sh` whenever the memory file's content changes; `memory` is the file it came from and `project` the working directory it belongs to. The body is the agent's own note, written during a session with the code in front of it, and is cited `(→ sources/memory/<file>.md)`. A later snapshot of the same `memory` path is a revision of the earlier one, not a contradiction.

## index.md

```markdown
# Index

## me
- [[me/working-style]] — how I like to work with agents; review preferences.

## people
- [[people/platform-team]] — owns CI and the deploy pipeline; contact: …
```

One line per page — the page's first sentence — grouped by directory, alphabetical within a group. Generated from the pages by `scripts/index.sh` at the end of every ingest; never written by hand or by the agent, so it cannot drift from the pages.

## log.md

```markdown
## [2026-08-21] distill | 3 sessions (acme-billing ×2, home ×1)
## [2026-08-21] ingest | 3 digests → 7 pages updated, 2 created, 1 conflict on topics/release-process
## [2026-08-21] query | "why do we not run ingest automatically?" → filed decisions/deliberate-ingest
```

Append-only. Prefix format is fixed so it is greppable.

## brief.md

Compiled from pages with `brief: true`: the page title, its opening summary, and a link. Generated at the end of every ingest. Target ≤ 30 lines, so keep the `brief: true` set small. Never hand-edited — change the source page instead.

## Lint rules

1. Unresolved `## Conflicts` older than 14 days.
2. `volatile: true` pages not updated in 30 days.
3. Pages with no inbound links.
4. Names appearing on ≥ 3 pages with no page of their own.
5. Digests with `ingested: false` older than 2 days.
6. `brief.md` claims that contradict `~/.claude/projects/*/memory/*.md`.
7. Any `(→ human, …)` claim present before an ingest and absent after it.
8. `index.md`, `brief.md` or `log.md` not valid UTF-8 — a generated file cut mid-character makes grep treat it as binary and skip it silently.
9. A `(verified …)` marker that git no longer bears out.
