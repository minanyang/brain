# Architecture

## Layers

### 0 — Streams

Raw, append-only, machine-local. Never copied into any repository.

| Stream | Location | Notes |
| --- | --- | --- |
| Claude Code transcripts | `~/.claude/projects/<cwd-slug>/<session-id>.jsonl` | One line per event (`user`, `assistant`, `system`, tool results, `ai-title`, …). Full history survives context compaction — compaction only affects what the model sees, not the file. Sessions grow while open and when resumed. |
| Codex transcripts | `<CODEX_HOME>/sessions/<year>/<month>/<day>/rollout-*.jsonl` | Rollout events include session metadata, conversation messages, tool calls, and internal events. The adapter keeps conversation and compact tool summaries and drops instructions, reasoning, and duplicate event mirrors. |
| Calendar, Notion, Slack | via MCP or exports | Later phases. Pulled, not pushed. |

Claude Code and Codex are implemented streams. Adding another agent means one adapter that yields `(timestamp, role, text, cwd)` from wherever that agent keeps its history; nothing downstream changes.

### 1 — Sources

Immutable once written. Live under `sources/` in the vault, so machine-written material stays out of the way of the pages a human actually browses. Each is small, dated, carries provenance, and records whether ingest has consumed it (`ingested:` in its frontmatter; nothing is moved after processing).

- `sources/sessions/<host>/<YYYY-MM-DD>-<slug>.md` — one digest per session, separated by source host. Slug comes from the transcript's title when present, else from the first user message. Legacy flat files remain valid and are not moved, because wiki pages cite their paths.
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
- `sources:` on a page — generated, not authored, and capped. It is a roll-up of the inline `(→ sources/…)` citations, which are the authority for what a claim rests on, and nothing in the pipeline reads the roll-up. While it was hand-maintained it drifted in both directions without any signal: over one 180-page vault, 9 % of its entries named a source no claim cited any more, 46 citations were absent from it, and a third of the pages disagreed with their own bodies. Uncapped it also grew without limit — one page reached 201 entries and spent 17 KB of its 100 KB on them, which is provenance crowding out the content it is provenance for, and that page's size was in turn distorting how facts were filed. So `provenance.sh` rebuilds it from the body, keeps the twelve most recent, and records the true count in `sources_cited:`. The general rule this instance teaches: a field that is derivable from the page, and that nothing reads, is a second copy of the truth and will diverge from the first.

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

## Two repositories

| | `brain` (this repo) | vault (yours, private) |
| --- | --- | --- |
| Contains | pattern, docs, reference scripts, templates, default schema | digests, refs, wiki pages, state — and a thin `CLAUDE.md` that imports the default schema and adds local overrides |
| Visibility | public | private, or local-only git |
| Knows about you | nothing | everything |

The split is deliberate: the mechanism and the general conventions are worth sharing; the content is not, and neither are the situation-specific conventions — an employer's org chart, a client list, a research programme — that will grow on top of the defaults. Conventions that turn out to be general get promoted upstream; the rest stays in the vault's `CLAUDE.md` as a delta.

## Where things live

