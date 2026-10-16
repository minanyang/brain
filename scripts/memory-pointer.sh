#!/usr/bin/env bash
# Point one of the agent's own memory notes at the vault page that now holds its subject.
#
#   memory-pointer.sh --note <path> --page <dir/page> [--page <dir/page>…] [--vault <name>]
#
# The agent reads its own `<transcript root>/<project>/memory/*.md` before anything else and
# treats what it finds there as sufficient. Measured on 2026-10-15 against a question whose
# answer was on a page checked that same day: five different session-start briefs reached the
# page in 0 of 19 runs, because every run read its own note first and stopped. One line in the
# note itself, naming the page, took it to 4 of 4 — so the pointer belongs where the agent
# already looks, not in a paragraph it reads once.
#
# The line is replaced, never duplicated: everything from the `<!-- brain:vault -->` marker to
# the end of the file belongs to this script, and `memory-sync.sh` strips that region before
# hashing or snapshotting a note, so a pointer never comes back into the vault as a fact and
# never makes an unchanged note look changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

MARKER='<!-- brain:vault -->'
note="" ; vault_arg="" ; pages=()
while [ $# -gt 0 ]; do
  case "$1" in
    --note) note="${2:-}"; shift 2 ;;
    --page) pages+=("${2:-}"); shift 2 ;;
    --vault) vault_arg="${2:-}"; shift 2 ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[ -n "$note" ] && [ ${#pages[@]} -gt 0 ] || { printf 'usage: memory-pointer.sh --note <path> --page <dir/page>…\n' >&2; exit 2; }

note="${note/#\~/$HOME}"
# Only the agent's own memory directory, so a mistyped path cannot rewrite a source or a page.
case "$note" in */memory/*.md) ;; *) printf 'not a memory note: %s\n' "$note" >&2; exit 2 ;; esac
[ -f "$note" ] || { log "memory note is gone, nothing to point: $note"; exit 0; }

# The note's own directory is not a working directory, so the vault is resolved from this
# process's cwd (an ingest's) or named outright, exactly as every other script resolves it.
vp=$("$(dirname "${BASH_SOURCE[0]}")/resolve-vault.sh" ${vault_arg:+--vault "$vault_arg"} | cut -f2)
[ -n "$vp" ] && [ -d "$vp" ] || { printf 'no vault resolved\n' >&2; exit 1; }

lines=""
for page in "${pages[@]}"; do
  page="${page%.md}"
  f="$vp/$page.md"
  [ -f "$f" ] || { log "no such page, skipping: $page"; continue; }
  # The page's own `updated:` is the honest date: it is when the claims were last established,
  # not when this pointer happened to be written.
  on=$(grep -m1 '^updated:' "$f" | cut -d' ' -f2- || true)
  # The page's own section headings, which is what makes the pointer worth following: told only
  # that a page holds "the current state of this subject", the agent read it in 1 of 4 runs and
  # went back to refusing; told what the page covers, in its own words, 4 of 4 (2026-10-16).
  # The three housekeeping sections are left out — they name no subject.
  # A page with no sections at all is normal for a short one, and grep's exit 1 must not end
  # the run: the pointer is still worth writing without the "It covers" clause.
  covers=$( { grep '^## ' "$f" || true; } \
    | { grep -vE '^## (Open threads|Conflicts|Rejected)$' || true; } \
    | sed 's/^## //' | head -8 | paste -sd ';' - | sed 's/;/; /g')
  lines="$lines"$'\n'"**Vault:** \`${f/#$HOME/~}\` — checked and dated, last ${on:-undated} — is where the present state of this subject is recorded.${covers:+ It covers: $covers.} Answer a question about any of that from the page, giving its date, before reaching for a live check or for this note."
done
[ -n "$lines" ] || exit 0

tmp=$(mktemp)
sed "/^$MARKER\$/,\$d" "$note" > "$tmp"
# A note that ended inside the old region must not lose its last blank line boundary.
printf '%s\n%s\n' "$MARKER" "${lines#$'\n'}" >> "$tmp"
mv "$tmp" "$note"

# Writing the pointer changes the note, which a sync would otherwise read as a human edit.
# memory-sync.sh hashes the file as it sits on disk, so re-stamping that hash here is what
# keeps this write from costing a snapshot. An entry that is not already there is left alone:
# that note has never been snapshotted and still has to be.
state="$vp/.state/memory.json"
if [ -f "$state" ] && [ "$(jq -r --arg f "$note" 'has($f)' "$state")" = true ]; then
  h=$(git hash-object "$note")
  jq --arg f "$note" --arg h "$h" '.[$f] = $h' "$state" > "$state.tmp" && mv "$state.tmp" "$state"
fi
log "pointed $(basename "$note") at ${#pages[@]} page(s)"
