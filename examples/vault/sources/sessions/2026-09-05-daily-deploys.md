---
session: c4d5e6f7-a8b9-4c0d-9e1f-2a3b4c5d6e7f
date: 2026-09-05
cwd: ~/Repos/acme-billing
branch: main
title: Move acme-billing to daily deploys
ingested: true
---

## What happened
- Removed the Tuesday/Thursday deploy gate from the pipeline; the platform team enabled daily deploys for acme-billing on 2026-09-01.
- Added a smoke test that runs the reconciler match step against staging before every deploy.
- Confirmed that the dead-letter queue from 2026-08-14 now exists and has received zero messages.

## Decisions
- (none)

## Learned
- [topic:release-process] acme-billing deploys daily at 10:00 UTC since 2026-09-01; the Tuesday/Thursday schedule is gone.
- [person:platform-team] enabled daily deploys and now owns the deploy calendar for all services.

## Open threads
- Whether the nightly reconciler should move to run right after the daily deploy instead of 02:00 UTC.
