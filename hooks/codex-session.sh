#!/usr/bin/env bash
# Codex SessionStart / SessionEnd adapter, invoked by the installed runtime shim.
set -euo pipefail
[ "${BRAIN_INNER:-}" = 1 ] && exit 0
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/lib.sh"
config_exists || exit 0
event="${1:?start or end}"
payload=$(cat)
data=$(dirname "$BRAIN_CONFIG")
mkdir -p "$data/logs"
case "$event" in
  start)
    cwd=$(jq -r '.cwd // empty' <<<"$payload")
    "$BRAIN_ROOT/scripts/status.sh" "${cwd:-$PWD}" | jq '
      .hookSpecificOutput.additionalContext |= gsub("/brain:"; "$brain-")'
    # Revisit only sessions active since installation, never an unsolicited full backfill.
    since=$(config_get '.codex_enabled_at' "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
    nohup "$BRAIN_ROOT/scripts/distill.sh" --all --host codex --provider codex --quiet --since "$since" \
      >>"$data/logs/codex-distill.log" 2>&1 </dev/null &
    ;;
  end)
    transcript=$(jq -r '.transcript_path // empty' <<<"$payload")
    [ -n "$transcript" ] && [ -f "$transcript" ] || exit 0
    nohup "$BRAIN_ROOT/scripts/distill.sh" --host codex --provider codex --quiet "$transcript" \
      >>"$data/logs/codex-distill.log" 2>&1 </dev/null &
    ;;
  *) log "unknown Codex hook event: $event"; exit 2 ;;
esac
disown 2>/dev/null || true
