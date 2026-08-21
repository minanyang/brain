#!/usr/bin/env bash
# Gather everything an ingest run needs and print it as markdown.
#
#   ingest-prep.sh [--vault <name>] [--batch N] [--cwd <dir>]
#
# Sections: the vault and its page types, human edits since the last ingest
# (git diff against the brain/last-ingest tag, working tree included, wiki
# directories only), the next N pending sources (ingested: false, oldest first)
# with the total still waiting, and the current index.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
config_exists || { echo "no config at $BRAIN_CONFIG — run /brain:init first" >&2; exit 1; }

vault="" batch=15 cwd="$PWD"
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) vault="$2"; shift ;;
    --batch) batch="$2"; shift ;;
    --cwd) cwd="$2"; shift ;;
  esac
  shift
done

if [ -z "$vault" ]; then
  # inside a vault → that vault; else the vault the cwd routes to
  while IFS=$'\t' read -r n p; do
    p=$(expand_home "$p"); case "$cwd" in "$p"|"$p"/*) vault="$n" ;; esac
  done < <(jq -r '.vaults[] | [.name, .path] | @tsv' "$BRAIN_CONFIG")
  [ -n "$vault" ] || vault=$(route "$cwd") || { echo "no vault for $cwd; pass --vault <name>" >&2; exit 1; }
fi
vp=$(vault_path "$vault")
[ -d "$vp" ] || { echo "vault $vault missing at $vp" >&2; exit 1; }
cd "$vp"

# Wiki directories: everything except sources/, the three special files, and dotfiles.
wiki_dirs=$(find . -maxdepth 1 -mindepth 1 -type d ! -name sources ! -name '.*' | sed 's|^\./||' | sort | tr '\n' ' ')

printf '# Ingest prep — vault %s\n\npath: %s\nwiki directories: %s\n\n' "$vault" "$vp" "$wiki_dirs"

printf '## Page types\n\n'
printf 'Defaults: me (me/), person (people/), project (projects/), decision (decisions/), topic (topics/).\n'
if grep -q '^## Page types' CLAUDE.md 2>/dev/null; then
  printf 'Declared in CLAUDE.md:\n'
  awk '/^## Page types/{f=1; next} /^## /{f=0} f' CLAUDE.md | grep -v '^\s*$' | grep -v 'none yet' || true
fi
printf '\n'

printf '## Human edits since last ingest\n\n'
if git rev-parse -q --verify brain/last-ingest >/dev/null 2>&1; then
  diff=$(git diff brain/last-ingest -- . ':(exclude)sources' ':(exclude)log.md' ':(exclude)index.md' ':(exclude)brief.md' ':(exclude).state' 2>/dev/null || true)
  untracked=$(git ls-files --others --exclude-standard -- $wiki_dirs 2>/dev/null || true)
  if [ -z "$diff" ] && [ -z "$untracked" ]; then printf '(none)\n'; else
    printf 'These hunks were written by a human. They outrank every source below; keep every claim they add, cite it as (→ human, %s).\n\n```diff\n%s\n```\n' "$(date +%Y-%m-%d)" "$diff"
    [ -n "$untracked" ] && { printf '\nNew pages added by hand:\n'; printf '%s\n' "$untracked" | sed 's/^/- /'; }
  fi
else
  printf '(first ingest — no brain/last-ingest tag yet)\n'
fi
printf '\n'

pending=$(grep -l '^ingested: false' sources/*/*.md 2>/dev/null | sort || true)
total=$(printf '%s' "$pending" | grep -c . || true)
printf '## Pending sources (%s waiting, this batch: up to %s, oldest first)\n\n' "$total" "$batch"
if [ "$total" -eq 0 ]; then printf '(none)\n'; else
  printf '%s\n' "$pending" | head -n "$batch" | while IFS= read -r f; do
    t=$(grep -m1 '^title:' "$f" | cut -d' ' -f2- || true); d=$(grep -m1 '^date:\|^added:' "$f" | cut -d' ' -f2 || true)
    printf -- '- %s — %s (%s, %s bytes)\n' "$f" "$t" "$d" "$(wc -c < "$f" | tr -d ' ')"
  done
fi
printf '\n'

printf '## Current index.md\n\n'
cat index.md
printf '\n'
