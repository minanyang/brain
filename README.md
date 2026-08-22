# Brain

A pattern for letting an LLM agent build a persistent, compounding understanding of **you and your work** — distilled from every session you have with it, plus whatever you hand it — and stored as a wiki it maintains on your behalf.

It generalizes [Karpathy's LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) in two ways: the subject is not an external topic but your own work and context, and the sources are not curated documents but the noisy streams an agent already produces.

This repository holds the **pattern and the reference implementation**. Your actual knowledge lives in a separate, private repository — the *vault* — that this repository never sees. See [Two repositories](#two-repositories).

## The problem

Every agent session starts from zero. Built-in memory features store a handful of atomic facts per project; compaction throws the rest away; the full transcripts sit on disk unread. After a hundred sessions the agent knows no more about the people you work with, your codebase's history, or how you like to work than it did on day one — everything it learned is buried in JSONL files nobody opens.

Meanwhile the knowledge that would make the agent a real colleague — who owns what, why a decision was made in March, which service is the fragile one, what you are on the hook for this quarter — is exactly the kind that only accumulates slowly, across many conversations and many days of work.

## The idea

Treat your sessions, and anything you hand the agent on purpose, as **sources**, and have the agent maintain a **wiki** compiled from them:

- Every session is distilled once into a short, immutable digest: what was done, what was decided, what was learned about you, the people around you, the project, what was left open.
- Things that happen outside a session reach the vault without a daily writing habit: mention them in any session and they land in that day's digest; hand over an article, a document, or meeting notes and it is kept as a ref.
- An ingest pass integrates new digests and refs into a wiki of entity and topic pages: `me/`, `people/`, `projects/`, `decisions/`, `topics/` — plus whatever page types your situation needs, declared per vault. Cross-references are maintained, contradictions flagged, stale claims superseded.
- The most load-bearing facts are compiled into a short **brief** that can be injected into every new session, so the agent starts each conversation already knowing the shape of your world. Everything else is queried on demand.

The wiki is a compounding artifact. You never write it; you read it, correct it, and ask questions against it — and good answers are filed back in.

## Why not …

| Alternative | What it lacks |
| --- | --- |
| RAG over transcripts | Rediscovers everything on every query. No synthesis, no contradiction tracking, and transcripts are 80% tool output. |
| Built-in agent memory | Per-project, atomic, written in the moment. No cross-project synthesis, no retrospection, no history of why. A good **hot cache** — Brain is the cold store behind it. |
| LLM Wiki as-is | Assumes clean, hand-curated sources. Raw agent transcripts need a distillation layer before they are fit to integrate. |
| Writing notes yourself | You will stop within two weeks. The bookkeeping is the part humans abandon. |

## Architecture

Four layers, not three. The extra one is what makes noisy streams usable as sources.

```
 0  Streams    immutable, stay on the machine, never in any repo
               agent transcripts (~/.claude/projects/**/*.jsonl for Claude Code),
               later: calendar, Notion, Slack exports
                      │  distill  (mechanical, idempotent, cheap model)
 1  Sources    immutable, in the vault
               sources/sessions/<date>-<slug>.md   one digest per session
               sources/refs/<date>-<slug>.md       articles, links, documents you hand over
                      │  integrate  (judgment, stronger model)
 2  Wiki       owned and rewritten by the agent
               me/  people/  projects/  decisions/  topics/  (+ vault-defined)
               index.md (catalog)   log.md (timeline)   brief.md (compiled, injected)
                      │
 3  Schema     the vault's CLAUDE.md: layout, page types, conventions, workflows
```

Details: [docs/setup.md](docs/setup.md) for the step-by-step · [docs/architecture.md](docs/architecture.md) · page conventions: [docs/schema.md](docs/schema.md) · what never leaves the machine: [docs/privacy.md](docs/privacy.md).

## Operations

| Op | Trigger | What it does |
| --- | --- | --- |
| **[distill](skills/distill/SKILL.md)** | automatic — `SessionEnd` hook for the session that just ended, `SessionStart` hook catches anything missed | New or grown transcript → clean conversation text → digest. Tracks byte offsets so resumed sessions are processed incrementally. |
| **[ingest](skills/ingest/SKILL.md)** | deliberate — `/brain:ingest`; the `SessionStart` hook reminds you when digests or unresolved conflicts are pending | Reads new digests / log entries / human edits, updates entity and topic pages, `index.md`, `log.md`. Records contradictions instead of overwriting, then asks you to decide them. |
| **[query](skills/query/SKILL.md)** | `/brain:query` | Reads `index.md`, drills into pages, answers with citations back to digests and session ids. Answers worth keeping are filed as new pages. |
| **[lint](skills/lint/SKILL.md)** | `/brain:lint`, weekly-ish | Contradictions, stale claims, orphans, concepts without pages, drift between the wiki and the agent's built-in memory. |
| **[clip](skills/clip/SKILL.md)** | `/brain:clip <url>` | Keeps an article or document as a ref — one line from you on why it matters — for the next ingest. |
| **brief** | after every ingest | Recompiles `brief.md` — the ~30 lines worth loading into every session; injected at session start when you turn `inject_brief` on. |

## Two repositories

| | `brain` (this repo) | vault (yours, private) |
| --- | --- | --- |
| Contains | pattern, docs, reference scripts, templates, default schema | digests, refs, wiki pages, state — and a thin `CLAUDE.md` that imports the default schema and adds local overrides |
| Visibility | public | private, or local-only git |
| Knows about you | nothing | everything |

The split is deliberate: the mechanism and the general conventions are worth sharing; the content is not, and neither are the situation-specific conventions — an employer's org chart, a client list, a research programme — that will grow on top of the defaults. Conventions that turn out to be general get promoted upstream; the rest stays in the vault's `CLAUDE.md` as a delta.

## Installation

### Claude Code

```
/plugin marketplace add minanyang/brain
/plugin install brain@brain
```

Then `/brain:init <path>` to create your first vault. Needs `git` and `jq`. Full walkthrough: [docs/setup.md](docs/setup.md).

### Other agents

Not supported yet. The skills follow the Agent Skills standard, so `npx skills add minanyang/brain` copies them into other agents, but distill depends on Claude Code's hooks and transcript format. What a port needs is listed in [docs/architecture.md](docs/architecture.md#porting-to-another-host).
