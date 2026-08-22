#!/usr/bin/env bash
# Write a ref — an article, document, or note the human hands over — into sources/refs/.
#
#   ref.sh --vault <path> --title "<title>" --why "<one line>" --body-file <file> [--url <url>] [--added YYYY-MM-DD]
#
# Builds the file name from the date and title, writes the frontmatter from
# templates/ref.md, runs the secret gate on the body, and prints the path.
# Does not commit; finish.sh --op clip does.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

vp="" title="" why="" body="" url="" added=$(date +%Y-%m-%d)
while [ $# -gt 0 ]; do
  case "$1" in
    --vault) vp=$(expand_home "$2"); shift ;;
    --title) title="$2"; shift ;;
    --why) why="$2"; shift ;;
    --body-file) body="$2"; shift ;;
    --url) url="$2"; shift ;;
    --added) added="$2"; shift ;;
  esac
  shift
done
[ -d "$vp" ] && [ -n "$title" ] && [ -n "$why" ] && [ -f "$body" ] || {
  echo "usage: ref.sh --vault <path> --title <t> --why <w> --body-file <f> [--url <u>] [--added <date>]" >&2; exit 2; }

if ! "$BRAIN_ROOT/scripts/secret-gate.sh" < "$body"; then
  echo "secret gate blocked the ref; remove the credential from the body and retry" >&2; exit 1
fi

slug=$(jq -rn --arg t "$title" '$t | ascii_downcase | gsub("[^\\p{L}\\p{N}]+"; "-") | gsub("^-+|-+$"; "") | .[0:40] | gsub("-+$"; "")')
[ -n "$slug" ] || slug="ref"
mkdir -p "$vp/sources/refs"
path="sources/refs/$added-$slug.md"
i=2; while [ -e "$vp/$path" ]; do path="sources/refs/$added-$slug-$i.md"; i=$((i+1)); done

yq() { printf '%s' "$1" | sed 's/"/\\"/g'; }   # quote a YAML scalar
{
  printf -- '---\nurl: "%s"\ntitle: "%s"\nadded: %s\nwhy: "%s"\ningested: false\n---\n\n' \
    "$(yq "${url:-pasted}")" "$(yq "$title")" "$added" "$(yq "$why")"
  cat "$body"
  printf '\n'
} > "$vp/$path"
printf '%s\n' "$path"
