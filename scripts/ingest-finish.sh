#!/usr/bin/env bash
# Close an ingest batch deterministically.
#
#   ingest-finish.sh --vault <path> --sources <file-with-one-source-path-per-line> [--note "<text>"]
#
# 1. secret gate on every changed or new wiki page (aborts before anything is marked)
# 2. mark the listed sources ingested: true
# 3. regenerate index.md, compile brief.md from pages with brief: true
# 4. append the log.md entry, commit, move the brain/last-ingest tag
# Prints the open conflicts afterwards so the skill can ask the human.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

vp="" list="" note=""
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) vp=$(expand_home "$2"); shift ;;
    --sources) list="$2"; shift ;;
    --note) note="$2"; shift ;;
  esac
  shift
done
[ -d "$vp" ] && [ -f "$list" ] || { echo "usage: ingest-finish.sh --vault <path> --sources <list-file> [--note text]" >&2; exit 2; }
cd "$vp"
today=$(date +%Y-%m-%d)

# 1. gate
changed=$( { git diff --name-only -- . ':(exclude)sources'; git ls-files --others --exclude-standard -- . ':(exclude)sources'; } | grep '\.md$' | sort -u || true)
bad=0
for f in $changed; do
  [ -f "$f" ] || continue
  if ! "$BRAIN_ROOT/scripts/secret-gate.sh" < "$f" 2>/dev/null; then echo "secret gate: $f" >&2; bad=1; fi
done
[ $bad = 0 ] || { echo "secret gate blocked the commit; fix the pages above and run finish again" >&2; exit 1; }

# 2. mark sources
n=0
while IFS= read -r s; do
  [ -n "$s" ] && [ -f "$s" ] || continue
  sed -i '' 's/^ingested: false$/ingested: true/' "$s" 2>/dev/null || sed -i 's/^ingested: false$/ingested: true/' "$s"
  n=$((n+1))
done < "$list"

# 3. index + brief
"$BRAIN_ROOT/scripts/index.sh" "$vp"
{
  for f in $(grep -l '^brief: true' $(find . -maxdepth 2 -name '*.md' ! -path './sources/*' ! -name index.md ! -name brief.md ! -name log.md ! -name CLAUDE.md) 2>/dev/null | sort); do
    t=$(grep -m1 '^title:' "$f" | cut -d' ' -f2-)
    s=$(awk 'BEGIN{fm=0} NR==1 && /^---$/ {fm=1; next} fm==1 && /^---$/ {fm=2; next} fm==2 && !/^\s*$/ && !/^#/ {print; exit}' "$f")
    printf -- '- **%s** — %s [[%s]]\n' "$t" "$s" "${f#./}" | sed 's/\.md\]\]$/]]/'
  done
} > brief.md
"$BRAIN_ROOT/scripts/secret-gate.sh" < brief.md >/dev/null 2>&1 || { echo "secret gate: brief.md" >&2; : > brief.md; }

# 4. log, commit, tag
created=$(git ls-files --others --exclude-standard -- . ':(exclude)sources' | grep -c '\.md$' || true)
updated=$(git diff --name-only -- . ':(exclude)sources' ':(exclude)index.md' ':(exclude)brief.md' ':(exclude)log.md' | grep -c '\.md$' || true)
wiki_dirs=$(find . -maxdepth 1 -mindepth 1 -type d ! -name sources ! -name '.*')
conflicts=$( { [ -n "$wiki_dirs" ] && grep -rh '^- \[open\]' $wiki_dirs 2>/dev/null; } | wc -l | tr -d ' ' || true)
printf '## [%s] ingest | %s sources → %s pages updated, %s created, %s open conflicts%s\n' "$today" "$n" "$updated" "$created" "$conflicts" "${note:+ — $note}" >> log.md

lock_wait "$vp" || { echo "vault is locked; commit skipped" >&2; exit 1; }
git add -A >/dev/null
git diff --cached --quiet || git commit -q -m "ingest: $today — $n sources, $updated updated, $created created"
git tag -f brain/last-ingest >/dev/null
unlock "$vp"

printf 'ingested %s sources; %s pages updated, %s created; tag brain/last-ingest moved to %s\n' "$n" "$updated" "$created" "$(git rev-parse --short HEAD)"
if [ "$conflicts" -gt 0 ]; then
  printf '\nOpen conflicts (%s):\n' "$conflicts"
  grep -rn '^- \[open\]' $wiki_dirs 2>/dev/null | sed 's/^/  /' || true
fi
