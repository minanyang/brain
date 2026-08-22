---
name: lint
description: Health report for a vault — stale conflicts, stale volatile pages, orphan pages, names without a page, digests never ingested, drift between the brief and Claude's built-in memory, lost human claims. Use weekly or when the user asks whether the wiki is healthy.
argument-hint: [--vault <name>] [--fix]
allowed-tools: Bash Read Glob Grep
---

Produce a report. Do not edit anything unless the user passed `--fix` or asks for a specific fix afterwards.

1. Find the vault: `"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-vault.sh" [--vault <name>]` prints `name<TAB>path`.
2. Run the deterministic rules: `"${CLAUDE_PLUGIN_ROOT}/scripts/lint.sh" <path>`. Its output is self-labelled (rules 1, 2, 3, 5, 7) and ends with the inputs for the two judgment rules. If it reports `(no ingest history yet)` for rule 7, say so rather than treating it as a pass.
3. Rule 4 — names on three or more pages with no page of their own: from the page list in the report, grep the wiki directories for recurring proper nouns (people, teams, services, repositories, tools) that appear on at least three pages and have no page. A name counts as having a page when it matches a page's file name, its `title:`, or an alias in the vault's `CLAUDE.md` glossary — read the glossary first, because it also records the names that deliberately have no page. Report each remaining name with the pages it appears on. Skip generic words, tool names already covered by a topic page, and digest tags.
4. Rule 6 — drift between `brief.md` and Claude's built-in memory: read each memory file listed in the report and compare it with the brief. A contradiction is the same subject with incompatible claims — a different owner, status, date or preference for the same thing. A fact present on one side only is not a contradiction, and neither is different phrasing. Note that the memory listing spans every project on this machine, including ones that route to another vault.
5. Print the combined report: the script output, then your rule 4 and rule 6 findings, then one line with the total, script findings plus your own. Keep each finding to one line with the file it concerns.
6. Record the run: `"${CLAUDE_PLUGIN_ROOT}/scripts/finish.sh" --vault <path> --op lint --note "<N> findings"`. With `--fix`, edit only what has one obviously correct outcome: an orphan page an existing page plainly should link to, or a rule 7 claim restored verbatim with `git show 'brain/last-ingest^:<page>'`. Never bump a stale `updated:` date — the staleness *is* the finding, and moving the date hides it without re-verifying anything. Conflicts are never fixed here: they are the human's call through `/brain:ingest`. Say what you changed.
