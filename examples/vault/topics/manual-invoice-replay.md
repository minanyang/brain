---
title: Manual invoice replay
type: topic
brief: false
volatile: false
locked: false
deprecated: 2026-09-05 — superseded by [[decisions/2026-08-14-invoice-worker-retries-with-backoff]]
updated: 2026-09-05
# generated — provenance.sh rewrites the two fields below from this page's own citations; hand edits are discarded
sources: [sources/sessions/2026-09-05-daily-deploys.md, sources/sessions/2026-08-14-invoice-worker-retry.md]
sources_cited: 2
---

How an invoice the worker had dropped was replayed by hand, which was the only recovery path until 2026-08-14. Kept rather than deleted because logs and tickets from before then still refer to it; it is not the procedure to follow, and [[topics/release-process]] has the one that is.

## The procedure, until 2026-08-14

- The worker caught a payments API timeout, logged it and acked the message, so the job was dropped with nothing left to retry it (→ sources/sessions/2026-08-14-invoice-worker-retry.md).
- A dropped invoice was found by grepping the worker log for the timeout, and its order id was replayed by hand against production; nothing recorded which ids had been replayed (→ sources/sessions/2026-08-14-invoice-worker-retry.md).

## Why it stopped

- Three retries with backoff and a dead-letter queue replaced it, so a job the worker cannot deliver now lands in `invoices.dead` instead of being lost — see [[decisions/2026-08-14-invoice-worker-retries-with-backoff]] (→ sources/sessions/2026-08-14-invoice-worker-retry.md).
- The queue existed from 2026-08-27 and had taken zero messages as of 2026-09-05, which is when this page was deprecated (→ sources/sessions/2026-09-05-daily-deploys.md).

## Conflicts
