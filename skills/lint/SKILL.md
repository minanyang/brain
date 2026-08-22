---
name: lint
description: Health report for a vault — stale conflicts, stale volatile pages, orphan pages, names without a page, digests never ingested, drift between the brief and Claude's built-in memory, lost human claims. Use weekly or when the user asks whether the wiki is healthy.
argument-hint: [--vault <name>] [--fix]
allowed-tools: Bash Read Glob Grep
---

Produce a report. Do not edit anything unless the user passed `--fix` or asks for a specific fix afterwards.

1. Find the vault: `"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-vault.sh" [--vault <name>]` prints `name<TAB>path`.
2. Run the deterministic rules: `"${CLAUDE_PLUGIN_ROOT}/scripts/lint.sh" <path>`. It reports rules 1 (open conflicts older than 14 days), 2 (volatile pages older than 30 days), 3 (pages with no inbound links), 5 (sources not ingested after 2 days) and 7 (human claims lost by the last ingest), and ends with the inputs for the two judgment rules.
3. Rule 4 — names on three or more pages with no page of their own: from the page list in the report, grep the wiki directories for recurring proper nouns (people, teams, services, repositories, tools) that appear on at least three pages and have no page. Report each with the pages it appears on. Skip generic words and tags.
4. Rule 6 — drift between `brief.md` and Claude's built-in memory: read each memory file listed in the report and compare it with the brief. Report every pair of statements that contradict each other (name, date, preference, status). Do not report facts that are merely absent from one side.
5. Print the combined report: the script output, then your rule 4 and rule 6 findings, then one line with the total. Keep each finding to one line with the file it concerns.
6. Record the run: `"${CLAUDE_PLUGIN_ROOT}/scripts/finish.sh" --vault <path> --op lint --note "<N> findings"`. With `--fix` and only for findings that have an unambiguous fix (an orphan that an obvious page should link to, a stale `updated:` date), make the edit first and say what you changed; conflicts are never fixed here — they are decided by the human through `/brain:ingest`.
