---
name: ingest
description: Use when the user asks to ingest, to integrate pending digests or refs, or to update the wiki — and when the session-start reminder says sources are pending.
argument-hint: [--vault <name>] [--batch N]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/ingest-prep.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/finish.sh *), Read, Write, Edit, Glob, Grep, Task, Agent
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

  | The excuse you will reach for | Why it is wrong |
  | --- | --- |
  | "The newer source is obviously right" | Recency is not authority. Both go under `## Conflicts`. |
  | "This is a clarification, not a contradiction" | If the existing claim would have to change, it is a contradiction. |
  | "Nobody will care about this small difference" | The human decides that, not you. A conflict costs one line; a silent overwrite costs the claim. |

- Promote to `decisions/` only what has consequences beyond one session; small choices stay as a line on the project page. Set `brief: true` on the handful of pages a new session should always see (the user's working style, the main projects); keep that set small.
- Keep the page bounded. A rewrite folds superseded detail into the current-state section and leaves one line per dated event — the old wording is in git, not on the page. When a section stops being about one thing, split it into its own `topics/` page and link it.
- A ref is not a digest. Its `why:` line is the human's routing opinion and tells you which page the body belongs to; the body is an external source, cited `(→ sources/refs/<file>.md)` and never written up as the user's own view or decision.
- Do not copy tool output, code, or credentials from a digest into a page. State the fact.

Write the list of sources you integrated, one path per line, to a temp file.

## 4. Finish the batch

```
"${CLAUDE_PLUGIN_ROOT}/scripts/finish.sh" --vault <path> --op ingest --sources <temp file> --note "<one line: what this batch covered>"
```

It runs the secret gate, marks the sources ingested, regenerates `index.md` and `brief.md`, appends to `log.md`, commits, and moves the `brain/last-ingest` tag. If the gate blocks, fix the page it names and run it again. Do not write `index.md` or `brief.md` yourself.

## 5. Next batch or stop

If the report said more sources are waiting, run steps 1–4 again. Stop when nothing is pending, or when the user asks to stop. A batch is small on purpose so that progress is committed and the run can resume later.

## 6. Large backlog (first ingest after a backfill)

When more than ~40 sources are pending, do not read them all into this context. Run `ingest-prep.sh --by-cwd` to see the pending sources grouped by the working directory they came from, then:

- Clusters that come from different working directories rarely touch the same pages; integrate them in parallel, one subagent per cluster, each briefed from `references/subagent-brief.md` with its own file list and the human-edit hunks that touch its pages.
- The dominant cluster (usually one project with most of the sessions) is integrated serially in batches of ~25, one subagent per batch, each started fresh so it reads the pages as the previous batch left them. That cluster's subagents own `me/` pages.
- Size a batch so the subagent never compacts — about 25 sources. A batch that hits compaction loses the pages it read first and writes worse than two smaller batches would. Ingest also rewards a stronger model than distill: splitting an overgrown page and noticing a file missing from its own list are things weaker models skip, so on a weaker model halve the batch and check the returned file list against the one you gave it.
- **Load `references/subagent-brief.md`** for the prompt each cluster subagent gets. Do NOT load it for an ordinary batch.
- Subagents never run `finish.sh`, never commit, and never touch `index.md`, `brief.md`, `log.md`, `CLAUDE.md` or the sources.
- After each subagent returns, merge its `.state/notes-*.md` into the pages they name, then run step 4 for that subagent's sources. Conflicts are asked about once at the very end.

## 7. Ask about conflicts

When you stop, list every `[open]` conflict the run recorded (finish prints them).

Resolve what you can before asking. About half of accumulated conflicts are questions of fact rather than judgment — the repository, `git log`, the forge or the cloud console settles them. Verify those, write the winner into the page cited `(→ human, <today>, verified against <what you checked>)`, mark the entry `[resolved <today>] … — decided: <clause>`, and ask the human only where both claims stay defensible. A first ingest that hands over twenty-five questions gets no answer at all.

For the rest, ask the human to decide each one, or leave it. For a decision: put the winning claim in the page body cited `(→ human, <today>)`, change the entry to `- [resolved <today>] …`, then commit with `git -C <vault> commit -am "ingest: resolve conflict on <page>"`.

Report at the end: sources ingested, pages created and updated, conflicts open, and anything the glossary should learn (names you had to guess at).

## Never

- **Never `git commit` in the vault.** `finish.sh` is the only sanctioned write path: secret gate on every changed page, sources marked ingested, `index.md` and `brief.md` regenerated, log appended, commit, `brain/last-ingest` moved. A raw commit skips all of it, and the next run re-ingests the same sources.
- **Never write `index.md` or `brief.md`.** They are generated from the pages; what you type is overwritten and the drift is invisible until someone reads a stale brief.
- **Never pick a winner between two claims.** The losing claim leaves no trace, so a wrong silent merge cannot be found later.
- **Never treat your own writing as a human edit.** Prep already excludes Brain's own commits from the human-edit diff; do not go looking for edits elsewhere in git and do not re-file your own prose as a correction.
- **Never split one entity across two pages** (`projects/acme` beside `projects/Acme`) — nothing downstream merges them.
