---
memory: ~/.claude/projects/-Users-me-Repos-acme-billing/memory/reconciler-retry-policy.md
project: ~/Repos/acme-billing
added: 2026-08-22
title: "reconciler-retry-policy"
ingested: true
---

---
name: reconciler-retry-policy
description: The reconciler must not get the invoice worker's retry policy
metadata:
  type: project
---

The reconciler is a batch job, not a queue consumer: a failed run is re-run whole the next night, so per-row retries with backoff would only make a bad night slower. Keep the 3×-with-backoff policy on the invoice worker only.

**Why:** the user said so on 2026-08-22 after the agent proposed copying the policy across.
**How to apply:** if asked to add retries to the reconciler, point at this and ask first.
