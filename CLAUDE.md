# Brain — maintainer notes

This repository is the public pattern and reference implementation. It must never contain anything derived from a real vault: every example, template, and test uses fabricated data (`acme-billing`, made-up session ids). Run a scan for personal or employer names before committing.

## Conventions

- Prose, code, file names, and commit messages are English.
- No roadmap, decision log, or status section in the repo. Rationale belongs inline in `docs/architecture.md`, next to the thing it explains. Plans and open questions stay in conversation.
- The README lists installation only for hosts that have been tested end to end. Other hosts get one sentence and a link to "Porting to another host".
- The six default page types (`me/ people/ projects/ decisions/ topics/ procedures/`) are situation-neutral; anything implying a particular job or employer belongs in a vault's `CLAUDE.md` as a declared type, not here.
- Commit messages: conventional, single line, no trailers. Commit only when asked.

## Writing a skill

- `description` states **what the skill does and when to use it**, and where the agent could plausibly do the job by hand, says why it should not. Measured, not assumed: a description that gave only the trigger ("Use when the user asks to ingest…") did not fire at all — the agent read the vault's files itself instead — while the same skill fired reliably once the description named the operation and its stakes. Anthropic's own skills follow the same shape and its guidance calls for being "a little bit pushy". Do not summarize the step sequence, though: that gets followed in place of the body.
- Frontmatter carries only what is needed: `name`, `description`, `argument-hint` when it takes arguments, `allowed-tools` scoped to the exact scripts it runs (`Bash(${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh *)`, never bare `Bash`), and `disable-model-invocation: true` for an operation the hooks already perform or that is expensive to start by accident.
- The body is imperative, names each script with its exact invocation and what it prints, and never restates `docs/schema.md` — the schema is injected at session start inside a vault and referenced by path outside one.
- Every prohibition carries its reason in the same sentence, and sits where the agent is about to break it, not at the end. Where the agent will negotiate with a rule rather than forget it (conflicts, human edits), add a two-column table of the excuse and why it is wrong.
- A skill stays under ~100 lines. Anything longer that is needed on a rare branch (a subagent brief, a migration recipe) goes in `skills/<name>/references/<file>.md`, loaded from the step that needs it and marked "Do NOT load" otherwise.
- Run `./scripts/check.sh` before committing.

## Layout

```
docs/        architecture, schema, privacy, setup — the pattern
templates/   vault skeleton and page templates, copied by /brain:init
examples/    a fabricated vault (acme-billing) showing a month of output; hand-written to docs/schema.md, keep it in step with schema changes
skills/      /brain:* skills (Agent Skills standard), one directory each: init, distill, ingest, query, lint, clip
hooks/       hooks.json, register.ts (the hooks module), and the command-hook scripts it runs — including prompt-search.sh, which pushes the pages a question needs on UserPromptSubmit
scripts/     deterministic parts: lib.sh (config, routing, lock), extract-transcript, secret-gate, distill, memory-sync, init-vault, status, resolve-vault, ingest-prep, finish (shared by ingest/query/lint/clip), index, lint, ref, verify (status markers vs git), git-read (read-only git for agents), restated (every page repeating a claim), restore-page (bring a deleted page back from git), memory-pointer (point a memory note at the vault page that now holds its subject — the one write outside a vault), search (the only BM25 implementation: both the registered tool and the prompt hook run it, so a second copy cannot drift and a host without the TypeScript engine can still retrieve)
.claude-plugin/  plugin.json and marketplace.json
```

After touching either manifest, run `./scripts/check.sh` — `claude plugin validate . --strict` alone reads marketplace.json and misses whole classes of plugin.json warning, so check.sh validates both paths. To try the plugin from the working tree without installing it: `claude --plugin-dir ~/Repos/brain`. Scripts must stay bash 3.2-compatible (macOS default) and depend only on `jq` and `git`.

## Releasing

Do not bump the version. Commits accumulate under the current number, and a release is a separate thing the maintainer asks for: one commit that bumps both manifests, then a push and a tag. The version is the unit of delivery, not of change. Bumping per change mints releases nobody ran, which is what `v0.6.12` through `v0.6.24` are — fourteen numbers tagged in one session, not one of them ever installed, and the installed copy sat at `0.6.11` the whole time, so every bump bought nothing.

The bump does matter when it happens, and this is the whole of what it is for: `claude plugin update` compares versions, so pushing new code under the old number reports "already at the latest version" and installs nothing. Between releases the pushed tree is therefore ahead of every installed copy. That is expected, and `claude --plugin-dir ~/Repos/brain` runs the working tree without installing it — it is not a reason to bump.

## Where the design lives

`docs/architecture.md` is authoritative. When a design change is agreed, update it and `docs/schema.md` in the same change; `README.md` and `docs/setup.md` describe, they do not decide.
