# Brain — maintainer notes

This repository is the public pattern and reference implementation. It must never contain anything derived from a real vault: every example, template, and test uses fabricated data (`acme-billing`, made-up session ids). Run a scan for personal or employer names before committing.

## Conventions

- Prose, code, file names, and commit messages are English.
- No roadmap, decision log, or status section in the repo. Rationale belongs inline in `docs/architecture.md`, next to the thing it explains. Plans and open questions stay in conversation.
- The README lists installation only for hosts that have been tested end to end. Other hosts get one sentence and a link to "Porting to another host".
- The five default page types (`me/ people/ projects/ decisions/ topics/`) are situation-neutral; anything implying a particular job or employer belongs in a vault's `CLAUDE.md` as a declared type, not here.
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
skills/      /brain:* skills (Agent Skills standard), one directory each: init, distill, ingest, query, lint, clip
hooks/       hooks.json plus the three scripts it runs
scripts/     deterministic parts: lib.sh (config, routing, lock), extract-transcript, secret-gate, distill, init-vault, status, resolve-vault, ingest-prep, finish (shared by ingest/query/lint/clip), index, lint, ref
.claude-plugin/  plugin.json and marketplace.json
```

After touching either manifest, run `claude plugin validate . --strict`. To try the plugin from the working tree without installing it: `claude --plugin-dir ~/Repos/brain`. Scripts must stay bash 3.2-compatible (macOS default) and depend only on `jq` and `git`.

## Where the design lives

`docs/architecture.md` is authoritative. When a design change is agreed, update it and `docs/schema.md` in the same change; `README.md` and `docs/setup.md` describe, they do not decide.