| Component | Lives in | Installed to |
| --- | --- | --- |
| `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` | this repo | the repo is its own marketplace: `/plugin marketplace add minanyang/brain`, then `/plugin install brain@brain` |
| Brain skills (`init`, `distill`, `ingest`, `query`, `lint`, `clip`) | this repo (`skills/`) | Claude loads them through the plugin; `scripts/install-codex.sh` generates Codex-bound `$brain-*` copies under the active Codex skill directory |
| Hooks (`SessionEnd` → distill, `SessionStart` → catch-up + status + auto-ingest) | this repo (`hooks/`) | Claude loads `hooks.json`; the Codex installer adds equivalent commands to its active `hooks.json` |
| Deterministic scripts: transcript extractor, distill runner, memory sync, secret gate, vault init, status, routing (`resolve-vault.sh`), ingest prep, auto-ingest, `finish.sh` (gate → mark sources → regenerate provenance → regenerate `index.md` and `brief.md` → log → commit → tag, shared by every op), `index.sh`, `provenance.sh` (rebuilds a page's `sources:` from its own citations), `lint.sh`, `ref.sh`, `verify.sh` (re-checks status markers against git), `git-read.sh` (read-only git for agents), `restated.sh` (finds every page repeating a claim) | this repo (`scripts/`) | called by skills and hooks via `${CLAUDE_PLUGIN_ROOT}` |
| Default schema, page and digest templates | this repo (`docs/schema.md`, `templates/`) | read by the skills from the plugin root; the schema is injected into in-vault sessions by the `SessionStart` hook |
| Per-machine config (vaults and their routing globs, transcript roots, model names, brief switch) | nowhere in git | `~/.brain/config.json` |
| Vault `CLAUDE.md`, `AGENTS.md`, sources, wiki, `.state/` | the vault | — |
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
    → host-specific extractor → clean conversation text
    → configured host model + digest template → sources/sessions/<host>/<date>-<slug>.md
      (or append a "## Continued" section if the digest already exists)
    record {host:session_id: {offset, digest_path, last_ts}} in .state/distilled.json
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

**Step 0 — collect human corrections.** The vault is a git repository and ingest is the only non-human process that commits wiki pages. After each ingest it moves the tag `brain/last-ingest`. Before the next ingest it runs `git diff brain/last-ingest -- me/ people/ projects/ decisions/ topics/ procedures/` (plus any directories the vault declares) (working tree included, so an edit saved in Obsidian counts without a commit). Every hunk in that diff is a human edit. The hunks are handed to ingest as a source that outranks every digest, and the claims they carry are cited as `(→ human, YYYY-MM-DD)` when the page is rewritten.

Then, in batches of pending sources (oldest first, ~15 at a time, so that progress is committed and a long run can stop and resume):

1. Extract facts and classify them by page type: the user, a person or team, a project, a decision, a topic, or any type the vault declares.
2. For each fact, find the page it belongs to (via `index.md` and the vault's glossary); create the page if missing.
3. Rewrite the page. If the fact contradicts an existing claim, do **not** overwrite and do **not** pick a winner — record both under `## Conflicts` as an `[open]` entry.
4. Finish the batch deterministically (`scripts/finish.sh --op ingest`): secret gate on every changed page, mark the sources `ingested: true`, regenerate `index.md` and `brief.md` from the pages, append to `log.md`, commit, move `brain/last-ingest`.
5. When the run stops, list every `[open]` conflict it created and ask the human to decide each one now or leave it. A decision is written immediately as a `(→ human, date)` claim on the page; the entry becomes `[resolved <date>]`.

Steps 1–3 are the skill's judgment; step 0 and step 4 are scripts (`ingest-prep.sh`, `finish.sh`).

Only ingest may stage the whole vault. Every other operation stages `index.md`, `brief.md`, `log.md` and the file it wrote, and reports what it left alone — because a human edit swept into a Brain commit vanishes from the next ingest's human-edit diff, which excludes Brain's own commits, and would never be cited `(→ human, …)` again. The two safeguards otherwise cancel each other out. The split is the same as distill's: the agent decides what a fact means, and never touches the bookkeeping.

Pages with `locked: true` are never rewritten; ingest may only append under their `## Conflicts`.

**Status is dated, checked and kept in one place; primary documents are linked, not retold** (schema: "Status claims", "Primary documents"). Both rules come from measuring the first vault after five weeks and 159 pages. Of 16 present-tense claims that a commit was or was not on a branch, 6 were false when checked against git, all made stale by one release. Of the dated claims, none was. One ticket's status was restated on 30 pages. A blind benchmark followed: 16 questions, each answered with and without the session-start context, 64 runs, graded against keys built from repositories only. It found no overall difference in correctness, and one pattern that did not depend on the grader. Where a repository's own document had gone stale and the vault had seen a later session, the vault helped. On "why was this decided" questions it hurt: agents answered from the page's summary of a spec and missed what the summary had dropped, and a wrong page claim was repeated in every answer that read it. So ingest now checks a status against git before writing it, through `git-read.sh`, and marks it. `verify.sh` re-checks every marker, ingest prep lists the ones that no longer hold so the next ingest rewrites them, and lint reports them as rule 9. A present-tense status therefore cannot quietly outlive the branch it describes.

`verify.sh` reports where a commit arrived on the ref, not where that ref points today. Reporting the tip, which it did until 2026-10-15, dates a claim to the day someone ran the check: a commit that reached `develop` on the 1st and `main` in the 10th's release was reported as arriving at whatever `main` pointed at, and one vault had twelve pages rewritten with a date up to six days late. An ancestry-path walk alone is not the fix — it names the merge into whichever branch took the commit first, and `--reverse` orders by ancestry rather than by date, so its first line is not the earliest. The arrival is the oldest of those merges that also sits on the ref's own first-parent spine. This matters more now that auto-ingest rewrites such claims unattended, where no one reads the output.

Trimming an overgrown page means deleting the original, and nobody does that willingly while the only way back is reading git history by hand, so the vault that most needs splitting is the one least likely to get it. `restore-page.sh` is the undo: it finds the newest commit that still carries the page — walking past the deletion commit, which has no blob to read — writes it into the working tree and stops, because `finish.sh` is the only path that gates and logs a change. It refuses to overwrite a page that still exists without `--over`, since the usual mistake is restoring over a rewrite rather than a deletion, and it says when nothing links to the restored page: the links were edited away when it was deleted, so a restore is exactly when a page becomes an orphan.

A wrong claim is rarely written once, and that is what makes it expensive. On 2026-09-23 a claim about a workflow was corrected on the page that had produced a wrong answer; the same sentence stood on two other pages, and the next measurement produced the same wrong answer from one of them. Which page an agent reads depends on how the question was asked, so a correction is not applied until every restatement is. `restated.sh` lists them from the claim's distinctive words, and ingest runs it whenever a decision makes a claim wrong. Entries under `## Conflicts` are quotations of what was said and are listed apart, because correcting those would rewrite the record.

An idea that was considered and rejected leaves no trace of having been considered, so it comes back.
This repository's own history holds three: a thirteenth lint rule prototyped and abandoned on
measurement, a rewrite in a faster language declined in favour of reviewing the algorithm, and
belief-strength scoring and cosine-similarity contradiction detection declined after comparable
projects were read. Each was written down by hand, in prose, in a different shape, which is the same
as not being written down: nothing can be read before proposing. So a rejection now has one shape and
one home — `- [rejected <date>] <proposal> — <what killed it>: <evidence> (→ source)` under `##
Rejected` on the page of the thing it was about, the same fixed-prefix, one-home treatment a conflict
and a status already get. The evidence is required because a rejection without its reason is
re-litigated by the next agent that has the idea and cannot see what killed it; `grep -rn '^- \[rejected'`
over the vault is the check before proposing, since the idea may have been killed on a neighbouring
page, and it is the clause the session map now carries for sessions that never open the vault. Only a
human overturns one: new evidence against a rejection goes under `## Conflicts` beside it, where the
old evidence is already quoted.

A page or a claim that has been superseded but is still worth keeping had two options and both were
bad: delete it and lose the record of something the user will still meet in old tickets and logs, or
leave it reading as current. `deprecated: <date> — superseded by [[dir/page]]` is the third, and the
value is required to carry both parts, because `deprecated: true` leaves the reader exactly where
deprecation was meant to get them out of — told this is history, not told where to go instead. What
reads the field is the generated layer: `index.sh` puts `(deprecated …)` in front of the page's
summary, so the session map, which quotes those lines, sends the reader to the successor, and
`finish.sh` leaves the page out of `brief.md` whatever its `brief:` says, since the brief is the one
text every session pays for. Ingest files nothing new onto a deprecated page — the fact goes to the
successor, because filing onto the old page undoes a deprecation nobody then re-decides — and
deprecating replaces deleting, with the inbound links moved to the successor. That makes a deprecated
page orphaned and un-updated on purpose, so lint rules 3 and 2 skip it, and rule 14 reports it after
180 days: keeping it is a claim that someone still meets the old thing, and after half a year that is
worth making again deliberately rather than by default.

Open threads accumulate and nothing removes them. A thread is closed by the thing it was waiting for
happening, which arrives as a later source, and the only moment anyone holds both the thread and that
source is the ingest that files it; left for later, nobody goes back. Measured on a real vault: 684
thread entries across 139 pages of 208, two of them carrying no date — the practice was already to
write a dated line with a citation, so what was missing was not discipline but an exit. A thread is
therefore prefixed like a conflict, `- [thread <date>] … — waiting on <the thing>`, and closed in
place as `- [closed <date>] … — <what closed it> (→ the source that closed it)` with the answer written
into the body as an ordinary dated claim. The closed entry stays, exactly as a `[resolved]` conflict
does, because it is the evidence that the question was asked and answered, and a page that drops it
invites the question again; deleting a thread to tidy a page is the one move the ingest skill names as
forbidden here. What lint can say about a thread is only how many there are. Picking out the finished
one was prototyped — pair each thread's ticket id with a later-dated line elsewhere on the same page —
and fired 30 times for 5 real defects, because whether the later line answers the thread needs the
page's sense, which is how the four rules of 2026-10-13 died as well. So rule 13 counts instead, and
the action is a sweep of that one section with the page open — the same shape as asking ingest to check
the status claims of a page it is already reading, which found eight real defects where a scan found
none.

What a count alone cannot do is stop. The rule first reported any page past twelve entries, which was
8 pages on a 208-page vault; the sweep that followed closed five threads and left 82 standing, because
they were all still genuinely waiting on something. A page can therefore satisfy a stock threshold
permanently while being perfectly well kept, and a rule that names the same six pages at every run is
scenery rather than a finding. Since 2026-10-16 the finding is growth: a page is reported when its
list is longer than it was the last time lint ran, with the stock printed beside it, and the count
kept per page in the vault's gitignored `.state/lint-threads.json`. The first run on a vault with no
baseline still reports what is already past twelve, once, so a vault that has never been swept is not
silent. Growth is the right measure because it goes quiet the moment a section is tended and speaks
again when it starts collecting; and an entry's own date could not have replaced the baseline, because
most of a real vault's threads predate the `- [thread <date>]` shape and carry no date at all.

Three kinds of content sit side by side on a page and are worth different amounts. `index.md`,
`brief.md`, `log.md` and the `sources:`/`sources_cited:` fields are generated: rewriting them by hand
changes nothing and the edit is lost at the next operation. Claims carrying `(verified <date>: …)`
were checked against git and are re-checked by `verify.sh`. Everything else is a report of what one
session, article or human said. Nothing on the page said which was which, so an agent corrected a
generated roll-up by hand — the drift that made `sources:` generated in the first place was found the
same way — and quoted one-session claims as though git had settled them. Each kind now says so where
it is read: the generated files carry a `<!-- generated … -->` first line, written by the scripts that
generate them, and the two generated frontmatter fields carry a `# generated` comment that
`provenance.sh` reprints above them; a claim with a citation and no marker is a report, and the schema
says to cite it as one rather than restate it as established. No marker was invented for the third
kind, because it is the bulk of every page and a marker on every claim is a marker on none.

Ingest still detects contradictions only while rewriting the same page, so a ticket whose status is copied onto a project page and a topic page can drift. Lint runs `cross-page-claims.sh` for that: an advisory scan that pairs two pages making opposite dated claims about the same ticket and the same action within three days, excluding `status on [[…]]` pointers. The lint skill reads both pages and their cited sources before deciding whether they conflict; candidates stay out of the findings count until confirmed, and the scan never chooses a winner.

Its unit is a clause, not a line, because the schema's own conventions defeat a line-level scan. A page states one fact per line with its citations attached, so on the first vault the median line carrying a ticket id is 339 characters and often reports two actions at once. Comparing whole lines produced 717 candidates and no contradictions; skipping the long ones to quieten that left 15 of 504 ticket lines in scope, which is not a check. Splitting on clause boundaries and registering one entry per action verb keeps both the long lines and the per-action polarity: 80 entries over 44 tickets, no candidates on a vault whose contradictions had already been settled, and all three planted ones found.

Two restrictions earn their keep, each of them a false positive measured before it was a rule. A clause may inherit the ticket or the date from its line but not both: a clause carrying neither is prose sharing a sentence with a status claim, and inheriting both paired a general remark about a codegen script with six unrelated pages. And polarity belongs to the verb rather than to the clause, because a clause states more than one thing ("until TASK-n fixed it, the client had not been regenerated") and the negation can follow the verb as easily as precede it ("CI ran no tests"); the test is a window around the verb.

Distillation preserves explicit user corrections as a `Correction: <wrong> → <correct> — <stated evidence or reason>` bullet in `What happened`. A digest distinguishes a user's correction from an independently verified fact, so it does not imply that a check ran when it did not.

The lead paragraph of a `brief: true` page is the only text every session pays for: `finish.sh` copies the first non-blank, non-heading line into `brief.md` whole, and the hook injects it before anything else. That makes a dated fact there the most expensive kind of staleness, and until lint rule 12 it was also the least checked — `verify.sh` checks markers, `restated.sh` needs the claim named, and nothing looked at the lead. A lead that narrates events instead of stating what is now also grows: on the first vault one had reached 1990 bytes carrying 20 dates, 8 version numbers and 5 markers, every one of which a section further down the same page already held. The rule is scoped to `brief: true` pages and tests for a shelf life rather than for length — a date or a marker — because over all 163 pages the same test returns 152 findings and means nothing.

`git-read.sh` exists because a permission pattern cannot express "read-only git". `Bash(git -C * log *)` also admits `-c core.pager=<program>` and `--exec-path`, both of which run a program. The wrapper takes the repository and the subcommand as separate arguments, allows only subcommands that read history, and refuses the options that write a file or launch a program. It trusts the repository's own config, as git does, so it is for your own checkouts.

A single session digest typically touches 3–10 pages. This step needs a stronger model than distill; it runs in the user's session, so it uses whatever model the session uses — Brain sets no default.

### query

Read `index.md` → pick pages → read them → answer with citations (`[[page]]`, digest path, session id). The vault answers from its pages, falls back to grepping `sources/` only when the pages are silent and says so, and names what it does not know rather than filling gaps from general knowledge. If the answer is a synthesis worth keeping — a comparison, a timeline, a post-mortem — it is filed as a page and committed through `finish.sh --op query`, which also logs it; a plain factual answer leaves no trace.

### clip

`/brain:clip <url or pasted text>` fetches the content, asks the one question that matters — *why should the vault keep this?* — and writes `sources/refs/<date>-<slug>.md` through `scripts/ref.sh` (slug, frontmatter from `templates/ref.md`, secret gate). Nothing is summarized or filed into the wiki at this point; the ref is `ingested: false` and the next ingest integrates it like a digest, citing it as `(→ sources/refs/…)`.

### search

`/brain:query` is a skill, and a skill has to be triggered. Measured on 2026-10-15 across 40
real interactive sessions since 2026-10-08: 37 received the injected brief, a vault page was
opened in 4 of those 37, and the skill was invoked in 0 of the 40. In each of the four
sessions that did want vault content the agent reached for `sed -n` or `cat` on a page path
instead — it knew the vault was there and went round the one operation built to read it. So
the read side no longer waits to be triggered. `hooks/register.ts` is a function-hooks module
that registers a full-text search over the vault's five wiki directories as a tool, on
`session.start`, which puts it in the tool list every turn: one `grep -ric` per term, ranked by
BM25 over those counts, at most 8 pages back, each as `[[directory/page]]` with its lead
paragraph and three matching lines.

The ranking itself is `scripts/search.sh`, not the module; the registered tool runs it and
returns what it said. Two reasons, both of them scars. It was written in TypeScript first, and
a copy of it would have been a seventh entry on the list below of what two versions must agree
on — the class of defect that produced 0.6.11 twice in one week. And a ranking in the module
can only be tested through a mock of the module's `process.run`: the mock that stood in for
`grep` disagreed with it twice over — `grep -c` counts matching *lines* rather than
occurrences, and a term matches as a substring, which is how `do` scores a page named
`reconciler-double-count` — so the assertions it passed were about behaviour the search does
not have. `scripts/test-search-ranking.sh` now generates a 40-page vault and runs the real
script over it, with a frozen per-question baseline rank: the ranking had been changed three
times on measured evidence (0.6.5 name hits, 0.6.7 BM25, 0.6.10 the match count) and each of
those measurements was a hand-run against a real vault, so nothing in the repository could tell
whether the next change made retrieval worse. The fixture is not evidence that the ranking is
good — the corpus and questions are fabricated, so every gold page is gold by construction —
and three of its questions are expected misses kept there on purpose, because a fixture of
winnable questions is a floor that never trips. The third reason arrived later: a host without
this engine can run the script, which is what "Porting to another host" below now needs.

Ranking by the number of terms a page mentions at all was the first attempt and it does not
work, which only shows on an ordinary question. Measured on 2026-10-15 against a 202-page
vault: a question about who reaches one production database put 38 pages on the identical
score, and the same question asked as a sentence put 25 there, because a word like
`production` was on 138 of the 202. The tie fell through to the path, which sorts `topics/`
after `decisions/`, `me/`, `people/` and `projects/` — so with 137 of that vault's pages in
`topics/`, a tie wider than the cap returned eight alphabetically early pages and none of the
pages the question was about. Run live against the same vault, the old ranking returned
neither of the two pages that answer the questions the 120-run benchmark failed; BM25 returns
them second and first. BM25 is what the discarded frequency count is worth keeping for: a term
on most pages earns little, repetition counts with diminishing return, and dividing by page
length is what stops a long page that touches everything from winning on bulk — which was the
real objection to frequency, and is a length problem rather than a reason to throw the counts
away. A term in the page's own name counts as two mentions, since a page's name is what it is
about and its body never repeats it.

The tool resolves which vault to
search by running `scripts/resolve-vault.sh` rather than reimplementing routing in
TypeScript — a second copy of `lib.sh`'s `include`-glob precedence would drift, and a machine
with two vaults would otherwise be searched in whichever order the config happened to list
them. The tool reads; it never writes, so `finish.sh` is still the only write path. It does
not replace `/brain:query`, which also cites the digest and the session id and files a
synthesis as a page: the tool is what gets read when nobody asked for a vault lookup, and its
description says to read a page in full before stating facts about it, because the measured
failure on "why was this decided" questions was an agent answering from a page's summary.

Two things about the query are not about English. A question written in a script with no word
boundaries — Mandarin, Japanese, Thai — is one whitespace token, so it greps as one long literal
and matches nothing: `訂位超收是怎麼發生的？` returned zero candidates against a 190-page vault.
When the terms return **zero candidates**, and only then, the query's CJK runs are cut into
character bigrams, which is what Lucene's CJK analyser does. The trigger matters more than the
mechanism: triggering on "no rare identifier" instead was measured on 2026-10-18 to take a
question answered at rank 9 down to rank 43, because it fired on questions that were already
working. On the zero-candidate trigger the fallback fired on 3 of 7 real questions, changed
nothing that already had candidates, and moved three from absent to ranks 1, 8 and 4. The
bigrams are filtered at a fifth of the vault — unfiltered, thirteen fragments of Mandarin
function words outnumbered two English terms in one question and took it from rank 4 to 40 —
and that ceiling is on the bigrams alone, because applying it to the ASCII terms dropped
`production` and took the same question to absent, BM25's own idf being what already handles a
term everything carries.

And punctuation is a word boundary, which whitespace splitting does not know:
`現在誰連得到 production 的 billingdb？` lost `billingdb` entirely, because the full-width question
mark rode along and `billingdb？` is on no page — a question ending in the writer's own
punctuation threw away its most distinctive term. The tokeniser now replaces punctuation with
spaces by codepoint range, keeping `- _ . / :` because identifiers contain them, and the terms
reach grep as fixed strings rather than patterns.

What neither of those reaches is a question asked in words the page does not use — a plural it
writes in the singular, a paraphrase, the English name of something it records in Mandarin. That
is what a page's `aliases:` is for, and it is the one frontmatter field written for the search
rather than the reader. An alias is matched exactly as the page's name is, so it earns the same
two mentions and the same tie-break, and it composes with the bigram fallback rather than
competing: a Mandarin alias is what those bigrams land on. Measured against
`scripts/test-search-ranking.sh`, declaring two aliases took the fixture's two
vocabulary-mismatch questions from absent to rank 1 and its recall@8 from 0.786 to 0.929, which
is the whole of what those two questions were put there to measure. The cost is that an alias on
the wrong page is a wrong answer with a name hit behind it, so the schema asks for a short list
and never for a restatement of the name.

Neither is a localisation. Code identifiers are English in every country — `BILL-412`,
`CloudFront`, `endpoint` — so BM25 over identifiers is the globally right lane for this subject,
and what breaks is the tokeniser, for which the fix is a known one with a bounded trigger. One
consequence is worth recording because it cost an afternoon: **every `sort` and `uniq` in
`scripts/search.sh` runs under `LC_ALL=C`**. BSD sort under `en_US.UTF-8` gives CJK characters no
collation weight, so it reports 不出, 人工, 出去 and 簡訊 as equal and `uniq -c` folds the four
into one group of four — which silently turned the bigram fallback off, the folded group looking
like a term on four pages and being filtered out as too common. A deterministic rule written for
one script failing open and silent on another is the same shape as Zep's future-tense
normaliser, whose regexes for "will" and "plans to" match nothing in a Mandarin transcript.

A tool in the list is still a tool that has to be chosen, and measured across 56 sessions where
a vault lookup would have helped, it was invoked organically in 1. So the pages a question needs
can be pushed as well: `hooks/prompt-search.sh` runs on `UserPromptSubmit`, searches the prompt,
and returns `hookSpecificOutput.additionalContext`.

**`push_pages` is `false` by default, and that is the honest state of this feature.** The 1-in-56
figure is a reason to measure before pushing, not a reason to push: on every prompt past the gate
this spends up to 2000 characters, and a page that is merely plausible is worse than none because
the agent cannot tell the difference. Nothing in a transcript distinguishes an injection that
helped from one that was ignored or that misled, so the switch waits on the instrument that can —
the 120-run benchmark, which has not been re-run since 0.6.7 and is therefore the only honest next
step for the whole read side. `inject_brief` carries the same switch for the same reason, and its
default moved when a benchmark said what it was worth, not when it felt ready. Three things decide whether it says
anything, and each exists because the first version of it was wrong.

A **length gate** at 40 codepoints, applied to the prompt with its quoted spans removed.
Measured over 2,650 real interactive prompts since 2026-10-01, the share carrying at least one
term rare enough to rank anything runs 25% under 20 characters, 53% at 20–39, 69% at 40–79, 96%
at 80 and over — 88% at 40 and over. Under the gate a prompt is almost always a follow-up whose
subject is in the turn above, not in its own words. The count is `jq`'s, in codepoints:
`${#prompt}` counts bytes under a non-UTF-8 locale, which reads a 14-character Mandarin question
as 42 and fires on it.

Raw length was the whole gate until 2026-10-19, and replaying a real prompt corpus through the
hook showed what it misses. Of 824 prompts that cleared it, around a third of a 12-prompt sample
were not questions at all but the agent's own last output quoted back with a verdict after it —
the fabricated shape is `「 four caches that keep growing │ 33–36G │ waiting on you 」delete it` —
and they drew pages keyed on whatever the paste happened to contain rather than on a subject: a
page about how the user works, for a prompt whose own words were `delete it`. A paste clears a
length gate on its own bulk, and it clears the rare-term floor below as well, because pasted
output is the richest source of rare terms there is: file paths, byte sizes, ticket ids. This is
the same failure the rare-term floor was added for — a page that is merely plausible teaches the
reader that the vault is noise — arriving one level up, at the prompt rather than at the page.

So the gate strips quoted spans (`「」`, `“”`, `"`) before counting, and an opening delimiter the
prompt never closes runs to the end of it, because that is how a pasted block arrives: cut off
mid-table, closed with the wrong bracket, or not closed at all. On the same corpus, grown to
2,654 prompts by 2026-10-19, that gates 153 of the 824 — 18.5% — and four in five of those open
with the quote.

It is the stricter of two readings, and the cost was measured rather than assumed. Keeping short
quoted spans brings back about 30 of the 153, and most of those are real questions whose subject
sits inside the quote: `「the reconciler ran nine workers」why nine?`. But the same move lets
back in `「open a ticket before any infrastructure work?」yes`, which is the noise class exactly.
Nothing in the text separates the two except whether the remainder is a question or an assent,
which is a word list per language and it rots. The asymmetry decides it instead: a gated question
still has the registered tool and `/brain:query`, so what is lost is one unasked push, while a
merely plausible page pushed unasked costs the credibility of every push, because the agent
cannot tell which kind it received.

A **rare-term floor**, which is `--require-rare-term` in the script. Without it the hook answered
"how does the kafka consumer group rebalance itself on restart" — a subject the vault had never
held — with a page matching 1 of 8 terms, because `the` is on every page; and it listed the
answer followed by every other page carrying `the`, which teaches a reader that the vault is
noise. The floor drops both: a query with no term on a fifth or less of the vault injects
nothing, and a page that matched no such term is not listed. It applies only here. Filtering
*terms* this way was measured harmful on 2026-10-18 (it dropped `production` and took an
answering page from rank 9 to absent), and when somebody asks the tool directly a weak answer
beats silence, so the registered tool still returns whatever it finds.

A **budget ladder**, which is OpenViking's: the full form at 2000 characters, then page
addresses alone, then nothing. A result over budget is never truncated — a page quoted halfway
through reads as the whole of what the page says, and the agent cannot tell the difference.

The injected text is wrapped in `<brain-vault>` … `</brain-vault>`, and
`scripts/extract-transcript.sh` strips that region before anything reads the turn. This is not
tidiness. An injected block lands inside the user's turn, so distill would quote the vault's own
pages as the user's words and ingest would file the vault back into itself as a session source
— the loop 0.6.11 was released to close, arriving by a second door.

After a compaction the conversation keeps a summary of itself, and a summary of a vault page is
the one thing the read side exists to prevent — the measured failure on "why was this decided"
questions was an agent answering from a page's summary rather than the page. So when
`SessionStart` fires with `source=compact` (or `resume`, which loses the same thing),
`scripts/status.sh` names the pages the conversation already cited, as addresses to re-open. It
does not re-quote them: that would spend the context the compaction just reclaimed. A `clear` is
excluded, because the user asked for a fresh start.

This is the whole of what the host allows, and the first design was wrong about it. The plan was
agentmemory's pattern — re-inject on `PreCompact`, so the summariser itself sees the vault — but
Claude Code's `PreCompact` can only *block* a compaction, and discards `systemMessage` and
`continue`; `PostCompact` "can't affect the compaction result" either, and neither event appears
in the documented list of events that support `additionalContext`. `SessionStart` with
`source=compact` is the documented place, and the hook was already registered on that matcher,
so most of what was planned here had in fact been shipped since 0.4.0 without being written
down.

The session-start list is not a substitute for that tool, and a 120-run benchmark on
2026-10-15 shows why. Five of its six questions the vault arm answered well (mean 2.14
against 0.42, and one confidently wrong answer against nineteen); the sixth it answered no
better than the arm with no vault at all, because the one page holding the answer was not in
the injected list. The list is the top 20 pages by how many of this directory's digests cite
them, so a page that answers exactly one kind of question loses to pages many sessions feed,
and the arm fell back to grepping the repository — the failure the vault exists to prevent.
Raising the cap dilutes every other turn for one question's benefit, so the list keeps its
ranking and says what it is: the closing sentence names the search tool, where it used to name
`/brain:query`, a skill that is invoked in no measured session.

That sentence was then measured on the two questions it was written for, eight runs against the
same vault, and it works on one of them. Where the repository holds nothing on the subject, the
agent now reaches the page — in two of four runs, with an answer carrying both environments'
timestamps where every earlier run had answered "no record" — for about a tenth more cost and one
more tool call. Where the repository holds a plausible partial answer, it still does not: all
four runs read the workspace's own notes, answered from them, and never looked, because an agent
that has found something does not reach the clause about finding nothing.

Three more briefs were measured against that half on the same day, four runs each, and none of
them moved it. Naming `index.md` — the vault's own list of every page and its summary — as the
route to a page the injected list does not carry: no run opened it, and the question that the
plain brief had reached in two of three runs fell to none of four, its tool calls rising from
15-27 to 13-21, so an added sentence can cost what it does not buy. Telling the agent that when
a check turns out to be unavailable the vault's dated record is the answer to give rather than a
report that nothing could be checked: it did exactly that, and answered "from records, not a
live check" out of its own week-old note instead of the page checked against the live system
that day. Naming the answering page in the injected list, which cannot ship because the list is
built before the question exists, is the only arm that moved either question — and it moved the
hard one in one run of four.

What every transcript shows instead is a nearer store: the agent reads
`<transcript root>/<project>/memory/` first and stops, in all five arms and every run of that
question. So the open half is not a retrieval failure the brief can word its way out of, and
not the registered tool's absence from the list either — it is an agent's own notes outranking
a vault page that was checked more recently.

### memory-pointer

That is what `scripts/memory-pointer.sh` answers, and it is the one thing Brain writes outside
a vault. Ingest runs it for every memory snapshot whose facts it filed, and it replaces a
single region at the end of the live note — introduced by `<!-- brain:vault -->`, so a second
run replaces rather than appends — naming the page, the page's own `updated:` date and the
page's section headings. Measured against the same question on 2026-10-16, four runs each with
the shipped brief and nothing else changed: no pointer, 0 of 15 across five briefs; a pointer
saying only that the page holds "the current state of this subject", 1 of 4; a pointer that
also lists what the page covers, 6 of 8, with the answers naming the page and its date. The
difference between the last two is the whole mechanism — the note is read first either way, so
what decides is whether the agent can tell from the pointer that this question is that page's
subject, and section headings say that deterministically where a summary does not.

Writing into the agent's own memory directory is a deliberate reversal: `memory-sync.sh` used
to say that nothing is ever written back there. The cost is that a note is no longer purely the
agent's own, so three things are kept true. `memory-sync.sh` strips the marked region out of
the copy it writes, because a pointer that reached the vault would be a source saying a page
says something — Brain quoting itself as evidence. The pointer carries no claim of its own
beyond a path, a date and headings, so everything a reader might act on stays on the page where
it is dated and checkable. And the change-detection hash is of the note as it sits on disk,
pointer included, which `memory-pointer.sh` re-stamps when it writes.

That last one cost a day to learn. Hashing the stripped text is the tidier-looking choice and it
is wrong, because a session pins its plugin version for its whole life: a session on the version
that strips and a session on a version from before the pointer existed compute different hashes
for the same unchanged note, so each re-snapshots what the other has just written. Within hours
of 0.6.8 going in, one note had five snapshots in a day and two of them carried the pointer into
the vault — the exact leak the strip was written to prevent, arriving by the other side of the
same mechanism. The on-disk bytes are the one formula every version agrees on, which is the
general rule: state shared between versions has to be keyed on something no version is free to
reinterpret. The ingest skill also names the region as never-file, because snapshots written by
an older session already exist and `sources/` is append-only.


---

modes, a claim contradicted later in conversation:**

### correction capture

A claim the user contradicts in conversation used to survive it. Distillation preserves an
explicit correction as a `Correction: <wrong> → <correct>` bullet in the digest's `What
happened`, but that is one part of the defence and it depends on the correction
surviving summarization. A second hook in the same module records it where it happens: on
`prompt.submit`, a prompt that passes a local gate is classified with `$.model.classify`
together with the claim it answers — a bare contradiction is only a correction against what it
contradicts — and a prompt classified as a correction is written to `<vault>/.state/corrections/<date>-<time>-<session>.md`
with the date, the user's words verbatim and what the agent had just said. The file decides
nothing — it names no page, resolves no conflict and edits nothing, because `/brain:ingest` is
the only thing that files a fact and `finish.sh` the only write path into a vault — and it says
so in its own text, along with the instruction to run `restated.sh` before rewriting a page,
since a wrong claim is rarely written once. The user's words belong in the class ingest step 2
already treats as outranking every source. The classifier's labels are written out in the
module rather than tuned out of sight, and the second label exists for the expensive false
positive: "no, do the other one first" is an instruction about work, not a claim about the
world, and the pipeline must never be handed one as a correction. The hook runs on every
prompt, so the model call is gated locally first — at most 300 characters, the session idle,
and a last message that is the assistant's, at least 40 characters and not a question. That
costs recall in two places worth naming: a long correction that sets out what is actually true
with its evidence is missed, which is the most valuable kind, and so is a correction of
something said two or more turns back; both still reach ingest through the digest. Everything
written goes through `secret-gate.sh --redact` first, and the redacted text is also what
reaches the classifier, so a credential in a prompt neither lands on disk nor leaves the
machine; nothing is logged, for the same reason.

### lint

Weekly or on demand. Produces a report, not edits, unless told otherwise. `scripts/lint.sh` computes the mechanical rules (1, 2, 3, 5, 7, 8, 9 in the schema) in a couple of seconds; the skill adds the two that need judgment (4 and 6) and logs the run:

- contradictions recorded under `## Conflicts` that are still unresolved
- claims older than N days on pages marked `volatile: true`
- orphan pages (no inbound `[[links]]`)
- entities mentioned on ≥3 pages that have no page of their own
- drift between `brief.md` / wiki and the agent's built-in memory (`~/.claude/projects/*/memory/`)
- digests that were never ingested
- status markers that git no longer bears out

## Triggers

Distill and ingest are triggered differently because they are different kinds of work. Claude and Codex both implement these triggers; Codex hooks require explicit review and trust through `/hooks`.

| Op | Trigger | Why |
| --- | --- | --- |
| distill | `SessionEnd` hook, forks to the background | The payload names the transcript; no scanning. `SessionEnd` hooks get about 1.5 s, so the hook only spawns the runner and returns; output goes to `~/.brain/logs/distill.log`. |
| distill (catch-up) | `SessionStart` hook `brain-catchup`, `startup` only, forks to the background | Sessions that ended without a clean `SessionEnd` (closed terminal, crash, `claude -p` runs) are picked up the next time the user opens the agent; it looks at transcripts modified in the last 7 days, so a fresh install does not silently backfill years of history — that is `/brain:distill --all`. Together the two hooks give complete coverage with no scheduler. |
| status reminder | `SessionStart` hook `brain-status`, **sync**, `startup\|resume\|clear\|compact` | Reads the vault's files only, so it is fast, and returns `hookSpecificOutput.additionalContext` with one line naming every pending source — digests and refs alike — and any unresolved conflicts. |
| ingest | `/brain:ingest`, deliberate | Expensive, judgment-heavy, rewrites many pages. The user decides when to spend that, and sees the conflicts it raises. |
| ingest (backlog) | `SessionStart` hook `brain-auto-ingest`, `startup` only, forks to the background, **off by default** | Deliberate ingest alone leaves a tail. Measured on the first vault: of 319 digests, 181 of the 270 ingested landed within a day, but p90 was 102 h, the worst 265 h, and 49 were never ingested at all. Two sessions were found re-deriving an answer that was already sitting in an un-ingested digest — the case the wiki exists to prevent. `auto-ingest.sh` fires when the backlog crosses `min_pending` or holds anything older than `max_age_hours`, so the tail is bounded without an ingest on every quiet day. |
| query, lint | `/brain:query`, `/brain:lint` | Interactive by nature. |

Automatic ingest is opt-in through `auto_ingest.enabled`, because it spends model budget without being asked and rewrites `brief.md`, which every later session reads. Its thresholds (`min_pending`, `max_age_hours`, `min_interval_hours`, `model`) live beside it in `~/.brain/config.json`. It runs the ingest skill in a headless session whose tools are the skill's own `allowed-tools` — the four scripts and the file tools, no bare `Bash` — plus `git-read.sh` for checking status claims — so an unattended run cannot write through `git` and `finish.sh` stays the only write path. **It resolves no conflict at all**: nobody is there to decide, git settles only part of a conflict, and a wrong decision recorded unattended leaves no trace to find later, so contradictions stay `[open]` for the next human-driven run. Rewriting a status whose marker git no longer bears out is not a conflict decision: it is a newer dated fact, and the check that produced it is on the page.

Rejected: `Stop` hook (fires every turn); a scheduler such as launchd or cron (an extra install step per machine, and a laptop asleep at the scheduled hour misses the run — whereas a session start is exactly when the backlog is about to matter); cloud scheduled agents (cannot read local transcripts).

Two guards the hooks need:

- **Recursion.** The runner marks its inner summarizer with `BRAIN_INNER=1`. Claude runs without session persistence or settings; Codex runs `--ephemeral` with hooks disabled in a read-only temporary directory. Sessions whose `cwd` is the vault are skipped, so an ingest conversation is not itself a source.
- **Concurrency.** Several sessions and hosts can act at once. Distill takes an atomic lock around each write and an in-flight marker around each model call. Wiki-writing skills take a lease across their read, edit, and finish calls; a second host waits instead of updating a page from stale content. An interrupted run retains its lease so recovery is explicit and partial agent edits are not mistaken for human corrections.

## Relationship to built-in agent memory

Claude Code's auto-memory (`~/.claude/projects/<project>/memory/`) is a per-project hot cache written during the session, by the working model, usually with the code in front of it. Brain is the cross-project cold store written after the fact. They are complementary, and left unconnected they drift: on the first vault, a memory file settled a question on one day (which contributor a shared account belongs to, verified against the forge) and the next day's ingest opened it as a conflict, because the digest of the same session was a small-model summary and the vault never saw the memory. So memory is a source, upstream of the vault, not a parallel store:

- Memory stays authoritative for "things the agent must know in this repo right now". Nothing writes back into it: it is the agent's own notebook, and specific to Claude Code.
- `scripts/memory-sync.sh` snapshots every memory file whose content changed (git blob hash, kept in `.state/memory.json`) into `sources/memory/<date>-<name>.md`, verbatim, through the secret gate, with `ingested: false`. A project directory is routed the way a session is, by the cwd of its newest transcript. The sync runs after every distill and at the start of ingest prep, so memory reaches the wiki by the same pending path as digests and refs, cited `(→ sources/memory/<file>.md)`, and outranked by human edits like every other source. Memory files are the best-written sources the vault gets — deliberate, with a *why*, often verified in the session — so a memory snapshot is usually what settles a conflict a digest opened.
- The vault is authoritative for history, synthesis, and anything cross-project.
- `brief.md` is the bridge back: when `inject_brief` is `true` in `~/.brain/config.json`, the plugin's `SessionStart` hook adds the routed vault's brief to every session (it passes the secret gate first). The default is `false`: injection costs tokens on every session, and a wrong synthesized fact would reach every conversation until lint catches it — so the switch is flipped once the owner has read a few weeks of the wiki and trusts it. Resolving a round of conflicts by hand is that point. The same switch adds a **session map**: the wiki pages that the last 30 days of sessions in the current directory (or below it) fed, most cited first, capped at 20, each with its `index.md` line. The instruction that heads the map was measured, not assumed, and it has been wrong in both directions. Its first version said only "read the page before stating facts about what it covers", and agents did exactly that: they took a status from a page that had gone stale rather than checking git, and took a decision's reasons from a page's summary rather than opening the spec it cited. The second version said a page is a note and the system is the truth — and agents stopped opening the vault at all: across 60 runs, vault reads fell from 43 to 3, confidently wrong answers fell from 7 to 3, and the one question whose answer existed only in the vault was answered "there is no record", from a page that was sitting in the injected list and said otherwise. A vault nobody opens is a vault nobody maintains.

So the instruction now describes what a page is worth rather than whether to trust it. Status claims carry the date they were established and usually the check behind them (schema: "Status claims"), which makes them citable as they stand; re-deriving them is waste, and the exceptions are named — no date, no marker, a date older than a change the agent already knows about, or evidence in front of it that disagrees. It also names the categories where the wiki is the only source there is: whether something really ran in an environment, why a choice was made, what happened during an incident, and how work moved across repositories. Those are the questions an agent otherwise answers with "no record exists", because no repository holds them. The brief says who the user is; the map says which pages this session is likely to need. Without it nothing points a session at the wiki — measured on the first vault: 136 distills and 14 ingests, zero queries — because an agent does not query for a fact it does not know it lacks. `index.md` is not injected whole: at a hundred pages it is 24 KB.
- Lint checks brief and memory for contradictions; humans resolve them.

## Multi-device

If the vault is synced across machines with git, the local filesystem lease cannot coordinate between devices:

- Each machine distills **its own** transcripts into the corresponding host directory under `sources/sessions/`. These are new files or appends — they merge cleanly.
- **Ingest runs on one machine only.** Two machines rewriting `index.md`, `brief.md`, and entity pages will conflict daily. The `brain/last-ingest` tag therefore lives on that machine; human edits made elsewhere are seen once they are pushed.
- State files under `.state/` are per-machine and gitignored; distill discovers "what is new" from the vault's recursive `sources/sessions/` tree, not only from local state.

## What two versions must agree on

A session pins its plugin version for its whole life, so two sessions on different versions
write the same vault at the same time, and nothing in the plugin can stop the older one: its
whole write path is its own copy of these scripts. The only protection is that the things both
versions touch keep meaning the same thing. Measured across the twelve versions cached on one
machine on 2026-10-16, counting distinct implementations of each script: `write-lock.sh`,
`lib.sh` and `secret-gate.sh` have exactly one each, `index.sh` and `distill.sh` two,
`finish.sh`, `memory-sync.sh`, `provenance.sh` and `ingest-prep.sh` three, `status.sh` four.
So divergence is normal and the question is only what the divergent copies share.

Six things, and a change to any of them needs a new **name**, not a new meaning — an old
version cannot be taught, but it can be left looking at a key it does not recognise:

- **The lease.** `.state/lock` and its token, `write-lock.sh`, one implementation since 0.3.0.
  This is what makes concurrent versions safe at all. If it ever has to change, the lock's
  filename changes with it, or two versions will each believe they hold the same lock.
- **`.state/memory.json`.** Key: the note's absolute path. Value: `git hash-object` of the file
  **as it sits on disk**. Hashing anything derived from the file — the text with Brain's own
  pointer region stripped, say — is a different formula in each version that computes it, and
  the two then re-snapshot what the other wrote; see `memory-pointer`.
- **`.state/distilled.json`.** Key: the session id. `value.offset`: a byte count into that
  transcript. An offset that came to mean anything else would re-distill or skip whole sessions.
- **The source handshake.** `ingested: false` in a source's frontmatter is what makes it
  pending, and `memory:` / `project:` is how a snapshot names its origin. One version's distill
  writes these and another version's `ingest-prep.sh` reads them.
- **The generated files.** `index.md` and `brief.md` are rewritten by whichever version happens
  to run the next operation, so a format change does not migrate — it alternates, in committed
  history. The header line `<!-- generated by brain … -->` and the `(deprecated …)` prefix are
  already in that state: versions before 0.6.3 write neither.
- **`brain/last-ingest`.** Where this tag sits is the definition of "human edits since the last
  ingest". Moving it for any other reason silently changes what the next ingest is shown.

`secret-gate.sh` having one implementation across every version is luck rather than design, and
it is the one to keep: it is the only check standing between a transcript and a file on disk,
and a vault written by five versions is only as private as the weakest of them.

## Porting to another host

Brain has integrations for Claude Code and Codex. A new host supplies the same five bindings:

1. **Skills.** Bind the shared operational skills to the host's discovery path and command syntax. Preserve the writer-lease and finish-script rules.
2. **Schema.** Load `docs/schema.md` and the vault's shared `CLAUDE.md` through the host's instruction mechanism.
3. **Transcripts.** Convert the host's format to the metadata and timestamped conversation entries consumed by the distiller. Use a unique host key so session ids cannot collide.
4. **Trigger.** Wire the adapter to session start and end, with an explicit manual backfill operation.
5. **Retrieval.** Wire the host's per-prompt event to `hooks/prompt-search.sh`. Nothing is reimplemented: that script and `scripts/search.sh` beneath it are shell, shared by both hosts, so the length gate, the rare-term floor and the budget ladder stay at the values that were measured once. A host with no per-prompt event still gets the brief and the skills; what it loses is the answer to the 1-in-56 problem, which is the whole of the read side.

A native port packages exactly these: the host-specific files are `hooks/` and the extractor; everything else is shared. The fifth binding is why the ranking left the Claude Code hooks module — a TypeScript ranker could not have been the thing Codex runs, and two rankers would have drifted.

What a port cannot assume is that an event behaves the same way. Claude Code's `PreCompact` can block a compaction but cannot add anything to one, so the post-compaction page list goes on `SessionStart` with `source=compact`; a host without that distinction simply never emits it. On Codex, `hooks.json` registers three Brain commands and each must be *trusted* by the user before it runs at all — an untrusted hook is a silent no-op, which is the right failure but means an install is not finished when the installer exits.

## Why procedures are their own type

The first five page types are all things to *read*. A `procedures/` page is run, and that one
difference decides everything about its shape: a wrong `topics/` page misleads a reader who can
weigh it against what they know, while a wrong procedure gets executed by someone who came to it
precisely because they did not know.

So a procedure is written only from a session that carried it out, and records `Last run <date>`
against what — the same bar that keeps unverified status off a page, for the same reason. Its
steps come from the session's **tool calls, not its prose**: what a session said it did and what
it ran are different documents, and only one of them ran. That distinction is memU's two-slice
split, and its failure is worth copying too — memU embeds only a skill's `name: description`
line, so the body of its headline asset is the least retrievable thing it holds. Here the body
is what grep sees, and `aliases:` is what covers the words the page does not use.

The boundary that needs stating is against `topics/`. A topic holds why the process has the
shape it does — who owns the pipeline, what the schedule is, why a gate exists — and the
procedure holds only what to run. Split the other way, or duplicated, one of the two becomes the
stale copy, which for an executed page is the failure mode that matters. `examples/vault` shows
the pair: `topics/release-process` beside `procedures/deploy-acme-billing`, each pointing at the
other and neither repeating it.

One mechanical note, because it is the kind of thing that fails silently: `scripts/search.sh`
holds the searchable directories as a literal list, so a type added to the schema and forgotten
there is an entire directory the search cannot see, with no symptom but an answer that is not in
the results. `scripts/test-search-ranking.sh` puts one page in each default directory and
asserts all six come back.

## The rules a mechanism had to carry

Three of this pattern's rules are ones an agent negotiates with rather than forgets: that only a
human resolves a conflict, that the generated files are generated, and that `sources/` is
append-only. Each was prose in a skill, and prose is advice. `scripts/vault-hook.sh` is the
mechanism — a vault's `.git/hooks/pre-commit` refuses a commit that breaks one — and it is
Letta's precedent, a zero-dependency validator on the commit path, applied to the three
invariants whose breach leaves nothing behind.

Three details are the whole design, and two of them are corrections to the first version.

The hook in the vault is a **shim** that execs the plugin's copy, because `.git/hooks` is not
tracked: a validator copied in there would drift from the rules it enforces, which is the defect
it exists to prevent. The shim is **fail-open** — the path names a plugin version and
`claude plugin update` prunes the old one's directory, so a shim that insisted would have failed
every commit in the vault, `finish.sh`'s included.

`BRAIN_FINISH=1`, set by `finish.sh` and `init-vault.sh`, exempts **two of the three checks and
not the third**. A blanket exemption was the first version and it guarded nothing that mattered:
`finish.sh` is the only sanctioned write path, so an agent that resolves a conflict and then runs
it is the exact scenario the conflict rule exists for. The two it does exempt are things
`finish.sh` legitimately does — regenerate the generated files, flip a source's `ingested:` line
— and the first version of this blocked `init-vault.sh` creating a vault at all. A mechanism that
blocks the sanctioned write path is worse than none, because the first thing anyone does is take
it off; one that exempts it everywhere is decoration. `--no-verify` is left working for the same
family of reasons: the point is that skipping it is a decision rather than the default.

Run against a real 190-page vault on 2026-10-19, the conflict check named 9 of the 60 pages
carrying a `[resolved]` or `[unresolvable]` entry as citing no human decision anywhere on the
page.

What this does not reach is the Brain repository, whose invariants are different — fabricated
data only, two manifests agreeing, a skill under its line cap — and already mechanised in
`scripts/check.sh`. What that one still lacks is anything forcing `check.sh` to run.

## Non-goals

- Embedding search. `index.md` plus grep is enough at hundreds of pages; revisit only when it stops being enough.
- A UI. Obsidian or any markdown viewer works on the vault as-is.
- A scheduler. Hooks piggyback on actual usage; a day with no sessions needs no run.
- A second host before it has been tested end to end.

## Cost model

Distill: a few thousand tokens per session with a small model — negligible. Ingest: one agentic run over the pending digests whenever the user invokes it, reading a handful of pages — on the order of a few interactive turns. Lint: weekly-ish. The whole system costs less per day than one real conversation.
