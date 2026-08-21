#!/usr/bin/env bash
# SessionStart hook (startup only): distill, in the background, any transcript
# from the last 7 days that ended without a clean SessionEnd.
set -u
[ "${BRAIN_INNER:-}" = 1 ] && exit 0
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -f "${BRAIN_CONFIG:-$HOME/.brain/config.json}" ] || exit 0
cat > /dev/null   # drain stdin
mkdir -p "$HOME/.brain/logs"
nohup "$root/scripts/distill.sh" --quiet --all --days 7 >> "$HOME/.brain/logs/distill.log" 2>&1 < /dev/null &
disown 2>/dev/null || true
exit 0
