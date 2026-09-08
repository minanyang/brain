#!/usr/bin/env bash
# SessionEnd hook: distill the transcript named in the payload, then snapshot changed
# memory files, in the background. SessionEnd hooks get ~1.5 s, so this only forks and returns.
set -u
[ "${BRAIN_INNER:-}" = 1 ] && exit 0
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
transcript=$(jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0
mkdir -p "$HOME/.brain/logs"
nohup bash -c '"$1" --quiet "$2"; "$3" --quiet' \
  _ "$root/scripts/distill.sh" "$transcript" "$root/scripts/memory-sync.sh" >> "$HOME/.brain/logs/distill.log" 2>&1 < /dev/null &
disown 2>/dev/null || true
exit 0
