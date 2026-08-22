---
name: clip
description: Use when the user shares a link, article, or document and wants it kept — "clip this", "save this article", "bookmark this for my brain". Stores it as a ref for the next ingest.
argument-hint: <url or "pasted"> [why it matters] [--vault <name>]
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/resolve-vault.sh *) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/ref.sh *) Bash(${CLAUDE_PLUGIN_ROOT}/scripts/finish.sh *) Read Write WebFetch
---

Turn `$ARGUMENTS` into a ref. A ref is an immutable copy of something the user handed over on purpose, plus one line from them on why it matters — that line is what tells ingest where the content belongs.

1. Find the vault: `"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-vault.sh" [--vault <name>]` prints `name<TAB>path`.
2. Get the content.
   - A URL: fetch it with WebFetch using the prompt *"Return the main content of this page as Markdown, verbatim and complete — no summary, no commentary. Put the page title on the first line as a level-1 heading."* Check what came back is the article and not a digest of it — it should open with the title heading and end the way the page ends. If it is paywalled, empty, summarized, or truncated (WebFetch shortens long pages regardless of the prompt), say so and ask the user to paste the text.
   - Pasted text or a document that is not a web page: use it as is and pass its origin as `--url` — `file`, `meeting`, `email` (see `templates/ref.md`). The title is the first heading or the user's description; if there is neither, ask for one alongside the "why" question.
3. If the user did not say why it matters, ask exactly one question: *why should the vault keep this — what should it inform?* One line is enough. Do not proceed without it.
4. Write the body to a temp file and run

   ```
   "${CLAUDE_PLUGIN_ROOT}/scripts/ref.sh" --vault <path> --url <url or pasted> --title "<title>" --why "<the user's line>" --body-file <temp file>
   ```

   It runs the secret gate and prints the path it wrote. If the gate blocks, show the user the line it matched and ask whether to drop it; if they agree, remove that line from the temp file and run `ref.sh` again.
5. Commit: `"${CLAUDE_PLUGIN_ROOT}/scripts/finish.sh" --vault <path> --op clip --note "<title>"`.
6. Report the path and remind the user that the ref is `ingested: false` until the next `/brain:ingest`.

Do not summarize or edit the content, and do not write wiki pages from here — that is ingest's job. Never clip a link that merely came up in conversation: the session's own digest already cites it, and a ref is the record of something the user handed over on purpose.
