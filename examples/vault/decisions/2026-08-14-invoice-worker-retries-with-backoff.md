---
title: Invoice worker retries 3× with backoff, then dead-letters
type: decision
brief: false
volatile: false
locked: false
updated: 2026-08-15
sources: [sources/sessions/2026-08-14-invoice-worker-retry.md, sources/refs/2026-08-15-idempotent-workers.md]
---

On 2026-08-14 the [[projects/acme-billing]] invoice worker got a bounded retry policy: 3 attempts with exponential backoff (1s, 4s, 16s), then the job goes to a dead-letter queue. Bounded rather than unbounded because an unbounded retry had hidden a real outage for two hours on 2026-08-12.

## Context

- Before this, the worker caught the payments API timeout, logged it and acked the message, so the job was silently dropped (→ sources/sessions/2026-08-14-invoice-worker-retry.md).
- A retry is only safe if the worker is idempotent, so an idempotency key derived from the order id shipped alongside (→ sources/refs/2026-08-15-idempotent-workers.md).

## Consequences

- The dead-letter queue is owned by [[people/platform-team]] and did not exist until 2026-08-27 (→ sources/sessions/2026-08-14-invoice-worker-retry.md).
- The policy is explicitly not applied to the reconciler (→ sources/memory/2026-08-22-reconciler-retry-policy.md).

## Conflicts
