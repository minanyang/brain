---
title: Release process
type: topic
brief: false
volatile: true
locked: false
deprecated: false
updated: 2026-09-05
# generated — provenance.sh rewrites the two fields below from this page's own citations; hand edits are discarded
sources: [sources/sessions/2026-09-05-daily-deploys.md, sources/sessions/2026-08-20-reconciler-double-count.md, sources/sessions/2026-08-14-invoice-worker-retry.md]
sources_cited: 3
---

How [[projects/acme-billing]] gets to production. Deploys are gated by the pipeline that [[people/platform-team]] owns, and the schedule changed on 2026-09-01; the schedule itself is written down in the repository (→ ~/Repos/acme-billing/docs/release.md).

## Pipeline

- As of 2026-09-05, a smoke test runs the reconciler match step against staging before every deploy (verified 2026-09-05: ~/Repos/acme-billing 4e1a9c2 in origin/main) (→ sources/sessions/2026-09-05-daily-deploys.md).

## Schedule

- As of 2026-09-05, acme-billing deploys daily at 10:00 UTC, since 2026-09-01 (→ sources/sessions/2026-09-05-daily-deploys.md, ~/Repos/acme-billing/docs/release.md).
- Until 2026-09-01: Tuesday and Thursday after the 15:00 UTC standup (→ sources/sessions/2026-08-20-reconciler-double-count.md).

## Recovering a dropped invoice

- A job the worker cannot deliver goes to `invoices.dead` — see [[decisions/2026-08-14-invoice-worker-retries-with-backoff]]. The hand replay it replaced is kept at [[topics/manual-invoice-replay]], because logs from before 2026-08-14 still show jobs that were put through it (→ sources/sessions/2026-08-14-invoice-worker-retry.md).
- The checklist in the repository still ends with a manual reconciler run after each deploy (deprecated 2026-09-05: superseded by the pre-deploy smoke test above) (→ ~/Repos/acme-billing/docs/release.md).

## Conflicts
