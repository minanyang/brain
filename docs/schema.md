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
├── me/ people/ projects/ decisions/ topics/ procedures/   default page types; vaults may add more
├── index.md  log.md  brief.md
└── .state/              per-machine, gitignored
```

## Page types

The default set is `me`, `person`, `project`, `decision`, `topic`, `procedure`, mapping to the six directories above. A vault may declare additional page types — and additional source directories under `sources/`, such as a daily journal — in its `CLAUDE.md`:

```markdown
## Page types
- `company/` (type `company`): org units, processes, and internal systems of my employer.
```

Ingest treats a declared type exactly like a default one: a directory, an `index.md` group, a digest tag (`[company]`), and a `type:` value. Undeclared types are never invented; a fact that fits no type goes to `topics/`.

### Procedures

A `procedures/` page is the one page type that gets **executed** rather than read, and that changes what it has to carry. A wrong `topics/` page misleads a reader who can weigh it; a wrong procedure gets run.

- **Only what has been done.** A procedure is written from a session that actually carried it out, and it records `Last run <date>` with what it was run against. A sequence nobody has executed is a plan, and plans stay in conversation — the same bar that keeps unverified status off a page, for the same reason.
- **Three sections, in this order.** `## When` is the trigger, so a reader can tell in one line whether this is their situation. `## Steps` is numbered, each step citing its source and naming the exact command where there is one. `## Checking it worked` is how you know it finished — a procedure with no check is one whose failures are discovered later by somebody else.
- **The steps come from the trace, not the prose.** What a session *said* it did and what its tool calls show are different documents, and the second is the one worth keeping. A digest records both; the procedure is written from the commands.
- **A step that names a version or a path is a status claim** and carries a marker like any other: `(verified 2026-09-22: ~/Repos/acme a1b2c3d in origin/main)`. Procedures go stale in a way topics do not, because the command keeps working while doing something else; set `volatile: true` and lint rule 2 will ask when its claims were last checked.
- **One procedure, one page.** Two ways of doing the same thing are a conflict, recorded like any other — not two pages, which is how a reader comes to run the abandoned one.

## Page frontmatter

Every wiki page:

```yaml
---
title: Payments service
type: me | person | project | decision | topic | procedure   # or a type the vault declares
brief: false          # true → included when brief.md is compiled
volatile: false       # true → lint flags claims older than 30 days
locked: false         # true → ingest never rewrites this page; it may only append to ## Conflicts
deprecated: false     # or "<date> — superseded by [[dir/page]]": kept for the record, read as history
aliases: []           # other names for this page's subject, searched exactly as its own name is
updated: 2026-08-21   # when this page's text last changed; when its claims were last checked is the newest (verified …) marker
# generated — provenance.sh rewrites the two fields below from this page's own citations; hand edits are discarded
sources: [sources/sessions/claude/2026-08-05-invoice-retry.md, sources/refs/2026-08-12-idempotent-workers.md]
sources_cited: 2
---
```

`aliases:` is the one field written for the search rather than the reader. A page is found by its own name as well as its text, which answers "version train" on a page whose body never writes those words — but only in the vault's own vocabulary. The questions that still miss are the ones asked in another: a plural the page uses in the singular, a paraphrase, the English name of a subject the page records in Mandarin. Each alias is matched exactly as the page's name is, so it earns the same two mentions and the same tie-break, and it composes with the character-bigram fallback rather than competing with it — a Mandarin alias is what those bigrams land on. On the hook that pushes pages unasked it is more than a help: a term in a script the vault does not write in counts for nothing there unless it names a page or sits in its `aliases:`, because document frequency cannot tell rare from uninformative in a script the vault barely contains. A question asked wholly in that script is answered through an alias or not at all. Write what a reader would plausibly type and the page does not say; do not restate the name, and keep the list short, because an alias on the wrong page is a wrong answer with a name-hit's weight behind it. Two pages sharing an alias make it ambiguous and neither will reliably win.

