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
#  13. pages whose ## Open threads list grew since the last lint — per page, never a
#      guess at which thread is finished
#  14. pages deprecated longer than the window, or with a deprecated: value that does not
#      say what superseded it
#  15. a contested claim whose [contested …] mark and its ## Conflicts entry disagree:
#      an open conflict with no mark in the body, one quoting a claim the body no longer
#      carries, or a mark left on after the conflict was resolved
# Rules 4 (names without a page) and 6 (brief vs built-in memory) need judgment; the
# report ends with the inputs for them.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
vp="${1:?vault path}"; shift || true
conflict_days=14 volatile_days=30 digest_days=2 thread_max=12 deprecated_days=180
while [ $# -gt 0 ]; do
  case "$1" in
    --conflict-days) conflict_days="$2"; shift ;;
    --volatile-days) volatile_days="$2"; shift ;;
    --digest-days) digest_days="$2"; shift ;;
    --thread-max) thread_max="$2"; shift ;;
    --deprecated-days) deprecated_days="$2"; shift ;;
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

# A deprecated page is history on purpose (docs/schema.md). Rules 2 and 3 skip it: nobody is
# going to update it, and its inbound links were moved to the successor when it was deprecated,
# so reporting it as stale or orphaned is a weekly finding with no action behind it.
# `|| true` because a page with no `deprecated:` line is the ordinary case and grep reports it
# as failure. Without it, rule 14's bare `v=$(deprecated_value "$f")` took the whole script
# down under `set -e` on the first such page — so rule 14 never produced a finding and
# `## Summary` never printed at all, on any vault, since the rule was written. It survived
# because the same call inside `live()` is reached as `live "$f" || continue`, and `set -e` is
# suspended for a command in an `||` list, so every rule that tests deprecation that way worked.
deprecated_value() { grep -m1 '^deprecated:' "$1" | cut -d' ' -f2- || true; }
live() { v=$(deprecated_value "$1"); [ -z "$v" ] || [ "$v" = false ]; }

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
[ $n = 0 ] && printf '(none)\n'; findings=$((findings+n))
# A conflict whose evidence is gone is not a backlog item. It is counted so it stays
# visible, and left out of the findings so it does not report every week for ever.
u=$( { grep -rc '^- \[unresolvable' $wiki_dirs 2>/dev/null || true; } | awk -F: '{t+=$2} END {print t+0}')
[ "$u" -gt 0 ] && printf '%s conflict(s) marked unresolvable; not counted as findings.\n' "$u"
printf '\n'

# 2
printf '## 2. Volatile pages not updated in %s days\n' "$volatile_days"
n=0
for f in $pages; do
  live "$f" || continue
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
  live "$f" || continue
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

# 13. Open threads accumulate and nothing removes them: a thread is closed by the thing it
# was waiting for happening, and the only moment anyone is looking at both is the ingest that
# files the source saying so. The finding is therefore the page, not the thread. Picking out
# the finished thread was prototyped against a real vault — pair each thread's ticket with a
# later-dated line elsewhere on the same page — and fired 30 times for 5 real defects, because
# whether the later line answers the thread needs the page's sense, which is how four earlier
# scans died too.
#
# What the count alone cannot do is stop. A page can hold more than the threshold with every
# thread genuinely open — on a 208-page vault, six did, and a sweep of all of them closed five
# threads and left 82 standing because they were all still waiting on something. A stock
# measure then names those same pages at every run forever, which is how a rule becomes
# scenery. So the finding is growth, not stock: a page is reported when its list is longer
# than the last time lint ran, the count kept per page in .state/lint-threads.json (gitignored,
# so it is machine-local like every other .state file). The stock is still printed beside it,
# and the first run on a vault with no baseline reports whatever is already over the threshold,
# once. An entry's own date cannot be used for this — most of a real vault's threads predate
# the `- [thread <date>]` shape and carry no date at all.
printf '## 13. Pages whose open-thread list grew since the last lint\n'
n=0
tstate=".state/lint-threads.json"
mkdir -p .state; [ -f "$tstate" ] || printf 'null\n' > "$tstate"
first=0; [ "$(jq -r 'if . == null then "new" else "seen" end' "$tstate")" = new ] && first=1
tnew=$(mktemp)
printf '{}' > "$tnew"
for f in $pages; do
  c=$(awk '/^## Open threads/ {t=1; next} /^## / {t=0} t && /^- / && !/^- \[closed/ {k++} END {print k+0}' "$f")
  page="${f#./}"
  jq --arg p "$page" --argjson c "$c" '.[$p] = $c' "$tnew" > "$tnew.t" && mv "$tnew.t" "$tnew"
  [ "$c" -gt 0 ] || continue
  was=$(jq -r --arg p "$page" '.[$p] // empty' "$tstate")
  if [ $first = 1 ]; then
    [ "$c" -gt "$thread_max" ] || continue
    printf -- '- %s — %s open threads and no earlier count to compare; sweep the section with the page open and close the ones its body already answers\n' "$page" "$c"
  elif [ -n "$was" ] && [ "$c" -gt "$was" ]; then
    printf -- '- %s — %s open threads, up from %s since the last lint; close the ones this ingest answered before the list stops being read\n' "$page" "$c" "$was"
  elif [ -z "$was" ] && [ "$c" -gt "$thread_max" ]; then
    printf -- '- %s — %s open threads on a page lint has not seen before; sweep the section with the page open\n' "$page" "$c"
  else
    continue
  fi
  n=$((n+1))
