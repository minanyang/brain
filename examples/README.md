# Examples

`vault/` is what a Brain vault looks like after a month of use, so you can see the output before installing anything. Everything in it is fabricated — a made-up service called `acme-billing`, made-up people, made-up session ids — and it was written by hand to the schema in [docs/schema.md](../docs/schema.md), not distilled from a real vault.

Read it in this order:

1. [`vault/brief.md`](vault/brief.md) — the lines injected into every new session. Two pages, because only two carry `brief: true`.
2. [`vault/index.md`](vault/index.md) — one line per page, generated from the pages by `scripts/index.sh`.
3. [`vault/projects/acme-billing.md`](vault/projects/acme-billing.md) — a page: summary, sections, every claim citing its source inline.
4. [`vault/topics/release-process.md`](vault/topics/release-process.md) — an open conflict: two digests disagree about the deploy schedule, and the agent recorded both instead of picking.
5. [`vault/people/platform-team.md`](vault/people/platform-team.md) — claims cited `(→ human, …)` are hand edits, which ingest may not overwrite.
6. [`vault/projects/acme-billing.md`](vault/projects/acme-billing.md) again, at its last three sections — an open thread and one closed by a later digest, and under `## Rejected` an idea the user turned down, with the evidence that killed it so it is not proposed again.
7. [`vault/topics/manual-invoice-replay.md`](vault/topics/manual-invoice-replay.md) — a page superseded but kept: `deprecated:` says what replaced it and when, `index.md` marks it, and `brief.md` leaves it out.
8. [`vault/sources/`](vault/sources/) — what the pages were compiled from: three session digests (one resumed and continued), a ref, and a snapshot of a built-in memory file.

`vault/.state/` is absent because it is per-machine and gitignored. `scripts/lint.sh examples/vault` reports rules 1, 2, 7 and 9 against it, all for the same reason: the example dates are fixed, so its conflicts and volatile pages read as old and its markers name a repository that does not exist on your machine, while rule 7 needs git history the example has none of. None of it is a defect in the example.
