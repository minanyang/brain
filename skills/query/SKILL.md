---
name: query
description: Use when the user asks what the vault knows, why something was decided, when something happened, or any question their brain should answer from its own pages.
argument-hint: "<question> [--vault <name>]"
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/resolve-vault.sh *), Bash(${CLAUDE_PLUGIN_ROOT}/scripts/finish.sh *), Read, Write, Glob, Grep
---

Never edit an existing page from here, and never cite a page you have only seen in `index.md` — the index is one generated sentence per page, not the page. Ingest reads the wiki diff since the last run as human corrections that outrank every digest, so an edit made here would come back as a `(→ human)` claim nothing can override — the vault would be citing you as its own authority. Corrections go through the human editing the page, or through `/brain:ingest`.


Answer `$ARGUMENTS` from the vault, not from memory. The schema is injected at session start when you are inside a vault; if you are not, read `${CLAUDE_PLUGIN_ROOT}/docs/schema.md` first.

1. Find the vault: `"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-vault.sh" [--vault <name>]` prints `name<TAB>path`.
2. Read `<vault>/index.md` and pick the pages that can answer the question. Read those pages in full; follow `[[links]]` when a page points elsewhere. Only when the pages are silent, fall back to grepping `<vault>/sources/`.

   Two layers can answer and they are not equal, so every answer names the layer it came from. The wiki is synthesized and may be behind: check the page's `updated:` and give the date when it matters, and treat `volatile: true` as "verify before relying on this". `sources/` is verbatim but unintegrated — a digest claim is what one session recorded, not what the vault concluded. When they disagree, a `(→ human, date)` claim beats a digest claim, and a digest newer than the page's `updated:` means the page is behind: say that rather than silently preferring one.
3. Cite every claim: the page as `[[dir/page]]`, and the underlying source as the page cites it (`sources/sessions/<file>.md`); when the user needs to go back to the original conversation, the digest's `session:` frontmatter is the session id. Say what the vault does not know rather than filling gaps from general knowledge. If a page's `## Conflicts` bears on the answer, present both sides and say the conflict is unresolved.
4. If the answer is a synthesis worth keeping — a comparison, a timeline, a post-mortem, a how-to that spans several pages — file it: write a page under `topics/`, `decisions/` if it documents a decision, or any directory the vault's `CLAUDE.md` declares, from `${CLAUDE_PLUGIN_ROOT}/templates/page.md`, with `sources:` listing the digests the cited pages cite, then run

   ```
   "${CLAUDE_PLUGIN_ROOT}/scripts/finish.sh" --vault <path> --op query --add <the page you filed> --note "<question> → filed <dir/page>"
   ```

   which gates, regenerates `index.md` and `brief.md`, logs and commits. File only when the answer needed two or more pages and the question is one that will be asked again; when in doubt, answer and file nothing. A plain factual answer leaves no log entry. If finish reports open conflicts, mention them; do not resolve them here.

Never file a page you would not defend at the next ingest. Because `finish.sh` commits it as Brain's own commit, ingest excludes it from the human-edit diff and it is not laundered into a `(→ human)` claim — but from the next run on it is an ordinary page whose claims get cited and extended. A wrong synthesis filed today is a source of truth tomorrow.

If `resolve-vault.sh` exits non-zero there is no vault for this directory: say so and offer `--vault <name>`, rather than grepping the current repository instead. If the secret gate blocks a page you filed, `finish.sh` exits 1 and commits nothing — remove the line it names and run it again; never commit by hand.