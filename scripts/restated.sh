#!/usr/bin/env bash
# restated.sh <vault-path> <term> [<term>...] — every place a claim is repeated.
#
# A wrong claim is rarely written once. Correcting the page you happened to read leaves the
# same sentence on the pages you did not, and the next agent reads one of those instead:
# measured on 2026-09-23, a claim corrected on one page was still answered wrongly from two
# restatements elsewhere. Before and after correcting a claim, look for its copies.
#
# Prints `page:line` for every claim line carrying ALL the terms, case-insensitively, so the
# terms are the distinctive words of the claim rather than its exact wording:
#   restated.sh ~/vault squash auto-tag
#   restated.sh ~/vault "never ran" S3
# Conflict entries are listed separately: a claim quoted inside `- [open]`/`- [resolved]` is a
# record of what was said, not an assertion, and correcting it would rewrite the history.
set -euo pipefail
vp="${1:?usage: restated.sh <vault-path> <term> [<term>...]}"; shift
[ $# -gt 0 ] || { echo "usage: restated.sh <vault-path> <term> [<term>...]" >&2; exit 2; }
cd "$vp"

wiki_dirs=$(find . -maxdepth 1 -mindepth 1 -type d ! -name sources ! -name '.*' | sed 's|^\./||' | sort)
[ -n "$wiki_dirs" ] || exit 0

hits=$(grep -rniF -- "$1" $wiki_dirs 2>/dev/null || true)
shift
for t in "$@"; do hits=$(printf '%s\n' "$hits" | grep -iF -- "$t" || true); done

claims=$(printf '%s\n' "$hits" | grep -vE '^[^:]+:[0-9]+:- \[(open|resolved)' | grep . || true)
records=$(printf '%s\n' "$hits" | grep -E '^[^:]+:[0-9]+:- \[(open|resolved)' | grep . || true)

n=$(printf '%s' "$claims" | grep -c . || true)
printf 'claims: %s\n' "$n"
[ -n "$claims" ] && printf '%s\n' "$claims" | sed 's/^/  /'
if [ -n "$records" ]; then
  printf 'in conflict entries (quotations, leave them): %s\n' "$(printf '%s' "$records" | grep -c . || true)"
  printf '%s\n' "$records" | cut -c1-120 | sed 's/^/  /'
fi
