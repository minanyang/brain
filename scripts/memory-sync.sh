#!/usr/bin/env bash
# Snapshot the agent's built-in memory files into the vault they route to, as sources.
#
#   memory-sync.sh [--quiet]
#
# Claude Code keeps per-project memory under <transcript root>/<project>/memory/*.md.
# Each project directory is routed like a session, by the cwd recorded in its newest
# transcript; one with no transcript left cannot be routed and is skipped. A memory
# file whose content changed since the last sync (git blob hash, kept per vault in
# .state/memory.json) is copied verbatim into sources/memory/<date>-<name>.md with
# ingested: false, after the secret gate, and committed under the vault lock. Nothing
# is ever written back into the memory directory.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
config_exists || exit 0
quiet=0; [ "${1:-}" = --quiet ] && quiet=1
say() { [ $quiet = 1 ] || log "$@"; }

today=$(date +%Y-%m-%d)
written=0 written_in=""
yq() { printf '%s' "$1" | sed 's/"/\\"/g'; }   # quote a YAML scalar

while IFS= read -r root; do
  for mdir in "$root"/*/memory; do
    [ -d "$mdir" ] || continue
    pdir=$(dirname "$mdir")
    newest=$(ls -t "$pdir"/*.jsonl 2>/dev/null | head -1 || true)
    [ -n "$newest" ] || continue
    # jq reads the 50 lines whole: a `| head -1` after it would die of SIGPIPE under pipefail.
    cwd=$(head -n 50 "$newest" | jq -rn '[inputs | select(type == "object" and .cwd != null) | .cwd] | first // empty' 2>/dev/null || true)
    [ -n "$cwd" ] || continue
    vault=$(route "$cwd") || continue
    vp=$(vault_path "$vault")
    [ -d "$vp" ] || continue
    state="$vp/.state/memory.json"
    mkdir -p "$vp/.state" "$vp/sources/memory"
    [ -f "$state" ] || echo '{}' > "$state"

    for f in "$mdir"/*.md; do
      [ -f "$f" ] || continue
      case "$f" in */MEMORY.md) continue ;; esac   # the index, not a memory
      hash=$(git hash-object "$f")
      [ "$(jq -r --arg f "$f" '.[$f] // empty' "$state")" = "$hash" ] && continue
      if ! "$BRAIN_ROOT/scripts/secret-gate.sh" < "$f" 2>/dev/null; then
        log "secret gate blocked memory file $f"; continue
      fi
      name=$(grep -m1 '^name:' "$f" | cut -d' ' -f2- | sed 's/^"//; s/"$//' || true)
      [ -n "$name" ] || name=$(basename "$f" .md)
      slug=$(jq -rn --arg t "$name" '$t | ascii_downcase | gsub("[^\\p{L}\\p{N}]+"; "-") | gsub("^-+|-+$"; "") | .[0:40] | gsub("-+$"; "")')
      [ -n "$slug" ] || slug=memory
      lock_wait "$vp" || { log "vault $vault stayed locked for 2 minutes, giving up on $f"; continue; }
      path="sources/memory/$today-$slug.md"
      i=2; while [ -e "$vp/$path" ]; do path="sources/memory/$today-$slug-$i.md"; i=$((i+1)); done
      {
        printf -- '---\nmemory: %s\nproject: %s\nadded: %s\ntitle: "%s"\ningested: false\n---\n\n' \
          "${f/#$HOME/~}" "${cwd/#$HOME/~}" "$today" "$(yq "$name")"
        cat "$f"; printf '\n'
      } > "$vp/$path"
      jq --arg f "$f" --arg h "$hash" '.[$f] = $h' "$state" > "$state.tmp" && mv "$state.tmp" "$state"
      unlock "$vp"
      written=$((written+1)); case " $written_in " in *" $vault "*) ;; *) written_in="$written_in $vault" ;; esac
      say "memory → $vault/$path"
    done
  done
done < <(transcript_roots)

for v in $written_in; do
  vp=$(vault_path "$v")
  lock_wait "$vp" || { log "could not lock $v to commit; memory snapshots are written but uncommitted"; continue; }
  printf '## [%s] memory | %s file(s)\n' "$today" "$(git -C "$vp" status --porcelain -uall sources/memory/ | wc -l | tr -d ' ')" >> "$vp/log.md"
  git -C "$vp" add sources/memory/ log.md >/dev/null 2>&1 && git -C "$vp" commit -q -m "memory: $today" >/dev/null 2>&1 || true
  unlock "$vp"
done
say "done: $written memory file(s) snapshotted"
