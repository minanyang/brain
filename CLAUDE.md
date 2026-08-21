# Brain — maintainer notes

This repository is the public pattern and reference implementation. It must never contain anything derived from a real vault: every example, template, and test uses fabricated data (`acme-billing`, made-up session ids). Run a scan for personal or employer names before committing.

## Conventions

- Prose, code, file names, and commit messages are English.
- No roadmap, decision log, or status section in the repo. Rationale belongs inline in `docs/architecture.md`, next to the thing it explains. Plans and open questions stay in conversation.
- The README lists installation only for hosts that have been tested end to end. Other hosts get one sentence and a link to "Porting to another host".
- The five default page types (`me/ people/ projects/ decisions/ topics/`) are situation-neutral; anything implying a particular job or employer belongs in a vault's `CLAUDE.md` as a declared type, not here.
- Commit messages: conventional, single line, no trailers. Commit only when asked.

## Layout

```
docs/        architecture, schema, privacy, setup — the pattern
templates/   vault skeleton and page templates, copied by /brain init
skills/      /brain skills (Agent Skills standard), one directory each   (not yet)
hooks/       hooks.json plus the scripts it runs                           (not yet)
scripts/     deterministic parts: transcript extractor, distill runner, secret gate, state, lock (not yet)
.claude-plugin/  plugin.json and marketplace.json                          (not yet)
```

After touching either manifest, run `claude plugin validate . --strict`.

## Where the design lives

`docs/architecture.md` is authoritative. When a design change is agreed, update it and `docs/schema.md` in the same change; `README.md` and `docs/setup.md` describe, they do not decide.
