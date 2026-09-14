---
title: Working style
type: me
brief: true
volatile: false
locked: false
updated: 2026-09-05
sources: [sources/sessions/2026-08-14-invoice-worker-retry.md, sources/sessions/2026-08-20-reconciler-double-count.md]
---

Backend engineer on [[projects/acme-billing]] who wants a failing test before every fix and small, single-purpose PRs. Tests against real data shapes, not mocks, and corrects the agent the moment it skips a step rather than after the fact.

## How to work with me

- Write the failing test first. Asked for it twice on 2026-08-14 before the agent complied (→ sources/sessions/2026-08-14-invoice-worker-retry.md).
- Keep PRs small: the idempotency change was split out of the retry PR on request (→ sources/sessions/2026-08-14-invoice-worker-retry.md).
- SQL is tested against a database snapshot, never mocked; mocks for SQL are "a lie" (→ sources/sessions/2026-08-20-reconciler-double-count.md).
- Fixtures should look like production data, a preference shared with [[people/priya-nair]] (→ sources/sessions/2026-08-20-reconciler-double-count.md).

## Conflicts
