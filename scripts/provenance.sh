#!/usr/bin/env bash
# provenance.sh <vault-path> [page ...] — regenerate each page's `sources:` frontmatter
# from the citations in its own body.
#
# A page cites every non-obvious claim inline (`(→ sources/…)`, docs/schema.md), so the
# frontmatter list is a roll-up of those citations and nothing in the pipeline reads it.
# Written by hand it drifts, and silently: measured over a 180-page vault, 9 % of its
# entries named a source no claim cited any more, 32 % of pages disagreed with their own
# bodies, and the disagreement ran both ways. It is generated for the same reason index.md
# and brief.md are — a generated file cannot drift from the pages.
#
# It is also bounded. One page carried 201 distinct citations and spent 17 KB of its 100 KB
# on the list, which is provenance crowding out the content it is provenance for. The
# frontmatter keeps the most recent CAP entries, `sources_cited:` records how many there
# are, and the full set is the body's own citations — the copy that was authoritative all
# along.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CAP=${BRAIN_SOURCES_CAP:-12}
vp="${1:?usage: provenance.sh <vault-path> [page ...]}"; shift || true
cd "$vp"

pages=""
if [ $# -gt 0 ]; then
  pages=$(printf '%s\n' "$@")
else
  # Wiki pages only: sources/ is append-only, and the generated files carry no frontmatter.
  pages=$(find . -maxdepth 2 -name '*.md' ! -path './sources/*' ! -name index.md \
    ! -name brief.md ! -name log.md ! -name CLAUDE.md ! -name AGENTS.md \
    | sed 's|^\./||' | sort)
fi

changed=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  [ -f "$p" ] || continue
  grep -q '^sources:' "$p" || continue

  # Body only. A path inside the frontmatter is the roll-up being rebuilt, not evidence.
  # The class excludes delimiters rather than listing allowed characters: most digest
  # filenames are Chinese, and an ASCII class silently truncated every one of them.
  cited=$(awk 'BEGIN { c = 0 } /^---$/ { c++; next } c >= 2' "$p" \
    | grep -oE 'sources/[^][ ,)]+\.md' | sort -u || true)
  total=$(printf '%s\n' "$cited" | grep -c . || true)

  # Newest first by the date every source filename starts with, so a reader scanning the
  # frontmatter sees what the page most recently drew on.
  # `|| true`: a page with no citation yet — a new one, written before its first claim —
  # must get an empty list, not take finish.sh down with it through pipefail.
  keep=$(printf '%s\n' "$cited" | grep . \
    | awk -F/ '{ print $NF "\t" $0 }' | sort -r | cut -f2- \
    | head -n "$CAP" | paste -sd, - | sed 's/,/, /g' || true)

  tmp="$p.provenance.$$"
  awk -v ns="sources: [${keep}]" -v tot="$total" '
    BEGIN { c = 0 }
    /^---$/ { c++; print; next }
    c == 1 {
      if ($0 ~ /^sources:/)       { print ns; print "sources_cited: " tot; next }
      if ($0 ~ /^sources_cited:/) { next }   # rewritten beside sources:, never twice
    }
    { print }
  ' "$p" > "$tmp"

  if cmp -s "$p" "$tmp"; then
    rm -f "$tmp"
  else
    mv "$tmp" "$p"
    changed=$((changed + 1))
  fi
done <<EOF
$pages
EOF

printf 'provenance: %s page(s) rewritten\n' "$changed"