`sources:` and `sources_cited:` are **generated, never written by hand** — `scripts/provenance.sh` rebuilds them from the page's own inline `(→ sources/…)` citations at the end of every operation, exactly as `index.sh` rebuilds `index.md`, and for the same reason: a generated field cannot drift from the page. Hand-maintained it did, in both directions and silently — over one 180-page vault, 9 % of its entries named a source no claim cited any more, 46 citations were missing from it, and a third of the pages disagreed with their own bodies. Nothing in the pipeline reads either field; the authority for what a page draws on is the citation beside the claim.

The list is capped at the twelve most recent sources (`BRAIN_SOURCES_CAP`) and `sources_cited:` records how many there are, because an uncapped roll-up grows without limit: one page reached 201 entries and spent 17 KB of its 100 KB on them, which is provenance crowding out the content it is provenance for.

## Generated, checked, reported

Three kinds of content sit side by side in a vault and are worth different amounts, so each says on the page itself which it is. Without the markers an agent treats all three alike: it rewrote a generated roll-up by hand (silently overwritten at the next operation) and quoted a one-session claim as if git had settled it.

| Kind | How it is marked | What it is worth |
| --- | --- | --- |
| **Generated** | the `# generated` comment above `sources:`/`sources_cited:`, and the `<!-- generated … -->` first line of `index.md`, `brief.md` and `log.md` | rebuilt from the pages at the end of every operation. Editing it changes nothing and the edit is lost without a trace, so change the page it is derived from instead. |
| **Checked** | a `(verified <date>: …)` marker on the claim | something outside the vault was read and said this on that date. `scripts/verify.sh` re-checks every marker, so a checked claim that stops holding becomes a finding rather than quietly going wrong. |
| **Reported** | a `(→ source)` citation and nothing else — the bulk of every page | what one session, article or human said. It may be true and unchecked, or it may be what somebody believed. Cite it as the report it is; do not restate it as established, and check it before acting on it where git or a document can settle it. |

A claim with no citation at all is none of the three and does not belong on a page.

## Page body conventions

