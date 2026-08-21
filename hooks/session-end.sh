#!/usr/bin/env bash
# SessionEnd hook: distill the transcript named in the payload, in the background.
# SessionEnd hooks get ~1.5 s, so this only forks and returns.
set -u
[ "${BRAIN_INNER:-}" = 1 ] && exit 0
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
transcript=$(jq -r '.transcript_path // empty' 2>/dev/null)
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0
mkdir -p "$HOME/.brain/logs"
nohup "$root/scripts/distill.sh" --quiet "$transcript" >> "$HOME/.brain/logs/distill.log" 2>&1 < /dev/null &
disown 2>/dev/null || true
exit 0
