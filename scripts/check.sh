#!/usr/bin/env bash
# Repository check: run before committing. Everything here has caught a real bug.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
fail=0
say() { printf '%s %s\n' "$1" "$2"; }

for f in scripts/*.sh hooks/*.sh; do
  bash -n "$f" 2>/dev/null || { say "FAIL" "syntax: $f"; fail=1; }
done
say "ok" "bash syntax"

for f in scripts/*.sh hooks/*.sh; do
  [ -x "$f" ] || { say "FAIL" "not executable: $f"; fail=1; }
done
say "ok" "executable bits"

for f in .claude-plugin/*.json hooks/hooks.json; do
  jq empty "$f" 2>/dev/null || { say "FAIL" "invalid JSON: $f"; fail=1; }
done
pv=$(jq -r .version .claude-plugin/plugin.json)
mv=$(jq -r '.plugins[0].version // empty' .claude-plugin/marketplace.json)
[ "$pv" = "$mv" ] || { say "FAIL" "version mismatch: plugin.json $pv vs marketplace.json ${mv:-none}"; fail=1; }
say "ok" "manifests"

for d in skills/*/; do
  f="$d/SKILL.md"
  [ -f "$f" ] || { say "FAIL" "missing $f"; fail=1; continue; }
  grep -q '^name: ' "$f" || { say "FAIL" "no name: $f"; fail=1; }
  grep -q '^description: Use when' "$f" || { say "FAIL" "description must start with 'Use when': $f"; fail=1; }
  grep -q '^allowed-tools: Bash$' "$f" && { say "FAIL" "unscoped Bash: $f"; fail=1; }
  n=$(wc -l < "$f")
  [ "$n" -le 200 ] || { say "FAIL" "over 200 lines ($n): $f"; fail=1; }
done
say "ok" "skills"

# Fabricated data only: the pattern repo must never carry anything derived from a real
# vault. The author's own name in LICENSE and the manifests is intentional and exempt.
scan() { grep -rniE 'pixel|eatsy|mybrain|miayang0513|mian\.yang|mian yang' \
  --exclude-dir=.git --exclude=check.sh --exclude=LICENSE --exclude='*.json' . ; }
if scan | grep -q .; then
  say "FAIL" "personal or employer name found:"; scan | head -5; fail=1
else
  say "ok" "no real-vault data"
fi

if command -v claude >/dev/null; then
  claude plugin validate . --strict >/dev/null 2>&1 || { say "FAIL" "claude plugin validate"; fail=1; }
  say "ok" "plugin validate"
fi

[ $fail = 0 ] && say "PASS" "all checks" || say "FAIL" "see above"
exit $fail
