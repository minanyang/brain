#!/usr/bin/env bash
# Run one unattended ingest when the backlog warrants it.
#
# Distilling is automatic; integrating was not, so digests piled up in sources/
# while the pages the agent actually reads stayed behind them. A measurement on
# 2026-09-20 put the median digest-to-ingest lag at under a day but p90 at 102 h,
# with 49 digests never ingested — and two sessions that re-derived an answer
# already sitting in an un-ingested digest. This closes that tail.
#
# It is opt-in (`auto_ingest.enabled`), because it spends model budget without
# being asked. It never resolves a conflict: nobody is there to decide, so
# contradictions stay `[open]` for the next human-driven run.
#
# usage: auto-ingest.sh [--quiet] [--vault <name>] [--force] [--dry-run]
set -u
[ "${BRAIN_INNER:-}" = 1 ] && exit 0   # never recurse out of our own inner session
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
config_exists || exit 0

quiet= vault_name= force= dry_run=
while [ $# -gt 0 ]; do
  case "$1" in
    --quiet) quiet=1 ;;
    --vault) vault_name="${2:?}"; shift ;;
    --force) force=1 ;;
    --dry-run) dry_run=1 ;;
    --help|-h) echo "usage: auto-ingest.sh [--quiet] [--vault <name>] [--force] [--dry-run]"; exit 0 ;;
    *) log "unknown argument: $1"; exit 2 ;;
  esac
  shift
done
say() { [ -n "$quiet" ] || log "$*"; }

[ "$(config_get '.auto_ingest.enabled' false)" = true ] || [ -n "$force" ] || exit 0

min_pending=$(config_get '.auto_ingest.min_pending' 20)
max_age_hours=$(config_get '.auto_ingest.max_age_hours' 24)
min_interval_hours=$(config_get '.auto_ingest.min_interval_hours' 6)
model=$(config_get '.auto_ingest.model' sonnet)
# How long a lease may sit untouched before a later run treats it as abandoned. Only
# reached after the inner session has exited, so it bounds recovery, not the run itself.
stale_lease_minutes=$(config_get '.auto_ingest.stale_lease_minutes' 60)
case "$min_pending$max_age_hours$min_interval_hours$stale_lease_minutes" in
  *[!0-9]*) log "auto_ingest thresholds must be integers"; exit 2 ;;
esac

# Which vaults to consider: the named one, or every configured vault.
vaults=$(jq -r --arg n "$vault_name" \
  '.vaults[] | select($n == "" or .name == $n) | [.name, .path] | @tsv' "$BRAIN_CONFIG")
[ -n "$vaults" ] || { log "no such vault: ${vault_name:-<any>}"; exit 2; }

mkdir -p "$HOME/.brain/.state" "$HOME/.brain/logs"

