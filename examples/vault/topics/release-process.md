---
title: Release process
type: topic
brief: false
volatile: true
locked: false
updated: 2026-09-05
sources: [sources/sessions/2026-08-20-reconciler-double-count.md, sources/sessions/2026-09-05-daily-deploys.md]
---

How [[projects/acme-billing]] gets to production. Deploys are gated by the pipeline that [[people/platform-team]] owns, and the schedule changed on 2026-09-01; the schedule itself is written down in the repository (→ ~/Repos/acme-billing/docs/release.md).

## Pipeline

- As of 2026-09-05, a smoke test runs the reconciler match step against staging before every deploy (verified 2026-09-05: ~/Repos/acme-billing 4e1a9c2 in origin/main) (→ sources/sessions/2026-09-05-daily-deploys.md).

## Schedule

- As of 2026-09-05, acme-billing deploys daily at 10:00 UTC, since 2026-09-01 (→ sources/sessions/2026-09-05-daily-deploys.md, ~/Repos/acme-billing/docs/release.md).
- Until 2026-09-01: Tuesday and Thursday after the 15:00 UTC standup (→ sources/sessions/2026-08-20-reconciler-double-count.md).

## Conflicts
