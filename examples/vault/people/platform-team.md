---
title: Platform team
type: person
brief: false
volatile: false
locked: false
updated: 2026-09-05
sources: [sources/sessions/2026-08-14-invoice-worker-retry.md, sources/sessions/2026-09-05-daily-deploys.md]
---

The platform team owns queues, the CI pipeline and, since 2026-09-01, the deploy calendar for every service including [[projects/acme-billing]]. Anything that needs a new queue or a pipeline change goes to them as a ticket.

## What they own

- Dead-letter queue configuration; a new queue needs a ticket (→ sources/sessions/2026-08-14-invoice-worker-retry.md). The `invoices.dead` queue was created on 2026-08-27 (→ human, 2026-08-28).
- Daily deploys, enabled for acme-billing on 2026-09-01, and the deploy calendar for all services (→ sources/sessions/2026-09-05-daily-deploys.md). See [[topics/release-process]].

## Contact

- Tickets, not messages: a queue request sent in chat was lost and had to be refiled (→ human, 2026-08-28).

## Conflicts
