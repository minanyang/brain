#!/usr/bin/env bash
# SessionStart hook (startup only): if a vault's backlog has crossed its threshold,
# run one ingest in the background. Distilling already happens on its own; without
# this the digests wait for someone to notice the session-start reminder.
set -u
[ "${BRAIN_INNER:-}" = 1 ] && exit 0
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -f "${BRAIN_CONFIG:-$HOME/.brain/config.json}" ] || exit 0
cat > /dev/null   # drain stdin
mkdir -p "$HOME/.brain/logs" "$HOME/.brain/.state"

# One ingest at a time across every session on this machine. auto-ingest.sh also
# refuses a vault another writer holds, but that check happens after the fork, so
# without this lock a burst of session starts pays for several model calls that
# then all find the vault busy. A run abandoned mid-flight frees the lock after 2 h.
d="$HOME/.brain/.state/auto-ingest"
[ -n "$(find "$d" -maxdepth 0 -mmin +120 2>/dev/null)" ] && rmdir "$d" 2>/dev/null
mkdir "$d" 2>/dev/null || exit 0

nohup bash -c 'trap "rmdir \"$1\" 2>/dev/null" EXIT; "$2" --quiet' \
  _ "$d" "$root/scripts/auto-ingest.sh" >> "$HOME/.brain/logs/ingest.log" 2>&1 < /dev/null &
disown 2>/dev/null || true
exit 0