- Lead with a two-sentence summary. The rest is headed sections.
- Every non-obvious claim cites its source inline: `(→ sources/sessions/claude/2026-08-05-invoice-retry.md)`. A claim that came from a human edit is cited `(→ human, 2026-08-22)`.
- Human-sourced claims outrank digest-sourced ones. Ingest may not remove or alter them; a later digest that contradicts one is recorded under `## Conflicts`, not applied. Humans edit pages directly — ingest detects the edits from git (see architecture.md, ingest step 0); no special syntax is required.
- Link other pages with `[[directory/page]]`. Link liberally; a link to a page that does not exist yet is a TODO for ingest, not an error.
- Dates are absolute (`2026-08-21`), never relative ("last week").
- Contradictions live under `## Conflicts`, one line each: `- [open] 2026-08-21: "<existing claim>" (→ its source) vs "<new claim>" (→ new source)`. The agent never picks a winner. **The contested claim is also marked where it sits in the body**, `[contested 2026-08-21]` at the end of its sentence. A conflict section at the foot of the page is not read by anyone answering a question from the body, so without the mark the agent quotes a claim the vault already knows is disputed and quotes it as settled — which is the one failure the section exists to prevent. The mark travels with the claim; the entry carries the evidence. When a human decides, the winning claim goes into the body cited `(→ human, date)`, the mark comes off, and the entry becomes `- [resolved 2026-08-22] …`. Lint rule 15 checks the three ways the two can fall out of step: an open conflict whose claim is unmarked, one whose quoted claim is no longer in the body at all, and a mark left behind after a resolution.
- **Not every disagreement is a contradiction.** A claim about a state that something can change — merged, deployed, who has access, how many there are — can be true at one date and false at another, so a later source saying it changed is an *update*: write the new status dated, keep the old one as a dated event line, and open no conflict. Nothing is discarded and no winner is picked; the page carries a sequence. A claim about something already settled — why a choice was made, what a commit did, when something launched — cannot be true in two versions, so a source that disagrees goes under `## Conflicts`. The test is whether both claims could be true at different times. Getting this wrong in the safe direction fills the section with staleness nobody can act on; getting it wrong in the other direction overwrites a claim, and that is the one that leaves no trace. The fixed prefix is what the reminder and lint grep for. A third prefix, `- [unresolvable <date>] … — <why>`, is for a conflict whose evidence is gone: the log was rotated, the console retention passed, the branch was deleted. Lint stops counting it as a finding and reports how many there are, because a question that cannot be settled is not a backlog item and reporting it every week teaches people to ignore the report. The bar is high and the reason is required — "nobody has checked yet" is `[open]`, and only a human may mark a conflict unresolvable, for the same reason only a human may resolve one.
- Unfinished business lives under `## Open threads`, one line each, prefixed and dated like a conflict: `- [thread 2026-08-21] <what is unfinished, or the question> — waiting on <the thing that would close it> (→ its source)`. A thread is closed by that thing happening, which is a later source saying so, and the only moment anyone is looking at both is the ingest that files that source: it writes the answer into the body as an ordinary dated claim and re-prefixes the entry `- [closed 2026-09-05] <the thread> — <what closed it> (→ the source that closed it)`. The closed entry stays where it is, exactly as a `[resolved]` conflict does, because it is the evidence that the question was asked and answered and a page that drops it invites the same question again. Never delete an open thread to tidy a page: an entry nobody can close is still true, and it is the `[closed …]` prefix, not deletion, that takes one out of the count lint reports (rule 13).
- An idea that was proposed and rejected lives under `## Rejected`, on the page of the thing it was about: `- [rejected 2026-09-05] <what was proposed> — <what killed it>: <the evidence> (→ its source)`. All four parts are required, the evidence most of all: a rejection without its reason is re-litigated by the next agent that has the same idea, which is the whole failure this section exists for. Check this section before proposing anything that looks like new work on a page — `grep -rn '^- \[rejected' <vault>` finds every one in the vault, since the idea may have been killed on a neighbouring page. A rejection with consequences beyond the one session is promoted to a `decisions/` page like any other decision, and the entry becomes the pointer to it. Only a human overturns a rejection; new evidence that argues against one goes under `## Conflicts` with it, where the entry already names what the old evidence was.
- Pages are rewritten, not appended to. History is in git, not in the page.

## Status claims

A status is a claim that stays true only until something moves: merged or not, deployed or not, fixed, open, blocked, who owns it. A present-tense status with no date reads as true forever, and it is the claim a page most often gets wrong.

