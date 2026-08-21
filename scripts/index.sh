#!/usr/bin/env bash
# Regenerate <vault>/index.md from the wiki pages: one line per page —
# [[dir/page]] — first sentence of the page body — grouped by directory.
#
#   index.sh <vault-path>
set -euo pipefail
vp="${1:?vault path}"
cd "$vp"

summary() { # first non-empty, non-heading line after the frontmatter, cut at the first sentence end
  awk 'BEGIN{fm=0} NR==1 && /^---$/ {fm=1; next} fm==1 && /^---$/ {fm=2; next} fm==2 && !/^\s*$/ && !/^#/ && !/^<!--/ {print; exit}' "$1" \
    | sed -E 's/[[:space:]]+/ /g; s/^ //; s/(\.|。)( |$).*/\1/' | awk '{ if (length($0) > 220) print substr($0, 1, 219) "…"; else print }'
}

{
  printf '# Index\n'
  for d in $(find . -maxdepth 1 -mindepth 1 -type d ! -name sources ! -name '.*' | sed 's|^\./||' | sort); do
    pages=$(find "$d" -maxdepth 1 -name '*.md' | sort)
    [ -n "$pages" ] || continue
    printf '\n## %s\n' "$d"
    printf '%s\n' "$pages" | while IFS= read -r f; do
      printf -- '- [[%s]] — %s\n' "${f%.md}" "$(summary "$f")"
    done
  done
} > index.md
