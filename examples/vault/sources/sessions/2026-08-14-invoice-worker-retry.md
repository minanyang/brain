---
session: 7f3a1c2e-0b4d-4e8a-9c1f-2d5e6a7b8c9d
date: 2026-08-14
cwd: ~/Repos/acme-billing
branch: feat/invoice-retry
title: Add retry policy to invoice worker
ingested: true
---

## What happened
- Investigated why the invoice worker dropped jobs when the payments API timed out: it caught the error, logged it, and acked the message.
- Added a retry policy: 3 attempts with exponential backoff (1s, 4s, 16s), then the job goes to a dead-letter queue.
- Found that the worker was not idempotent — a retried job could create a duplicate invoice — and added an idempotency key derived from the order id.
- Wrote tests for the timeout path and the duplicate path; both pass.

## Decisions
- Retry 3× with backoff and dead-letter after that, rather than retrying forever — because an unbounded retry hid a real outage for two hours on 2026-08-12.

## Learned
- [me] wants a failing test written before the fix, and asked for it twice before the agent complied.
- [me] prefers small PRs; asked to split the idempotency change out of the retry PR.
- [project:acme-billing] the invoice worker consumes from the `invoices.pending` queue and calls the payments API synchronously.
- [project:acme-billing] the payments API has a 5s timeout and no rate-limit headers.
- [person:platform-team] owns the dead-letter queue configuration; a new queue needs a ticket to them.

## Open threads
- The dead-letter queue does not exist yet; ticket to platform team pending.
- Whether the reconciler needs the same retry policy.
