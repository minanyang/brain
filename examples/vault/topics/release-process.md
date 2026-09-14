---
title: Release process
type: topic
brief: false
volatile: true
locked: false
updated: 2026-09-05
sources: [sources/sessions/2026-08-20-reconciler-double-count.md, sources/sessions/2026-09-05-daily-deploys.md]
---

How [[projects/acme-billing]] gets to production. Deploys are gated by the pipeline that [[people/platform-team]] owns, and the schedule changed on 2026-09-01.

## Pipeline

- A smoke test runs the reconciler match step against staging before every deploy, since 2026-09-05 (→ sources/sessions/2026-09-05-daily-deploys.md).

## Schedule

- Deploys go out on Tuesday and Thursday after the 15:00 UTC standup (→ sources/sessions/2026-08-20-reconciler-double-count.md).

## Conflicts
- [open] 2026-09-05: "deploys go out on Tuesday and Thursday after the 15:00 UTC standup" (→ sources/sessions/2026-08-20-reconciler-double-count.md) vs "acme-billing deploys daily at 10:00 UTC since 2026-09-01; the Tuesday/Thursday schedule is gone" (→ sources/sessions/2026-09-05-daily-deploys.md)
