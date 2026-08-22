---
name: query
description: Answer a question from the vault's wiki with citations back to pages, digests and session ids; file answers worth keeping as new pages. Use when the user asks what the vault knows, why something was decided, or what happened when.
argument-hint: <question> [--vault <name>]
allowed-tools: Bash Read Write Glob Grep
---

Answer `$ARGUMENTS` from the vault, not from memory. The schema is injected at session start when you are inside a vault; if you are not, read `${CLAUDE_PLUGIN_ROOT}/docs/schema.md` first.

1. Find the vault: `"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-vault.sh" [--vault <name>]` prints `name<TAB>path`.
2. Read `<vault>/index.md` and pick the pages that can answer the question. Read those pages in full; follow `[[links]]` when a page points elsewhere. Only when the pages are silent, fall back to grepping `<vault>/sources/` — and say that the answer comes from a raw digest, not from the wiki.
3. Answer concisely, in the user's language. Cite every claim: the page as `[[dir/page]]`, and the underlying source as the page cites it (`sources/sessions/<file>.md`); when the user needs to go back to the original conversation, the digest's `session:` frontmatter is the session id. Say what the vault does not know rather than filling gaps from general knowledge. If a page's `## Conflicts` bears on the answer, present both sides and say the conflict is unresolved.
4. If the answer is a synthesis worth keeping — a comparison, a timeline, a post-mortem, a how-to that spans several pages — file it: write a page under `topics/` (or `decisions/` if it documents a decision) from `${CLAUDE_PLUGIN_ROOT}/templates/page.md`, with `sources:` listing the digests the cited pages cite, then run

   ```
   "${CLAUDE_PLUGIN_ROOT}/scripts/finish.sh" --vault <path> --op query --note "<question> → filed <dir/page>"
   ```

   which gates, regenerates `index.md` and `brief.md`, logs and commits. A plain factual answer is not filed and leaves no log entry.

Never edit existing pages from here — corrections go through the human editing the page (ingest picks them up) or through `/brain:ingest`.
