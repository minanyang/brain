#!/usr/bin/env bash
# SessionStart hook (sync): pending-digest reminder, schema when inside a vault,
# brief when enabled, and after a compaction the pages this session already read.
# Reads files only.
set -u
[ "${BRAIN_INNER:-}" = 1 ] && exit 0
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
in=$(cat)
cwd=$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null)
# `source` and `transcript_path` are what let status.sh tell a fresh start from a conversation
# that lost its context. This hook is the only place they are available: PreCompact can block a
# compaction but cannot add anything to it, and PostCompact cannot either — the documented way
# to put something in front of the agent after a compaction is this event, with source=compact.
src=$(printf '%s' "$in" | jq -r '.source // empty' 2>/dev/null)
tr=$(printf '%s' "$in" | jq -r '.transcript_path // empty' 2>/dev/null)
exec "$root/scripts/status.sh" "${cwd:-$PWD}" --source "${src:-}" --transcript "${tr:-}"
