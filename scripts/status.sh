#!/usr/bin/env bash
# status.sh <cwd> → SessionStart context as JSON on stdout (nothing if idle).
#
# Reads only files, never the model. Emits:
#   - the default schema, when cwd is inside a vault
#   - one reminder line, when the routed vault has digests not yet ingested
#   - the routed vault's brief.md, when inject_brief is true
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
config_exists || exit 0
cwd="${1:-$PWD}"

ctx=""
# Inside a vault: inject the schema so the agent knows how the vault is organised.
while IFS=$'\t' read -r n p; do
  p=$(expand_home "$p")
  case "$cwd" in "$p"|"$p"/*)
    ctx="You are inside the Brain vault '$n'. The default schema follows; the vault's CLAUDE.md overrides it."$'\n\n'"$(cat "$BRAIN_ROOT/docs/schema.md")"
    vault="$n" ;;
  esac
done < <(jq -r '.vaults[] | [.name, .path] | @tsv' "$BRAIN_CONFIG")

[ -n "${vault:-}" ] || vault=$(route "$cwd") || vault=""
if [ -n "$vault" ]; then
  vp=$(vault_path "$vault")
  pending_files=$(grep -l '^ingested: false' "$vp"/sources/sessions/*.md 2>/dev/null || true)
  pending=$(printf '%s' "$pending_files" | grep -c . || true)
  if [ "$pending" -gt 0 ]; then
    since=$(printf '%s\n' "$pending_files" | xargs -n1 basename | sort | head -1 | cut -c1-10)
    line="[brain] $pending source(s) pending in vault '$vault' since $since"
  fi
  wiki_dirs=$(find "$vp" -maxdepth 1 -mindepth 1 -type d ! -name sources ! -name '.*')
  open=$( { [ -n "$wiki_dirs" ] && grep -rh '^- \[open\]' $wiki_dirs 2>/dev/null; } | wc -l | tr -d ' ' || true)
  [ "$open" -gt 0 ] && line="${line:-[brain] vault '$vault'}${line:+,} $open open conflict(s)"
  if [ -n "${line:-}" ]; then
    ctx="${ctx:+$ctx$'\n\n'}$line — run /brain:ingest"
  fi
  if [ "$(config_get '.inject_brief' false)" = true ] && [ -s "$vp/brief.md" ]; then
    if "$BRAIN_ROOT/scripts/secret-gate.sh" < "$vp/brief.md" 2>/dev/null; then
      ctx="${ctx:+$ctx$'\n\n'}Brief from vault '$vault':"$'\n'"$(cat "$vp/brief.md")"
    fi
  fi
fi

[ -n "$ctx" ] || exit 0
jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