done
mv "$tnew" "$tstate"
[ $n = 0 ] && printf '(none)\n'; findings=$((findings+n)); printf '\n'

# 14. A page is deprecated rather than deleted so that someone who meets the old thing in the
# wild can still find out what happened to it. After half a year that is a claim worth making
# again on purpose, and a value that names no successor leaves the reader where deprecating was
# meant to get them out of: told this is history, not told where to go instead.
printf '## 14. Deprecated pages past %s days, or not saying what superseded them\n' "$deprecated_days"
n=0
for f in $pages; do
  v=$(deprecated_value "$f"); [ -n "$v" ] || continue; [ "$v" != false ] || continue
  d=$(printf '%s' "$v" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)
  rest=$(printf '%s' "$v" | sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*(—|-|:)?[[:space:]]*//')
  if [ -z "$d" ]; then
    printf -- '- %s — deprecated: carries no date: "%s"\n' "${f#./}" "$v"; n=$((n+1))
  elif [ -z "$rest" ]; then
    printf -- '- %s — deprecated %s but says nothing about what superseded it\n' "${f#./}" "$d"; n=$((n+1))
  else
    a=$(age_days "$d")
    if [ "$a" -ge "$deprecated_days" ]; then
      printf -- '- %s — deprecated %s (%s days): fold what is still wanted into the successor and delete it; git keeps it\n' "${f#./}" "$d" "$a"; n=$((n+1))
    fi
  fi
done
[ $n = 0 ] && printf '(none)\n'; findings=$((findings+n)); printf '\n'

# 15
# The conflict section is at the foot of the page and nobody answering a question from the body
# reads it, so a contested claim has to say so where it sits. This rule is the mechanism behind
# that rule: the schema can ask for the mark, but only a check keeps the mark and the entry from
# drifting apart, and all three ways they drift are silent.
printf '## 15. Contested claims whose mark and conflict entry disagree\n'
n=0
for f in $pages; do
  live "$f" || continue
  body=$(sed '/^## Conflicts$/,$d' "$f")
  open_n=$(grep -c '^- \[open\]' "$f" 2>/dev/null || true)
  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    d=$(printf '%s' "$entry" | grep -o '\[open\] [0-9-]*' | cut -d' ' -f2)
    # The existing claim is the first quoted run on the entry. A prefix of it is matched rather
    # than the whole, because a quote long enough to be unambiguous is also long enough to have
    # been rewrapped since.
    claim=$(printf '%s' "$entry" | sed -n 's/^[^"]*"\([^"]*\)".*$/\1/p' | cut -c1-40)
    [ -n "$claim" ] || continue
    hit=$(printf '%s' "$body" | grep -F -- "$claim" | head -1 || true)
    if [ -z "$hit" ]; then
      printf -- '- %s — the %s conflict quotes "%s…", which is no longer in the body: the page was rewritten under the entry, so re-quote it or resolve it\n' \
        "${f#./}" "${d:-undated}" "$claim"; n=$((n+1))
    elif ! printf '%s' "$hit" | grep -q '\[contested'; then
      printf -- '- %s — the %s conflict is not marked in the body: add [contested %s] to the sentence saying "%s…"\n' \
        "${f#./}" "${d:-undated}" "${d:-$(date +%Y-%m-%d)}" "$claim"; n=$((n+1))
    fi
  done < <(grep '^- \[open\]' "$f" 2>/dev/null || true)
  # A mark left behind after a resolution is worse than no mark: it tells every later reader the
  # claim is disputed when the human has already settled it.
  if [ "${open_n:-0}" = 0 ] && printf '%s' "$body" | grep -q '\[contested'; then
    printf -- '- %s — body carries [contested …] with no open conflict on the page: the conflict was resolved and the mark was left on\n' \
      "${f#./}"; n=$((n+1))
  fi
done
[ $n = 0 ] && printf '(none)\n'; findings=$((findings+n)); printf '\n'

printf '## Summary\n%s finding(s) from rules 1, 2, 3, 5, 7, 8, 9, 10, 12, 13, 14, 15. Rules 4 and 6 need judgment — inputs below.\n\n' "$findings"

printf '## Inputs for rule 4 (names on ≥ 3 pages with no page of their own)\nPages (%s): ' "$(printf '%s\n' "$pages" | grep -c .)"
printf '%s\n' "$pages" | sed 's|\.md$||' | tr '\n' ' '; printf '\n\n'

printf '## Inputs for rule 6 (brief vs built-in memory)\n### brief.md\n'
cat brief.md 2>/dev/null || printf '(empty)\n'
printf '\n### memory files\n'
ls "$HOME"/.claude/projects/*/memory/*.md 2>/dev/null | grep -v '/MEMORY\.md$' | sed 's/^/- /' || printf '(none)\n'
