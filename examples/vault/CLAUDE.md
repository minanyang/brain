# Vault

This repository is a Brain vault: a private wiki about me and my work, maintained by you (the agent) from session digests and refs. The Brain plugin injects the current schema — layout, page types, frontmatter, digest template, index/log formats, lint rules — at session start. Overrides below win over it.

## Local overrides

Keep this section short; promote anything general upstream.

- (none yet)

## Page types

Beyond the defaults (`me/ people/ projects/ decisions/ topics/`), this vault also uses:

- (none yet — e.g. `company/` (type `company`): org units, processes, and internal systems of my employer)

## Source types

Beyond `sources/sessions/` and `sources/refs/`, ingest also reads:

- (none yet — e.g. `sources/journal/`: one file per day, written by me)

## Glossary

Names and acronyms the digests will mention that you should resolve consistently:

- `acme-billing`: the invoicing service, `~/Repos/acme-billing`. Not "billing", not "the billing repo".
- `reconciler`: the nightly job inside acme-billing that matches invoices to payments. Part of the project page, not its own page.
- Platform: the platform team ([[people/platform-team]]), never an individual.

## Workflow

- On every query, read `index.md` first, then drill into pages. Cite sources.
- Never pick a winner between contradicting claims — record both under `## Conflicts` and ask.
- Never hand-edit `brief.md`; change the source page.
- Before writing any file, apply the secret gate.
