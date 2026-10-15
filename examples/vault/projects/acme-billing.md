---
title: acme-billing
type: project
brief: true
volatile: false
locked: false
deprecated: false
updated: 2026-09-05
# generated — provenance.sh rewrites the two fields below from this page's own citations; hand edits are discarded
sources: [sources/sessions/2026-09-05-daily-deploys.md, sources/memory/2026-08-22-reconciler-retry-policy.md, sources/sessions/2026-08-20-reconciler-double-count.md, sources/refs/2026-08-15-idempotent-workers.md, sources/sessions/2026-08-14-invoice-worker-retry.md]
sources_cited: 5
---

acme-billing (`~/Repos/acme-billing`) is the invoicing service: an invoice worker that consumes `invoices.pending` and calls the payments API, plus a nightly reconciler that matches invoices to payments. Most of the user's sessions happen here; the reconciler is the job most often paged on.

## Invoice worker

- Consumes from `invoices.pending` and calls the payments API synchronously; the API has a 5s timeout and no rate-limit headers (→ sources/sessions/2026-08-14-invoice-worker-retry.md).
- Retries 3× with exponential backoff, then dead-letters to `invoices.dead` — see [[decisions/2026-08-14-invoice-worker-retries-with-backoff]]. Idempotent since the same day, keyed on the order id (→ sources/sessions/2026-08-14-invoice-worker-retry.md, sources/refs/2026-08-15-idempotent-workers.md).
- The dead-letter queue had received zero messages as of 2026-09-05 (→ sources/sessions/2026-09-05-daily-deploys.md).

## Reconciler

- Runs nightly at 02:00 UTC (→ sources/sessions/2026-08-20-reconciler-double-count.md)
- Two steps since 2026-08-21, match then report; the report step reads only the match output table (→ sources/sessions/2026-08-20-reconciler-double-count.md).
- Must not get the invoice worker's retry policy: it is a batch job re-run whole the next night (→ sources/memory/2026-08-22-reconciler-retry-policy.md).
- A same-day refund was counted as both paid and refunded until 2026-08-20; fixed by filtering on `status` (→ sources/sessions/2026-08-20-reconciler-double-count.md).

## People

- [[people/priya-nair]] reviews most PRs. [[people/platform-team]] owns the queues and the deploy calendar. How the user works on it: [[me/working-style]].

## Open threads

- [thread 2026-09-05] whether the reconciler should run right after the daily deploy — waiting on [[people/platform-team]], who own the deploy calendar (→ sources/sessions/2026-09-05-daily-deploys.md).
- [closed 2026-09-05] whether the `invoices.dead` queue had been created — [[people/platform-team]] created it on 2026-08-27 and it had taken zero messages by 2026-09-05 (→ sources/sessions/2026-09-05-daily-deploys.md).

## Rejected

- [rejected 2026-08-22] giving the nightly reconciler the invoice worker's retry policy — the user turned it down when the agent proposed copying it across: the reconciler is a batch job re-run whole the next night, so per-row retries with backoff would only make a bad night slower (→ sources/memory/2026-08-22-reconciler-retry-policy.md).

## Conflicts
- [open] 2026-09-05: "the reconciler runs nightly at 02:00 UTC" (→ sources/sessions/2026-08-20-reconciler-double-count.md) vs "the nightly reconciler runs at 03:00 UTC, after the backup window" (→ sources/sessions/2026-09-05-daily-deploys.md)
