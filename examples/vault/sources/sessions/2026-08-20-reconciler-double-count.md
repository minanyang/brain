---
session: 3b9e5d10-7c2a-4f61-8e4d-a1b2c3d4e5f6
date: 2026-08-20
cwd: ~/Repos/acme-billing
branch: fix/reconciler-double-count
title: Reconciler counts a refunded payment twice
ingested: true
---

## What happened
- Reproduced the double count: a payment that was refunded on the same day appeared in both the paid and the refunded totals.
- Root cause was the reconciler reading the payments table without filtering on `status`, so a refunded row still matched as paid.
- Fixed the query and added a regression test with a same-day refund.
- Priya reviewed the PR and asked for the fixture to use a real-shaped payment id instead of `1`.

## Decisions
- (none)

## Learned
- [me] runs the reconciler locally against a database snapshot rather than mocking it; considers mocks for SQL "a lie".
- [person:priya-nair] reviews most acme-billing PRs; cares about fixtures looking like production data.
- [project:acme-billing] the reconciler runs nightly at 02:00 UTC and is the job most often paged on.
- [topic:release-process] deploys go out on Tuesday and Thursday after the 15:00 UTC standup.

## Open threads
- Priya suggested the reconciler should be split into match and report steps.

## Continued (2026-08-21)

## What happened
- Split the reconciler into a match step and a report step as Priya suggested; the report step now reads only from the match output table.
- Deployed to staging; the nightly run produced identical totals to the previous night.

## Learned
- [project:acme-billing] the reconciler is now two steps, match then report, since 2026-08-21.

## Open threads
- Production deploy waits for Tuesday.
