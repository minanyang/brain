#!/usr/bin/env bash
# Codex SessionStart / UserPromptSubmit / SessionEnd adapter, invoked by the installed runtime
# shim.
#
# Retrieval reaches Codex because the ranking is a shell script rather than part of the Claude
# Code hooks module: `scripts/search.sh` is the same implementation both hosts run, so the
# measured 1-in-56 organic-invocation problem is answered the same way on each, and the two
# cannot drift apart.
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
    # Passed through so a Codex session that lost its context gets the pages it already cited,
    # the same as on Claude Code. Both are optional: a host that sends neither simply gets the
    # brief, which is what every Codex session got before.
    src=$(jq -r '.source // empty' <<<"$payload")
    tr=$(jq -r '.transcript_path // empty' <<<"$payload")
    "$BRAIN_ROOT/scripts/status.sh" "${cwd:-$PWD}" --source "${src:-}" --transcript "${tr:-}" | jq '
      .hookSpecificOutput.additionalContext |= gsub("/brain:"; "$brain-")'
    # Revisit only sessions active since installation, never an unsolicited full backfill.
    since=$(config_get '.codex_enabled_at' "$(date -u +%Y-%m-%dT%H:%M:%SZ)")
    nohup "$BRAIN_ROOT/scripts/distill.sh" --all --host codex --provider codex --quiet --since "$since" \
      >>"$data/logs/codex-distill.log" 2>&1 </dev/null &
    ;;
  prompt)
    # The same script Claude Code runs on the same event name, with the same gate, floor and
    # budget ladder: a question is a question whichever host typed it, and a second copy of
    # those thresholds would drift from the measurements that set them. It fails closed —
    # anything unexpected and it prints nothing, so the prompt enters untouched.
    printf '%s' "$payload" | "$BRAIN_ROOT/hooks/prompt-search.sh" 2>/dev/null || true
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
