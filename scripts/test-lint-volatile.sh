#!/usr/bin/env bash
# test-lint-volatile.sh — behaviour tests for lint rule 2, on a throwaway vault.
#
# Rule 2 asks when a volatile page's claims were last *checked*, which `updated:` does not
# answer: `updated:` is when the page's text last changed, and an ingest that appends one open
# thread bumps it without re-verifying anything. The page that case produces — fresh text, stale
# checks — is the one the rule exists for and the one the old version could not see, so it is
# the first test here.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v="$(mktemp -d)"
trap 'rm -r -f "$v"' EXIT

pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  ok %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s — %s\n' "$1" "$2" >&2; }

mkdir -p "$v/topics" "$v/sources/sessions"
rule2() { { "$here/lint.sh" "$v" 2>/dev/null || true; } | awk '/^## 2\./{f=1; next} /^## 3\./{f=0} f'; }

page() {  # page <slug> <volatile> <updated> <body>
  { printf -- '---\ntitle: T\ntype: topic\nvolatile: %s\nupdated: %s\n---\n\nA page.\n\n' "$2" "$3"
    printf '%s\n' "$4"
  } > "$v/topics/$1.md"
}
reset() { rm -f "$v"/topics/*.md; }

# Fresh text, stale check: the case `updated:` alone reports as healthy.
reset
page stale-check true 2026-10-18 'The fix is on main (verified 2026-01-05: ~/Repos/acme a1b2c3d in origin/main).'
if rule2 | grep -q 'stale-check.md — last verified 2026-01-05'; then
  ok "a page with fresh text and a stale marker is reported on the marker"
else bad "a page with fresh text and a stale marker is reported on the marker" "$(rule2)"; fi

reset
page fresh-check true 2026-01-05 "On main (verified $(date +%Y-%m-%d): ~/Repos/acme a1b2c3d in origin/main)."
if rule2 | grep -q '(none)'; then ok "a stale page whose claims were just checked is quiet"
else bad "a stale page whose claims were just checked is quiet" "$(rule2)"; fi

# The newest marker is the page's check date: one old claim does not make a checked page stale.
reset
page mixed true 2026-01-05 "Old (verified 2026-01-05: ~/Repos/acme a1b2c3d in origin/main).
New (verified $(date +%Y-%m-%d): ~/Repos/acme e4f5a6b in origin/main)."
if rule2 | grep -q '(none)'; then ok "the newest marker decides, not the oldest"
else bad "the newest marker decides, not the oldest" "$(rule2)"; fi

# No marker to derive from: fall back to `updated:`, and say so, because the action is different
# — give the claims markers rather than re-check ones that do not exist.
reset
page no-marker true 2026-01-05 'Nothing here carries a marker.'
if rule2 | grep -q 'no-marker.md — updated, and carries no marker to check 2026-01-05'; then
  ok "a page with no marker falls back to updated and says which it used"
else bad "a page with no marker falls back to updated and says which it used" "$(rule2)"; fi

reset
page not-volatile false 2026-01-05 'Nothing here carries a marker.'
if rule2 | grep -q '(none)'; then ok "a page that is not volatile is not this rule's business"
else bad "a page that is not volatile is not this rule's business" "$(rule2)"; fi

# A deprecated page is history and is not meant to be updated; rule 14 owns it.
reset
{ printf -- '---\ntitle: T\ntype: topic\nvolatile: true\ndeprecated: 2026-02-01 — superseded by [[topics/other]]\nupdated: 2026-01-05\n---\n\nA page.\n'
} > "$v/topics/gone.md"
if rule2 | grep -q '(none)'; then ok "a deprecated page is left alone"
else bad "a deprecated page is left alone" "$(rule2)"; fi

# A marker written in a form verify.sh does not produce must not be read as a check date.
reset
page malformed true 2026-01-05 'On main (verified last week: ~/Repos/acme a1b2c3d in origin/main).'
if rule2 | grep -q 'malformed.md — updated, and carries no marker'; then
  ok "a marker with no absolute date is not a check date"
else bad "a marker with no absolute date is not a check date" "$(rule2)"; fi

printf 'test-lint-volatile: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
