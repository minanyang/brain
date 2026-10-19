---
title: Deploy acme-billing
type: procedure
brief: false
volatile: true
locked: false
deprecated: false
aliases: [ship acme-billing, push to prod]
updated: 2026-09-05
# generated — provenance.sh rewrites the two fields below from this page's own citations; hand edits are discarded
sources: [sources/sessions/2026-09-05-daily-deploys.md]
sources_cited: 1
---

What to run to put [[projects/acme-billing]] in production. [[topics/release-process]] is the shape of the thing — who owns the pipeline, what the schedule is, why the smoke test exists — and this page is only the commands; a step that turns out to need explaining belongs there, not here, so that neither page becomes the stale copy of the other.

Last run 2026-09-05 against `acme-billing` at `4e1a9c2` on `origin/main` (→ sources/sessions/2026-09-05-daily-deploys.md).

## When
A change is on `main` and the daily 10:00 UTC window is open. Outside the window the deploy calendar is [[people/platform-team]]'s to open, and running this anyway is what the calendar exists to prevent (→ sources/sessions/2026-09-05-daily-deploys.md).

## Steps

1. `git -C ~/Repos/acme-billing fetch origin && git -C ~/Repos/acme-billing log --oneline origin/main -1` — note the commit; every step below reports against it.
2. `make smoke-staging` — runs the reconciler match step against staging. As of 2026-09-05 the pipeline runs this itself before every deploy (verified 2026-09-05: ~/Repos/acme-billing 4e1a9c2 in origin/main), so a local run is a check on the local checkout, not a substitute (→ sources/sessions/2026-09-05-daily-deploys.md).
3. `make deploy STAGE=production` — prints the commit it is deploying. Stop if it is not the commit from step 1: that means the pipeline is holding an older build and deploying around it skips the gate.
4. Watch the worker drain: `make worker-status` until the pending count stops falling.

## Checking it worked
`make worker-status` reports the commit from step 1 and a pending count that is not growing. A half-finished deploy looks like the new commit with a pending count that keeps climbing — the worker restarted but is not consuming; raise it with [[people/platform-team]] rather than restarting it again.

## Open threads
- [thread 2026-09-05] Step 4 has no upper bound, so there is no point at which a slow drain becomes a failure — waiting on someone deciding what that number is (→ sources/sessions/2026-09-05-daily-deploys.md)

## Rejected
- [rejected 2026-09-05] Skipping step 2 because the pipeline runs the same smoke test — it tests what the pipeline built, not the local checkout, so skipping it moves the first sight of a local-only break to after the deploy (→ sources/sessions/2026-09-05-daily-deploys.md)

## Conflicts
