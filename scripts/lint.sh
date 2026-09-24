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
#   9. git markers that no longer hold (verify.sh)
#  10. exclusive quantifiers in claims a human or a verification settled — where consolidating
#      two sources into one sentence turns "we found one case" into "there was one case"
#  11. candidate cross-page status contradictions for the same ticket — advisory; the skill
#      judges whether the claims describe the same fact and records unresolved conflicts.
#  12. a dated claim or a git marker in the lead of a brief: true page (dates inside
#      citations are provenance and do not count) — the lead is copied verbatim
#      into brief.md and injected at the start of every session, so a fact with a shelf life
#      there is the most expensive kind of staleness and the least checked
# Rules 4 (names without a page) and 6 (brief vs built-in memory) need judgment; the
# report ends with the inputs for them.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
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
for f in $(pending_sources .); do
  # a continued digest is pending since its last append, not since the file's date
  d=$(grep -o '^## Continued ([0-9-]\{10\}' "$f" 2>/dev/null | tail -1 | cut -c15-24 || true)
  [ -n "$d" ] || d=$(basename "$f" | cut -c1-10); a=$(age_days "$d")
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

# 9
printf '## 9. Status markers that no longer hold\n'
n=0
while IFS=$'\t' read -r state loc marker detail; do
  [ -n "$state" ] || continue
  printf -- '- %s %s — %s %s\n' "$state" "$loc" "$marker" "$detail"; n=$((n+1))
done < <("$BRAIN_ROOT/scripts/verify.sh" . 2>/dev/null || true)
[ $n = 0 ] && printf '(none)\n'; findings=$((findings+n)); printf '\n'

# 10
printf '## 10. Exclusive quantifiers in settled claims\n'
n=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  printf -- '- %s…\n' "$(printf '%s' "$line" | cut -c1-180)"; n=$((n+1))
done < <(grep -rnE '(the only|The only|no other|No other|nowhere|Nowhere|never (ran|executed|happened|reached))' $wiki_dirs 2>/dev/null \
           | grep -E 'verified against|\(→ human' | grep -vE '^[^:]+:[0-9]+:- \[(open|resolved)' || true)
[ $n = 0 ] && printf '(none)\n'; findings=$((findings+n)); printf '\n'

printf '## 11. Candidate cross-page claims about the same ticket\n'
n=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  printf -- '- %s\n' "$line"; n=$((n+1))
done < <("$BRAIN_ROOT/scripts/cross-page-claims.sh" . 2>/dev/null || true)
[ $n = 0 ] && printf '(none)\n'
printf '%s advisory candidate(s); excluded from the findings total.\n\n' "$n"

# 12. The lead of a brief page is the only text every session pays for: finish.sh copies the
# first non-blank, non-heading line into brief.md whole. A lead that narrates dated events
# instead of stating what is now grows with every ingest and goes stale between them — on the
# first vault one had reached 1990 bytes with 20 dates, all of which a section below already
# carried. Length is not the test; a shelf life is.
printf '## 12. Dated facts in the lead of a brief page\n'
n=0
for f in $(grep -l '^brief: true' $pages 2>/dev/null | sort); do
  lead=$(awk 'BEGIN{fm=0} NR==1 && /^---$/ {fm=1; next} fm==1 && /^---$/ {fm=2; next} fm==2 && !/^[[:space:]]*$/ && !/^#/ {print; exit}' "$f")
  # A date inside a citation is provenance and does not go stale; only dated claims count.
  claim=$(printf '%s' "$lead" | sed 's/(→[^)]*)//g')
  d=$(printf '%s' "$claim" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | grep -c . || true)
  m=$(printf '%s' "$claim" | grep -oE '\(verified ' | grep -c . || true)
  [ "$d" = 0 ] && [ "$m" = 0 ] && continue
  printf -- '- %s — lead is %s bytes with %s date(s) and %s marker(s); move them to a dated section\n' \
    "${f#./}" "$(printf '%s' "$lead" | wc -c | tr -d ' ')" "$d" "$m"; n=$((n+1))
done
[ $n = 0 ] && printf '(none)\n'; findings=$((findings+n)); printf '\n'

printf '## Summary\n%s finding(s) from rules 1, 2, 3, 5, 7, 8, 9, 10, 12. Rules 4 and 6 need judgment — inputs below.\n\n' "$findings"

printf '## Inputs for rule 4 (names on ≥ 3 pages with no page of their own)\nPages (%s): ' "$(printf '%s\n' "$pages" | grep -c .)"
printf '%s\n' "$pages" | sed 's|\.md$||' | tr '\n' ' '; printf '\n\n'

printf '## Inputs for rule 6 (brief vs built-in memory)\n### brief.md\n'
cat brief.md 2>/dev/null || printf '(empty)\n'
printf '\n### memory files\n'
ls "$HOME"/.claude/projects/*/memory/*.md 2>/dev/null | grep -v '/MEMORY\.md$' | sed 's/^/- /' || printf '(none)\n'
