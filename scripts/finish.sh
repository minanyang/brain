#!/usr/bin/env bash
# Close a vault operation deterministically.
#
#   finish.sh --vault <path> --op <ingest|query|lint|clip> [--sources <file, one source path per line>] [--note "<text>"]
#
# 1. secret gate on every changed or new wiki page and ref (aborts before anything is marked)
# 2. ingest only: mark the listed sources ingested: true
# 3. regenerate index.md, compile brief.md from pages with brief: true
# 4. append the log.md entry (prefixed with the op), commit; ingest only: move the brain/last-ingest tag
# Prints the open conflicts afterwards so the skill can ask the human.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

vp="" list="" note="" op="" add=()
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) vp=$(expand_home "$2"); shift ;;
    --op) op="$2"; shift ;;
    --sources) list="$2"; shift ;;
    --note) note="$2"; shift ;;
    --add) shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do add+=("$1"); shift; done; continue ;;
  esac
  shift
done
case "$op" in ingest|query|lint|clip) ;; *) echo "usage: finish.sh --vault <path> --op <ingest|query|lint|clip> [--sources <list-file>] [--note text]" >&2; exit 2 ;; esac
[ -d "$vp" ] || { echo "vault not found: $vp" >&2; exit 2; }
[ -z "$list" ] || [ -f "$list" ] || { echo "sources list not found: $list" >&2; exit 2; }
cd "$vp"
today=$(date +%Y-%m-%d)

# 1. gate — every changed or new markdown file except session digests (those were gated by distill)
changed=$( { git diff --name-only -- . ':(exclude)sources/sessions'; git ls-files --others --exclude-standard -- . ':(exclude)sources/sessions'; } | grep '\.md$' | sort -u || true)
bad=0
for f in $changed; do
  [ -f "$f" ] || continue
  if ! "$BRAIN_ROOT/scripts/secret-gate.sh" < "$f" 2>/dev/null; then echo "secret gate: $f" >&2; bad=1; fi
done
[ $bad = 0 ] || { echo "secret gate blocked the commit; fix the pages above and run finish again" >&2; exit 1; }

# 2. mark sources (ingest only)
n=0
if [ "$op" = ingest ] && [ -n "$list" ]; then
  while IFS= read -r s; do
    [ -n "$s" ] && [ -f "$s" ] || continue
    sed -i '' 's/^ingested: false$/ingested: true/' "$s" 2>/dev/null || sed -i 's/^ingested: false$/ingested: true/' "$s"
    n=$((n+1))
  done < "$list"
fi

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
case "$op" in
  ingest) printf '## [%s] ingest | %s sources → %s pages updated, %s created, %s open conflicts%s\n' "$today" "$n" "$updated" "$created" "$conflicts" "${note:+ — $note}" >> log.md ;;
  *)      printf '## [%s] %s | %s pages updated, %s created%s\n' "$today" "$op" "$updated" "$created" "${note:+ — $note}" >> log.md ;;
esac

lock_wait "$vp" || { echo "vault is locked; commit skipped" >&2; exit 1; }
# Only ingest may stage the whole tree: it is the op that reads human edits and
# rewrites the pages. Every other op stages just the generated files and whatever
# it wrote, because a human edit swept into a Brain commit disappears from the
# next ingest's human-edit diff (which excludes Brain's own commits) and would
# never be cited as (→ human, …) again.
if [ "$op" = ingest ]; then
  git add -A >/dev/null
else
  git add index.md brief.md log.md >/dev/null 2>&1 || true
  [ ${#add[@]} -gt 0 ] && git add -- "${add[@]}" >/dev/null 2>&1 || true
  left=$(git status --porcelain -- . ':(exclude)index.md' ':(exclude)brief.md' ':(exclude)log.md' | grep -v '^[MARD]  ' || true)
  [ -n "$left" ] && printf 'left uncommitted (not this op'"'"'s to stage):\n%s\n' "$left" >&2
fi
if [ "$op" = ingest ]; then msg="ingest: $today — $n sources, $updated updated, $created created"; else msg="$op: $today — ${note:-$updated updated, $created created}"; fi
git diff --cached --quiet || git commit -q -m "$msg"
[ "$op" = ingest ] && git tag -f brain/last-ingest >/dev/null
unlock "$vp"

if [ "$op" = ingest ]; then printf 'ingested %s sources; %s pages updated, %s created; tag brain/last-ingest moved to %s\n' "$n" "$updated" "$created" "$(git rev-parse --short HEAD)"
else printf '%s: %s pages updated, %s created; committed %s\n' "$op" "$updated" "$created" "$(git rev-parse --short HEAD)"; fi
if [ "$conflicts" -gt 0 ]; then
  printf '\nOpen conflicts (%s):\n' "$conflicts"
  grep -rn '^- \[open\]' $wiki_dirs 2>/dev/null | sed 's/^/  /' || true
fi
