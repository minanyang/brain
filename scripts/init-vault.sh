#!/usr/bin/env bash
# Create a vault and register it in ~/.brain/config.json.
#
#   init-vault.sh <path> [--name <name>] [--include <glob> ...]
#
# Name defaults to the directory's basename; include defaults to "~/**".
# New vaults are inserted at the front of the vault list so a specific vault
# added after a catch-all one takes precedence.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

path="" name="" includes=()
usage() { echo "usage: init-vault.sh <path> [--name <name>] [--include <glob> ...]" >&2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --name) name="$2"; shift ;;
    --include) shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do includes+=("$1"); shift; done; continue ;;
    -h|--help) usage; exit 0 ;;
    # An unrecognized flag must never be taken as the vault path: doing so once
    # created a vault at /tmp/--help and front-inserted a catch-all include.
    -*) echo "unknown option: $1" >&2; usage; exit 2 ;;
    *) path="$1" ;;
  esac
  shift
done
[ -n "$path" ] || { usage; exit 2; }
path=$(expand_home "$path")
case "$path" in /*) ;; *) path="$PWD/$path" ;; esac
[ -n "$name" ] || name=$(basename "$path")
[ ${#includes[@]} -gt 0 ] || includes=('~/**')

if config_exists && jq -e --arg n "$name" '.vaults[] | select(.name == $n)' "$BRAIN_CONFIG" >/dev/null; then
  echo "a vault named '$name' is already registered in $BRAIN_CONFIG" >&2; exit 1
fi

mkdir -p "$path"
cd "$path"
[ -d .git ] || git init -q
for d in sources/sessions sources/refs me people projects decisions topics; do mkdir -p "$d"; [ -e "$d/.gitkeep" ] || : > "$d/.gitkeep"; done
[ -e CLAUDE.md ] || cp "$BRAIN_ROOT/templates/vault/CLAUDE.md" CLAUDE.md
[ -e .gitignore ] || cp "$BRAIN_ROOT/templates/vault/gitignore" .gitignore
[ -e index.md ] || printf '# Index\n' > index.md
[ -e brief.md ] || : > brief.md
[ -e log.md ] || printf '## [%s] init | vault created\n' "$(date '+%Y-%m-%d')" > log.md

mkdir -p "$(dirname "$BRAIN_CONFIG")"
config_exists || printf '{\n  "transcripts": ["~/.claude/projects"],\n  "distill_model": "haiku",\n  "inject_brief": false,\n  "vaults": []\n}\n' > "$BRAIN_CONFIG"
entry=$(jq -n --arg n "$name" --arg p "${path/#$HOME/~}" --args '{name: $n, path: $p, include: $ARGS.positional}' "${includes[@]}")
jq --argjson e "$entry" '.vaults = [$e] + (.vaults // [])' "$BRAIN_CONFIG" > "$BRAIN_CONFIG.tmp" && mv "$BRAIN_CONFIG.tmp" "$BRAIN_CONFIG"

git add -A >/dev/null
git diff --cached --quiet || git commit -q -m "init: vault created"

cat <<EOF
vault '$name' at $path
registered in $BRAIN_CONFIG with include: ${includes[*]}
next: /brain:distill --all   (backfill; add --days 30 for a smaller first run, --jobs 4 to parallelize)
EOF
