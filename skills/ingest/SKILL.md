---
name: ingest
description: Integrate pending session digests and refs into the vault's wiki pages. Use when the user asks to ingest, update the wiki, or process pending digests; the SessionStart reminder names how many are waiting.
argument-hint: [--vault <name>] [--batch N]
allowed-tools: Bash Read Write Edit Glob Grep
---

Integrate pending sources into the wiki, one batch at a time, committing after each batch. The schema is injected at session start when you are inside a vault; if you are not, read `${CLAUDE_PLUGIN_ROOT}/docs/schema.md` first.

## 1. Prepare

```
"${CLAUDE_PLUGIN_ROOT}/scripts/ingest-prep.sh" $ARGUMENTS
```

Read the whole report. It gives you the vault path, the page types (defaults plus those the vault's `CLAUDE.md` declares), human edits since the last ingest, the batch of pending sources, and the current index. Also read the vault's `CLAUDE.md` for its glossary and local overrides. If nothing is pending and there are no human edits, say so and stop.

## 2. Human edits outrank everything

Every hunk under "Human edits" is a correction or addition by the human. When you rewrite a page that carries one, keep the claim, cite it `(→ human, <today>)`, and never let a source below override it. A source that contradicts a human claim goes under `## Conflicts`.

## 3. Integrate the batch

Read each pending source in full. For each fact worth keeping:

- Decide the page type — `me`, `person`, `project`, `decision`, `topic`, or a declared type. Never invent a type; an unclassifiable fact goes to `topics/`.
- Find the page in the index (resolve names through the glossary; one entity, one page — do not create `projects/acme` next to `projects/Acme`). Create the page from `${CLAUDE_PLUGIN_ROOT}/templates/page.md` if it does not exist. File names: lowercase, hyphenated, no dates except in `decisions/`.
- Rewrite the page, do not append: lead with a two-sentence summary, then headed sections. Cite every non-obvious claim inline `(→ sources/sessions/<file>.md)`. Link related pages with `[[dir/page]]`. Absolute dates only. Update `updated:` and `sources:` in the frontmatter.
- A fact that contradicts an existing claim is **not** applied. Record both under `## Conflicts` as `- [open] <today>: "<existing>" (→ its source) vs "<new>" (→ new source)` and leave the body as it was. Never pick a winner.
- Pages with `locked: true`: only `## Conflicts` may change.
- Promote to `decisions/` only what has consequences beyond one session; small choices stay as a line on the project page. Set `brief: true` on the handful of pages a new session should always see (the user's working style, the main projects); keep that set small.
- Do not copy tool output, code, or credentials from a digest into a page. State the fact.

Write the list of sources you integrated, one path per line, to a temp file.

## 4. Finish the batch

```
"${CLAUDE_PLUGIN_ROOT}/scripts/ingest-finish.sh" --vault <path> --sources <temp file> --note "<one line: what this batch covered>"
```

It runs the secret gate, marks the sources ingested, regenerates `index.md` and `brief.md`, appends to `log.md`, commits, and moves the `brain/last-ingest` tag. If the gate blocks, fix the page it names and run it again. Do not write `index.md` or `brief.md` yourself.

## 5. Next batch or stop

If the report said more sources are waiting, run steps 1–4 again. Stop when nothing is pending, or when the user asks to stop. A batch is small on purpose so that progress is committed and the run can resume later.

## 6. Large backlog (first ingest after a backfill)

When more than ~40 sources are pending, do not read them all into this context. Run `ingest-prep.sh --by-cwd` to see the pending sources grouped by the working directory they came from, then:

- Clusters that come from different working directories rarely touch the same pages; integrate them in parallel, one subagent per cluster. Give each subagent this skill's section 3 verbatim, its file list, the vault path, and an ownership rule: it may only create or edit pages for entities in its own cluster, must not edit `me/` pages, and writes every `[me]` fact and every fact that belongs to another cluster's page to `.state/notes-<cluster>.md` with citations.
- The dominant cluster (usually one project with most of the sessions) is integrated serially in batches of ~25, one subagent per batch, each started fresh so it reads the pages as the previous batch left them. That cluster's subagents own `me/` pages.
- Subagents never run `ingest-finish.sh`, never commit, and never touch `index.md`, `brief.md`, `log.md`, `CLAUDE.md` or the sources.
- After each subagent returns, merge its `.state/notes-*.md` into the pages they name, then run step 4 for that subagent's sources. Conflicts are asked about once at the very end.

## 7. Ask about conflicts

When you stop, list every `[open]` conflict the run recorded (finish prints them) and ask the human to decide each one, or leave it. For a decision: put the winning claim in the page body cited `(→ human, <today>)`, change the entry to `- [resolved <today>] …`, then commit with `git -C <vault> commit -am "ingest: resolve conflict on <page>"`.

Report at the end: sources ingested, pages created and updated, conflicts open, and anything the glossary should learn (names you had to guess at).
