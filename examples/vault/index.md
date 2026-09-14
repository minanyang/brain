# Index

## decisions
- [[decisions/2026-08-14-invoice-worker-retries-with-backoff]] — On 2026-08-14 the [[projects/acme-billing]] invoice worker got a bounded retry policy: 3 attempts with exponential backoff (1s, 4s, 16s), then the job goes to a dead-letter queue.

## me
- [[me/working-style]] — Backend engineer on [[projects/acme-billing]] who wants a failing test before every fix and small, single-purpose PRs.

## people
- [[people/platform-team]] — The platform team owns queues, the CI pipeline and, since 2026-09-01, the deploy calendar for every service including [[projects/acme-billing]].
- [[people/priya-nair]] — Priya reviews most [[projects/acme-billing]] PRs and pushes for fixtures that look like production data.

## projects
- [[projects/acme-billing]] — acme-billing (`~/Repos/acme-billing`) is the invoicing service: an invoice worker that consumes `invoices.pending` and calls the payments API, plus a nightly reconciler that matches invoices to payments.

## topics
- [[topics/release-process]] — How [[projects/acme-billing]] gets to production.
