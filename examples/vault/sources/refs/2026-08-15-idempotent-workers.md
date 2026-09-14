---
url: https://example.com/posts/idempotent-workers
title: Designing idempotent background workers
added: 2026-08-15
why: the retry policy added on 2026-08-14 only works if the worker is idempotent; this is the argument for the idempotency key
ingested: true
---

# Designing idempotent background workers

A retry is only safe when running the job twice has the same effect as running it once. The usual way to get there is an idempotency key: a value derived from the job's input, stored with the result, and checked before the job does any work.

Three rules that follow from that:

1. Derive the key from the business input (an order id), not from the message id, because a re-enqueued message gets a new id.
2. Store the key in the same transaction as the side effect, or a crash between the two leaves the job half done.
3. Retry with backoff and give up: an unbounded retry hides an outage behind a growing queue.
