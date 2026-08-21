#!/usr/bin/env bash
# SessionStart hook (sync): pending-digest reminder, schema when inside a vault,
# brief when enabled. Reads files only.
set -u
[ "${BRAIN_INNER:-}" = 1 ] && exit 0
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
cwd=$(jq -r '.cwd // empty' 2>/dev/null)
exec "$root/scripts/status.sh" "${cwd:-$PWD}"
