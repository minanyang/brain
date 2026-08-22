#!/usr/bin/env bash
# SessionStart hook (startup only): distill, in the background, any transcript
# from the last 7 days that ended without a clean SessionEnd.
set -u
[ "${BRAIN_INNER:-}" = 1 ] && exit 0
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -f "${BRAIN_CONFIG:-$HOME/.brain/config.json}" ] || exit 0
cat > /dev/null   # drain stdin
mkdir -p "$HOME/.brain/logs" "$HOME/.brain/.state"

# One catchup at a time. Each run walks every transcript under the roots, so a
# second concurrent scan only repeats the first one's work — four were seen running
# together after a handful of sessions started in quick succession. Whatever this
# run skips, the next session's catchup still sees. An hour-old lock is abandoned.
d="$HOME/.brain/.state/catchup"
[ -n "$(find "$d" -maxdepth 0 -mmin +60 2>/dev/null)" ] && rmdir "$d" 2>/dev/null
mkdir "$d" 2>/dev/null || exit 0

nohup bash -c 'trap "rmdir \"$1\" 2>/dev/null" EXIT; "$2" --quiet --all --days 7' \
  _ "$d" "$root/scripts/distill.sh" >> "$HOME/.brain/logs/distill.log" 2>&1 < /dev/null &
disown 2>/dev/null || true
exit 0
