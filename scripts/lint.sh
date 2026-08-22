#!/usr/bin/env bash
# Vault health report. Deterministic rules only; the skill adds the judgment rules.
#
#   lint.sh <vault-path> [--conflict-days 14] [--volatile-days 30] [--digest-days 2]
#
# Rules (numbers follow docs/schema.md "Lint rules"):
#   1. [open] conflicts older than N days
#   2. volatile: true pages not updated in N days
#   3. pages with no inbound [[links]] (index.md and brief.md do not count)
#   5. sources still ingested: false after N days
#   7. (→ human, …) claims present before the last ingest and absent after it
#   8. generated files (index.md, brief.md, log.md) that are not valid UTF-8
# Rules 4 (names without a page) and 6 (brief vs built-in memory) need judgment; the
# report ends with the inputs for them.
set -euo pipefail
vp="${1:?vault path}"; shift || true
conflict_days=14 volatile_days=30 digest_days=2
while [ $# -gt 0 ]; do
  case "$1" in
    --conflict-days) conflict_days="$2"; shift ;;
    --volatile-days) volatile_days="$2"; shift ;;
    --digest-days) digest_days="$2"; shift ;;
  esac
  shift
done
cd "$vp"
today=$(date +%Y-%m-%d)
now=$(date +%s)

epoch() { date -j -f '%Y-%m-%d' "$1" +%s 2>/dev/null || date -d "$1" +%s 2>/dev/null || echo 0; }
age_days() { echo $(( (now - $(epoch "$1")) / 86400 )); }

wiki_dirs=$(find . -maxdepth 1 -mindepth 1 -type d ! -name sources ! -name '.*' | sed 's|^\./||' | sort)
pages=$(for d in $wiki_dirs; do find "$d" -maxdepth 1 -name '*.md'; done | sort)
findings=0

printf '# Lint — %s — %s\n\n' "$(basename "$vp")" "$today"

# 1
printf '## 1. Open conflicts older than %s days\n' "$conflict_days"
n=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  f=${line%%:*}; rest=${line#*:}; d=$(printf '%s' "$rest" | grep -o '\[open\] [0-9-]*' | cut -d' ' -f2)
  [ -n "$d" ] || continue
  a=$(age_days "$d")
  if [ "$a" -ge "$conflict_days" ]; then printf -- '- %s — %s days: %s\n' "$f" "$a" "$(printf '%s' "$rest" | cut -c1-140)…"; n=$((n+1)); fi
done < <(grep -rn '^- \[open\]' $wiki_dirs 2>/dev/null | sed -E 's/^([^:]*):[0-9]+:/\1:/' || true)
[ $n = 0 ] && printf '(none)\n'; findings=$((findings+n)); printf '\n'

# 2
printf '## 2. Volatile pages not updated in %s days\n' "$volatile_days"
n=0
for f in $pages; do
  grep -q '^volatile: true' "$f" || continue
  d=$(grep -m1 '^updated:' "$f" | awk '{print $2}'); [ -n "$d" ] || continue
  a=$(age_days "$d")
  if [ "$a" -ge "$volatile_days" ]; then printf -- '- %s — updated %s (%s days)\n' "$f" "$d" "$a"; n=$((n+1)); fi
done
[ $n = 0 ] && printf '(none)\n'; findings=$((findings+n)); printf '\n'

# 3
printf '## 3. Pages with no inbound links\n'
n=0
for f in $pages; do
  ref="${f%.md}"
  if ! grep -rlF "[[$ref]]" $wiki_dirs --exclude="$(basename "$f")" 2>/dev/null | grep -qv "^$f$"; then
    printf -- '- %s\n' "$f"; n=$((n+1))
  fi
done
[ $n = 0 ] && printf '(none)\n'; findings=$((findings+n)); printf '\n'

# 5
printf '## 5. Sources not ingested after %s days\n' "$digest_days"
n=0
for f in $(grep -l '^ingested: false' sources/*/*.md 2>/dev/null || true); do
  d=$(basename "$f" | cut -c1-10); a=$(age_days "$d")
  if [ "$a" -ge "$digest_days" ]; then printf -- '- %s (%s days)\n' "$f" "$a"; n=$((n+1)); fi
done
[ $n = 0 ] && printf '(none)\n'; findings=$((findings+n)); printf '\n'

# 7
printf '## 7. Human claims lost by the last ingest\n'
n=0
if git rev-parse -q --verify brain/last-ingest >/dev/null 2>&1 && git rev-parse -q --verify 'brain/last-ingest^' >/dev/null 2>&1; then
  for f in $(git diff --name-only 'brain/last-ingest^' brain/last-ingest -- $wiki_dirs 2>/dev/null | grep '\.md$' || true); do
    before=$(git show "brain/last-ingest^:$f" 2>/dev/null | grep -c '(→ human' || true)
    after=$(git show "brain/last-ingest:$f" 2>/dev/null | grep -c '(→ human' || true)
    if [ "${before:-0}" -gt "${after:-0}" ]; then printf -- '- %s — %s human claims before, %s after\n' "$f" "$before" "$after"; n=$((n+1)); fi
  done
else
  printf '(no ingest history yet)\n'
fi
[ $n = 0 ] && printf '(none)\n'; findings=$((findings+n)); printf '\n'

# 8
printf '## 8. Generated files unreadable\n'
n=0
for f in index.md brief.md log.md; do
  [ -f "$f" ] || continue
  if ! iconv -f UTF-8 -t UTF-8 "$f" >/dev/null 2>&1; then
    printf -- '- %s — not valid UTF-8; grep treats it as binary and skips it silently\n' "$f"; n=$((n+1))
  fi
done
[ $n = 0 ] && printf '(none)\n'; findings=$((findings+n)); printf '\n'

printf '## Summary\n%s finding(s) from rules 1, 2, 3, 5, 7, 8. Rules 4 and 6 need judgment — inputs below.\n\n' "$findings"

printf '## Inputs for rule 4 (names on ≥ 3 pages with no page of their own)\nPages (%s): ' "$(printf '%s\n' "$pages" | grep -c .)"
printf '%s\n' "$pages" | sed 's|\.md$||' | tr '\n' ' '; printf '\n\n'

printf '## Inputs for rule 6 (brief vs built-in memory)\n### brief.md\n'
cat brief.md 2>/dev/null || printf '(empty)\n'
printf '\n### memory files\n'
ls "$HOME"/.claude/projects/*/memory/*.md 2>/dev/null | grep -v '/MEMORY\.md$' | sed 's/^/- /' || printf '(none)\n'
