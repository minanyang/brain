#!/usr/bin/env bash
# test-lint-threads.sh — behaviour tests for lint rule 13, on a throwaway vault.
#
# Rule 13 is the only stateful rule: it reports a page whose open-thread list is longer than
# the last time lint ran, so the thing that can break silently is the baseline. A rule that
# forgot its baseline would report the same pages at every run, which is the noise this
# replaced; one that recorded a count it never compares would report nothing, ever.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v="$(mktemp -d)"
trap 'rm -rf "$v"' EXIT

pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  ok %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s — %s\n' "$1" "$2" >&2; }

mkdir -p "$v/topics" "$v/sources/sessions"
threads() {  # threads <count>
  { printf -- '---\ntitle: T\ntype: topic\nupdated: 2026-03-04\n---\n\nA page.\n\n## Open threads\n'
    i=1; while [ "$i" -le "$1" ]; do printf -- '- waiting on thing %s\n' "$i"; i=$((i+1)); done
  } > "$v/topics/busy.md"
}
# lint.sh exits with its finding count, so the call is guarded: under pipefail a run that
# found something would otherwise fail the test that asked it to find something.
rule13() { { "$here/lint.sh" "$v" 2>/dev/null || true; } | awk '/^## 13/{f=1; next} /^## 14/{f=0} f'; }

threads 13
if rule13 | grep -q 'topics/busy.md'; then ok "a first run with no baseline reports what is over the threshold"
else bad "a first run with no baseline reports what is over the threshold" "$(rule13)"; fi

if rule13 | grep -q '(none)'; then ok "a second run with the same count says nothing"
else bad "a second run with the same count says nothing" "$(rule13)"; fi

threads 15
out=$(rule13)
case "$out" in
  *"15 open threads, up from 13"*) ok "a longer list is reported with both counts" ;;
  *) bad "a longer list is reported with both counts" "$out" ;;
esac

threads 14
if rule13 | grep -q '(none)'; then ok "a list that shrank says nothing"
else bad "a list that shrank says nothing" "$(rule13)"; fi

threads 3
if rule13 | grep -q '(none)'; then ok "a short list under the threshold stays quiet"
else bad "a short list under the threshold stays quiet" "$(rule13)"; fi

threads 4
out=$(rule13)
case "$out" in
  *"4 open threads, up from 3"*) ok "growth is reported below the threshold too, once a baseline exists" ;;
  *) bad "growth is reported below the threshold too, once a baseline exists" "$out" ;;
esac

printf 'test-lint-threads: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
