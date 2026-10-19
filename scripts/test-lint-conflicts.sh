#!/usr/bin/env bash
# test-lint-conflicts.sh — behaviour tests for lint rule 15, on a throwaway vault.
#
# Rule 15 is the mechanism behind a rule the schema can only ask for: that a contested claim
# says so where it sits, because the conflict section is at the foot of the page and nobody
# answering a question from the body reads it. All three ways the mark and the entry fall out of
# step are silent, which is what makes a check worth having rather than more prose.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v="$(mktemp -d)"
trap 'rm -r -f "$v"' EXIT

pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  ok %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s — %s\n' "$1" "$2" >&2; }

mkdir -p "$v/topics" "$v/sources/sessions"
# lint.sh exits with its finding count, so each call is guarded: under pipefail a run that found
# something would otherwise fail the test that asked it to find something.
rule15() { { "$here/lint.sh" "$v" 2>/dev/null || true; } | awk '/^## 15/{f=1; next} /^## Summary/{f=0} f'; }

page() {  # page <body> <conflicts…>
  { printf -- '---\ntitle: T\ntype: topic\nupdated: 2026-03-04\n---\n\nA page.\n\n## Access\n'
    printf '%s\n' "$1"
    if [ $# -gt 1 ]; then
      printf -- '\n## Conflicts\n'
      shift
      for c in "$@"; do printf '%s\n' "$c"; done
    fi
  } > "$v/topics/db-access.md"
}

claim='One administrator user reaches the billing database (→ sources/sessions/a.md).'
entry='- [open] 2026-03-01: "One administrator user reaches the billing database" (→ sources/sessions/a.md) vs "Two accounts reach it" (→ sources/sessions/b.md)'

page "$claim" "$entry"
if rule15 | grep -q 'not marked in the body'; then ok "an open conflict with an unmarked claim is reported"
else bad "an open conflict with an unmarked claim is reported" "$(rule15)"; fi
if rule15 | grep -q 'add \[contested 2026-03-01\]'; then ok "the report says the mark and the date to write"
else bad "the report says the mark and the date to write" "$(rule15)"; fi

page "One administrator user reaches the billing database [contested 2026-03-01] (→ sources/sessions/a.md)." "$entry"
if rule15 | grep -q '(none)'; then ok "a marked claim with an open conflict is quiet"
else bad "a marked claim with an open conflict is quiet" "$(rule15)"; fi

# The page was rewritten under the entry: the conflict now quotes something the body no longer
# says, so neither the mark nor the entry can be trusted.
page "Access was revoked entirely in March (→ sources/sessions/c.md)." "$entry"
if rule15 | grep -q 'no longer in the body'; then ok "a conflict quoting a claim the body dropped is reported"
else bad "a conflict quoting a claim the body dropped is reported" "$(rule15)"; fi

# A mark left behind after a resolution tells every later reader the claim is disputed when the
# human has already settled it — worse than no mark at all.
page "One administrator user reaches the billing database [contested 2026-03-01] (→ human, 2026-03-05)." \
  '- [resolved 2026-03-05] "One administrator user reaches the billing database" — decided: one user'
if rule15 | grep -q 'with no open conflict'; then ok "a mark left on after a resolution is reported"
else bad "a mark left on after a resolution is reported" "$(rule15)"; fi

page "One administrator user reaches the billing database (→ human, 2026-03-05)." \
  '- [resolved 2026-03-05] "One administrator user reaches the billing database" — decided: one user'
if rule15 | grep -q '(none)'; then ok "a resolved conflict with the mark removed is quiet"
else bad "a resolved conflict with the mark removed is quiet" "$(rule15)"; fi

page "$claim"
if rule15 | grep -q '(none)'; then ok "a page with no conflicts at all is quiet"
else bad "a page with no conflicts at all is quiet" "$(rule15)"; fi

# A deprecated page is history: its conflicts are not a backlog, and rule 14 already reports it.
{ printf -- '---\ntitle: T\ntype: topic\ndeprecated: 2026-03-02 — superseded by [[topics/other]]\nupdated: 2026-03-04\n---\n\nA page.\n\n'
  printf '%s\n\n## Conflicts\n%s\n' "$claim" "$entry"
} > "$v/topics/db-access.md"
if rule15 | grep -q '(none)'; then ok "a deprecated page is left alone"
else bad "a deprecated page is left alone" "$(rule15)"; fi

# Two open conflicts on one page are two findings, not one: the mark is per claim.
page "One administrator user reaches the billing database (→ sources/sessions/a.md).
The nightly job runs at 02:00 (→ sources/sessions/a.md)." \
  "$entry" \
  '- [open] 2026-03-02: "The nightly job runs at 02:00" (→ sources/sessions/a.md) vs "It runs at 03:00" (→ sources/sessions/b.md)'
if [ "$(rule15 | grep -c 'not marked in the body')" = 2 ]; then ok "each unmarked claim is its own finding"
else bad "each unmarked claim is its own finding" "$(rule15)"; fi

printf 'test-lint-conflicts: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
