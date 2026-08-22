---
name: clip
description: Save an article, web page, or pasted document into the vault as a ref (sources/refs/) so the next ingest can integrate it. Use when the user shares a link or text and wants it kept in their brain.
argument-hint: <url or "pasted"> [why it matters] [--vault <name>]
allowed-tools: Bash Read Write WebFetch
---

Turn `$ARGUMENTS` into a ref. A ref is an immutable copy of something the user handed over on purpose, plus one line from them on why it matters — that line is what tells ingest where the content belongs.

1. Find the vault: `"${CLAUDE_PLUGIN_ROOT}/scripts/resolve-vault.sh" [--vault <name>]` prints `name<TAB>path`.
2. Get the content.
   - A URL: fetch it with WebFetch using the prompt *"Return the main content of this page as Markdown, verbatim and complete — no summary, no commentary. Put the page title on the first line as a level-1 heading."* If the page is paywalled, empty, or the fetch returns a summary instead of the text, say so and ask the user to paste the text.
   - Pasted text: use it as is; the title is the first heading or the user's description.
3. If the user did not say why it matters, ask exactly one question: *why should the vault keep this — what should it inform?* One line is enough. Do not proceed without it.
4. Write the body to a temp file and run

   ```
   "${CLAUDE_PLUGIN_ROOT}/scripts/ref.sh" --vault <path> --url <url or pasted> --title "<title>" --why "<the user's line>" --body-file <temp file>
   ```

   It runs the secret gate and prints the path it wrote. If the gate blocks, show the user which line and ask whether to drop it.
5. Commit: `"${CLAUDE_PLUGIN_ROOT}/scripts/finish.sh" --vault <path> --op clip --note "<title>"`.
6. Report the path and remind the user that the ref is `ingested: false` until the next `/brain:ingest`.

Do not summarize or edit the content, and do not write wiki pages from here — that is ingest's job.