- **Dated.** Write it as of a date: "As of 2026-09-22, the fix is on `main`." A dated status is still true after the branch moves, as history. An undated one silently becomes false.
- **Checked where git can settle it,** and marked so it can be checked again: `(verified 2026-09-22: ~/Repos/acme-billing a1b2c3d in origin/main)`, or `not-in`. The fields are fixed: the date, the repository's path, a commit, `in` or `not-in`, and a ref. `scripts/verify.sh` re-checks every marker; ingest prep and lint list the ones that no longer hold. Write what git shows, not what a session believed.
- **One home.** Each status lives on exactly one page, the page of the thing it is the status of (its project, or its ticket's topic page). Other pages link there with `[[…]]` and do not restate it. A status copied onto five pages is updated on one and stale on four.
- **No exclusive quantifier without exhaustive evidence.** "the only", "never", "always", "nowhere else" turn a gap in what you read into a claim about the world. Consolidating two sources into one sentence is where this happens: a page that recorded one run and a page that recorded none became "the only recorded run", which was false and was then repeated by every agent that read it. Write what is recorded ("recorded in dev and in staging"), and if exhaustiveness matters, say what was searched.
- **Newer is an update, not a conflict.** A status dated later than the one on the page replaces it; keep the old one as a one-line dated event only if it matters. `## Conflicts` is for claims about the same moment that disagree.

## Deprecated pages and claims

A page or a claim that has been superseded but is still worth keeping has had two bad options: delete it and lose the record of a thing the user will still meet in the wild, or leave it reading as current. `deprecated:` is the third.

```yaml
deprecated: 2026-09-05 — superseded by [[decisions/2026-08-14-invoice-worker-retries-with-backoff]]
```

- The value is required to carry **the date and what superseded it** — a page link, or, when nothing replaced it, what ended it and why. A bare `deprecated: true` says a page is history without saying where the reader should be instead, which is the state it was deprecated to escape. `false` (or the field's absence) is a live page.
- **Nothing is filed onto a deprecated page.** Ingest sends the fact to the successor, and rewrites the deprecated page only to correct a wrong claim or append to its `## Conflicts`; filing new facts onto it undoes the deprecation without anyone deciding to.
- **Deprecating replaces deleting.** Point the inbound `[[links]]` at the successor and leave the page. Its inbound links then go, which is the expected end state and the reason lint rule 3 skips it — a deliberate pointer back at it from the successor, for the reader who still meets the old thing, is the exception; rule 2 skips it too, since a deprecated page is not meant to be updated.
- **Injection and the session map.** `index.md` carries `(deprecated …)` in front of the page's summary, so the session map — which quotes those lines — sends the reader to the successor. A deprecated page is never compiled into `brief.md`, whatever its `brief:` says, because the brief is the one text every session pays for and history there is pure cost.
- **A single claim** is deprecated in place when it reads as current and someone will still meet the old thing: `The replay script is run by hand after a dead-letter (deprecated 2026-09-05: superseded by the retry policy) (→ its source)`. Where no one will meet it again, fold it into a one-line dated event instead — that is the ordinary case, and a page full of deprecation markers is a page that needs splitting.
- Lint reports a page deprecated more than 180 days ago (rule 14), because the point of keeping it is that someone still meets the old thing, and after half a year that is a claim worth re-making deliberately: fold what is still wanted into the successor and delete the page, which git keeps and `restore-page.sh` brings back.

## Primary documents

When the authority for a fact is a document in a repository — a spec, a runbook, a release record, an ADR — the page states the conclusion in a sentence and cites the document by path: `(→ ~/Repos/acme-billing/docs/adr/0007-retries.md)`. The reasons, the steps and the numbers stay in the document. A page that retells a spec is read instead of the spec, and what the retelling dropped is lost to every reader after it. The page's own value is what no single document holds: how the documents connect, what happened between them, and where to look.

## Session digest template

Distillers preserve an explicit correction as a `Correction: <wrong claim> → <correct claim> — <stated evidence or reason>` bullet under `What happened`. The digest distinguishes the user's correction from facts independently verified in the session.

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
- Things left unfinished or explicitly deferred. Ingest turns each into a `- [thread <date>]` entry on the page of the thing it waits on, or closes one already there.

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
<!-- generated by brain (scripts/index.sh) — edits are overwritten; change the page -->
# Index

## me
- [[me/working-style]] — how I like to work with agents; review preferences.

## people
- [[people/platform-team]] — owns CI and the deploy pipeline; contact: …
- [[people/release-captain]] — (deprecated 2026-09-05 — superseded by [[people/platform-team]]) who used to own the deploy calendar.
```

One line per page — the page's first sentence — grouped by directory, alphabetical within a group, with `(deprecated …)` in front of the summary of a page whose frontmatter carries it. Generated from the pages by `scripts/index.sh` at the end of every ingest; the first line says so, because the file a reader meets first is the one most likely to be edited by hand, and never written by hand or by the agent, so it cannot drift from the pages.

## log.md

```markdown
<!-- generated by brain (scripts/finish.sh) — append-only; edits are not read back -->
## [2026-08-21] distill | 3 sessions (acme-billing ×2, home ×1)
## [2026-08-21] ingest | 3 digests → 7 pages updated, 2 created, 1 conflict on topics/release-process
## [2026-08-21] query | "why do we not run ingest automatically?" → filed decisions/deliberate-ingest
```

Append-only, by `finish.sh` alone. Prefix format is fixed so it is greppable.

## brief.md

Compiled from pages with `brief: true`: the page title, its opening summary, and a link, under the same `<!-- generated … -->` first line. Generated at the end of every ingest, and a page carrying `deprecated:` is left out of it whatever its `brief:` says. Target ≤ 30 lines, so keep the `brief: true` set small. Never hand-edited — change the source page instead.

## Lint rules

1. Unresolved `## Conflicts` older than 14 days.
2. `volatile: true` pages whose claims were last checked over 30 days ago. The date is the newest `(verified <date>: …)` marker on the page, and `updated:` only where there is no marker — `updated:` says when the page's *text* changed, which an ingest appending one open thread bumps without re-verifying anything, so a page can read as fresh while every status on it is stale. The check date is derived rather than kept in a third frontmatter field, for the reason `sources:` is derived: a hand-kept date drifts from what it describes, and this one would drift towards looking checked. The report says which of the two it used, because the action differs — re-check the claims, or give them markers at all. Pages carrying `deprecated:` are skipped: they are not meant to be updated.
3. Pages with no inbound links. Pages carrying `deprecated:` are skipped: having their links moved to the successor is what deprecating one does.
4. Names appearing on ≥ 3 pages with no page of their own.
5. Digests with `ingested: false` older than 2 days.
6. `brief.md` claims that contradict `~/.claude/projects/*/memory/*.md`.
7. Any `(→ human, …)` claim present before an ingest and absent after it.
8. `index.md`, `brief.md` or `log.md` not valid UTF-8 — a generated file cut mid-character makes grep treat it as binary and skip it silently.
9. A `(verified …)` marker that git no longer bears out.
10. An exclusive quantifier ("the only", "no other", "never ran") inside a claim a human or a verification settled — the shape a consolidated contradiction takes when it overstates.
11. Candidate status claims on different pages that mention the same ticket, carry dates within three days, and have opposite polarity for the same action. The unit is a clause, not a line, and a clause that carries neither its own ticket nor its own date is not considered; pointer lines containing `status on [[…]]` are excluded. This is an advisory scan (`scripts/cross-page-claims.sh`): candidates are excluded from the lint findings count until an agent confirms a real contradiction; the scan never chooses a winner.
12. A date or a `(verified …)` marker in the lead paragraph of a `brief: true` page. The lead is copied into `brief.md` verbatim and injected at the start of every session, so a fact with a shelf life belongs in a dated section below, not there.
13. A page whose `## Open threads` carries more than 12 entries that are not `[closed …]`. The finding is the page, not any one thread: which thread the body has already answered needs the page's sense, and a scan for it was measured on a real vault at 30 hits for 5 defects, the same shape as four rules abandoned before it. A count is exact and bounded — one line per page, eight on a 208-page vault whose 139 thread sections held 684 entries — and the action is a human-or-agent sweep of that one section with the page in front of it.
14. A page deprecated more than 180 days ago, or a `deprecated:` value with no date or nothing after it. The first is a page to fold into its successor and delete; the second is a page that says it is history without saying where to go instead.
15. A contested claim whose `[contested …]` mark and its `## Conflicts` entry disagree, in any of three ways: an `[open]` conflict whose quoted claim carries no mark in the body, one quoting a claim the body no longer carries (the page was rewritten under the entry), or a `[contested …]` left on a page with no open conflict (the human resolved it and the mark stayed). The mark is what a reader of the body sees; the entry is where the evidence is. Each drifts from the other silently, which is why this is a check and not another paragraph.