while IFS=$'\t' read -r name path; do
  [ -n "$name" ] || continue
  vp=$(expand_home "$path")
  [ -d "$vp/.git" ] || { say "$name: not a vault checkout, skipping"; continue; }

  pending=$(pending_sources "$vp")
  count=$(printf '%s' "$pending" | grep -c . || true)
  [ "$count" -gt 0 ] || { say "$name: nothing pending"; continue; }

  # `find -mmin` rather than `stat`, whose format flags differ between BSD and GNU.
  stale=0
  if [ -n "$pending" ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      [ -n "$(find "$f" -maxdepth 0 -mmin "+$((max_age_hours * 60))" 2>/dev/null)" ] && { stale=1; break; }
    done <<EOF
$pending
EOF
  fi

  if [ -z "$force" ] && [ "$count" -lt "$min_pending" ] && [ "$stale" = 0 ]; then
    say "$name: $count pending, none older than ${max_age_hours}h — below threshold"
    continue
  fi

  # A run per session start would bill for the same backlog repeatedly; the stamp is
  # touched before the model call, so a crashed run still waits out the interval.
  stamp="$HOME/.brain/.state/auto-ingest-$name.stamp"
  if [ -z "$force" ] && [ -f "$stamp" ] \
     && [ -n "$(find "$stamp" -maxdepth 0 -mmin "-$((min_interval_hours * 60))" 2>/dev/null)" ]; then
    say "$name: ingested within the last ${min_interval_hours}h, waiting"
    continue
  fi

  # Someone is already editing this vault — a session running /brain:ingest, or another
  # host. Leave it; the next session start sees the same backlog.
  if [ -d "$vp/.state/lock" ]; then
    say "$name: vault is busy, skipping"
    continue
  fi

  if [ -n "$dry_run" ]; then
    log "$name: would ingest $count pending source(s) with $model"
    continue
  fi

  say "$name: ingesting $count pending source(s) with $model"
  : > "$stamp"

  # Built in a file rather than a $(...) around a heredoc, which bash 3.2 mis-parses.
  pf=$(mktemp "${TMPDIR:-/tmp}/brain-ingest-prompt.XXXXXXXX")
  cat > "$pf" <<EOF
You are running UNATTENDED, started by a hook. No human will read your output or answer a
question, so never ask one and never wait for input.

Follow the instructions below, which are Brain's ingest skill, with these overrides:
- Work on vault '$name' at $vp. Pass --vault '$name' to resolve-vault.sh and ingest-prep.sh.
- Step 7 (conflicts): skip it. Leave every conflict [open], including ones that look like
  questions of fact: this run has no git or cloud access to verify against, you have no one
  to ask, and a guess recorded as a decision cannot be found later.
- Stop after the batch that empties the backlog, or after 4 batches, whichever comes first.
  Whatever you leave pending, the next run picks up.
- If the vault is busy or a script fails twice, release the lease and stop. Do not improvise
  another write path: finish.sh is the only sanctioned one.
- End with one line naming sources ingested, pages created and updated, and conflicts left open.

EOF
  sed -e '1{/^---$/!q' -e '}' -e '1,/^---$/d' "$BRAIN_ROOT/skills/ingest/SKILL.md" \
    | sed "s|\${CLAUDE_PLUGIN_ROOT}|$BRAIN_ROOT|g" >> "$pf"
  prompt=$(cat "$pf")
  rm -f "$pf"

  # Tools mirror the skill's own allowed-tools: the four scripts it runs, and nothing
  # else through Bash. An unattended run must not be able to reach git directly.
  out=$(mktemp "${TMPDIR:-/tmp}/brain-auto-ingest.XXXXXXXX")
  BRAIN_INNER=1 claude -p "$prompt" \
      --model "$model" \
      --no-session-persistence \
      --output-format text \
      --add-dir "$vp" \
      --allowedTools Read Write Edit Glob Grep Task Agent \
        "Bash($BRAIN_ROOT/scripts/resolve-vault.sh *)" \
        "Bash($BRAIN_ROOT/scripts/write-lock.sh *)" \
        "Bash($BRAIN_ROOT/scripts/ingest-prep.sh *)" \
        "Bash($BRAIN_ROOT/scripts/finish.sh *)" \
    </dev/null > "$out" 2>&1
  status=$?
  sed "s/^/[$name] /" "$out"
  rm -f "$out"
  [ "$status" = 0 ] || log "$name: ingest exited $status"

  # A crashed inner session can leave its lease behind and block every later run.
  if [ -f "$vp/.state/lock/owner" ] \
     && [ -n "$(find "$vp/.state/lock/owner" -maxdepth 0 -mmin "+$stale_lease_minutes" 2>/dev/null)" ]; then
    log "$name: abandoned lease older than ${stale_lease_minutes}m, clearing"
    rm -f "$vp/.state/lock/owner" "$vp/.state/lock/pid"
    rmdir "$vp/.state/lock" 2>/dev/null || true
  fi
done <<EOF
$vaults
EOF
