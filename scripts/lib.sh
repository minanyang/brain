#!/usr/bin/env bash
# Shared helpers for Brain scripts. Source this file; do not execute it.
# Requires: bash 3.2+, jq, git.

BRAIN_CONFIG="${BRAIN_CONFIG:-$HOME/.brain/config.json}"
BRAIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

expand_home() { printf '%s' "${1/#\~/$HOME}"; }

config_exists() { [ -f "$BRAIN_CONFIG" ]; }

# config_get <jq-filter> [default]
config_get() {
  local v
  v=$(jq -r "$1 // empty" "$BRAIN_CONFIG" 2>/dev/null || true)
  printf '%s' "${v:-${2:-}}"
}

# Transcript roots, one per line, expanded.
transcript_roots() {
  jq -r 'if (.transcripts // []) == [] then "~/.claude/projects" else .transcripts[] end' "$BRAIN_CONFIG" 2>/dev/null \
    | while read -r r; do printf '%s\n' "$(expand_home "$r")"; done
}

# glob_match <glob> <path>: bash pattern match where ** means any depth.
glob_match() {
  local g p
  g=$(expand_home "$1"); p="$2"
  # "~/Repos/acme/**" matches the directory itself as well as anything below it.
  case "$g" in */'**') [ "$p" = "${g%/**}" ] && return 0 ;; esac
  g="${g//\*\*/__DS__}"; g="${g//\*/[^/]*}"; g="${g//__DS__/*}"
  [[ "$p" == $g ]]
}

# route <cwd>: print the name of the first vault whose include matches and
# exclude does not. Prints nothing (exit 1) when no vault matches or when the
# cwd is inside a vault.
route() {
  local cwd="$1" n path g i count hit
  config_exists || return 1
  while IFS=$'\t' read -r n path; do
    path=$(expand_home "$path")
    case "$cwd" in "$path"|"$path"/*) return 1 ;; esac
  done < <(jq -r '.vaults[] | [.name, .path] | @tsv' "$BRAIN_CONFIG")
  count=$(jq '.vaults | length' "$BRAIN_CONFIG")
  # Globs are read one per line, never word-split, so the shell cannot expand them against the filesystem.
  for ((i = 0; i < count; i++)); do
    hit=0
    while IFS= read -r g; do
      [ -n "$g" ] && glob_match "$g" "$cwd" && { hit=1; break; }
    done < <(jq -r ".vaults[$i].include[]?" "$BRAIN_CONFIG")
    [ $hit = 1 ] || continue
    while IFS= read -r g; do
      [ -n "$g" ] && glob_match "$g" "$cwd" && { hit=0; break; }
    done < <(jq -r ".vaults[$i].exclude[]?" "$BRAIN_CONFIG")
    [ $hit = 1 ] && { jq -r ".vaults[$i].name" "$BRAIN_CONFIG"; return 0; }
  done
  return 1
}

# vault_path <name>
vault_path() { expand_home "$(jq -r --arg n "$1" '.vaults[] | select(.name == $n) | .path' "$BRAIN_CONFIG")"; }

# lock <vault-path>: atomic mkdir lock. Returns 1 if held. Stale after 1h.
lock() {
  local d="$1/.state/lock"
  mkdir -p "$1/.state"
  if mkdir "$d" 2>/dev/null; then echo $$ > "$d/pid"; return 0; fi
  if [ -n "$(find "$d" -maxdepth 0 -mmin +60 2>/dev/null)" ]; then
    unlock "$1"
    mkdir "$d" 2>/dev/null && { echo $$ > "$d/pid"; return 0; }
  fi
  return 1
}
unlock() { rm -f "$1/.state/lock/pid"; rmdir "$1/.state/lock" 2>/dev/null || true; }

log() { printf '[brain] %s\n' "$*" >&2; }

# lock_wait <vault-path> [seconds]: like lock, but wait up to N seconds (default 120).
lock_wait() {
  local i=0 max="${2:-120}"
  until lock "$1"; do
    i=$((i+1)); [ "$i" -ge "$max" ] && return 1
    sleep 1
  done
}
