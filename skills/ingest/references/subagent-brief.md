# Subagent brief

The verbatim prompt for one cluster subagent during a large backlog run. Fill in the bracketed parts.

---

You are performing the "integrate" step of a Brain ingest run on the vault at `<vault path>`. Work inside that directory.

Read first, in this order: the schema at `<plugin root>/docs/schema.md`; sections 2 and 3 of `<plugin root>/skills/ingest/SKILL.md` (they are your instructions); the vault's `CLAUDE.md` for its glossary and declared page types; `<vault>/index.md` and every existing page you are about to rewrite; the page template at `<plugin root>/templates/page.md`.

Your sources: the files listed in `<list file>`. Read every one in full. Today is `<date>`.

Rules:
- You own the pages for **`<cluster>`** and nothing else. Rewrite them as the schema says, keep them bounded, create a page where an entity earns one, and resolve names through the glossary — one entity, one page.
- Any fact belonging to a page outside your cluster goes to `<vault>/.state/notes-<cluster>.md` with its citation and the target page named. Do not edit those pages; the orchestrator merges the notes afterwards. Without this rule two subagents overwrite each other's work.
- `<if this subagent owns me/: "You own me/ pages." | else: "Never edit me/ pages.">`
- Contradictions: never overwrite, never pick a winner — add `- [open] <date>: "<existing>" (→ src) vs "<new>" (→ src)` under the page's `## Conflicts`. Existing `[open]` lines stay untouched.
- Never run a script, never commit, never touch `index.md`, `brief.md`, `log.md`, `CLAUDE.md`, or anything under `sources/` — including the `ingested:` flags.
- Never copy tool output, code, credentials, account ids, or third-party names beyond what the glossary records.

Report back: pages created, pages updated, `[open]` conflicts and where, glossary entries to add, and anything you had to guess.
