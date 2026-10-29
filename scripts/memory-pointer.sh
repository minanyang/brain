#!/usr/bin/env bash
# Point one of the agent's own memory notes at the vault page that now holds its subject.
#
#   memory-pointer.sh --note <path> --page <dir/page> [--page <dir/page>…] [--vault <name>]
#
# The agent often opens its own `<transcript root>/<project>/memory/*.md` early and, when it does,
# treats what it finds there as sufficient. Measured on 2026-10-15 against a question whose
# answer was on a page checked that same day: five different session-start briefs reached the
# page in 1 of 19 runs, and the one hit came from a brief that named the page outright, which
# cannot ship (the other four: 0 of 15). One line in the note itself, naming the page, took it
# to 6 of 8 as this script writes it and 4 of 4 hand-written (2026-10-16), and every run that
# opened the note with the line in it reached the page — so the pointer belongs where the agent
# already looks, not in a paragraph it reads once. It cannot help a run that never opens the note.
#
# The line is replaced, never duplicated: everything from the `<!-- brain:vault -->` marker to
# the end of the file belongs to this script, and `memory-sync.sh` strips that region before
# hashing or snapshotting a note, so a pointer never comes back into the vault as a fact and
# never makes an unchanged note look changed.
#
# The same sentence also goes into `MEMORY.md`, the index Claude Code loads at session start,
# under that note's own entry. Where the line sits is what decides whether it is read, and the
# two placements fail in different runs: measured on 2026-10-28 over one question, seven arms and
# 50 runs each, the pointer in the note reached the page in 32 runs of 50 — and in none of the 17
# that never opened the note — while the same sentence under the note's entry in `MEMORY.md`
# reached it in 50 of 50, every answer correct, in a mean of 1.2 tool calls against 5.3 without
# it. The index is in context whether the agent goes looking or not; the note has to be opened
# first. Both are written, since the note's line costs nothing in the index's budget.
#
# The sentence written into the index is the one written into the note, unchanged. A shorter
# variant would buy room in a budgeted file and would not be the thing that was measured.
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
  # The page's own section headings, which are meant to make the pointer worth following: told
  # only that a page holds "the current state of this subject", the agent reached it in 1 of 4
  # runs; with the headings, 6 of 8 (2026-10-16). The gap is not shown to be the wording: the
  # three misses without headings never opened the note at all.
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
base=$(basename "$note")
idx="$(dirname "$note")/MEMORY.md"
imk="<!-- brain:vault $base -->"
# The index is a list of one line per note; the pointer goes under its note's own line as a
# sub-bullet, so the list it belongs to survives. The marker carries the note's file name
# because every note's pointer lives in this one file and a run must replace only its own.
# `memory-sync.sh` skips `MEMORY.md` as the index rather than a memory, so nothing here can come
# back into the vault as a fact and there is no hash to re-stamp.
if [ ! -f "$idx" ]; then
  log "no MEMORY.md beside $base, so there is no entry to point: the note's own line is written"
elif ! grep -qF "]($base)" "$idx"; then
  # An entry this script did not find is an entry it would have to invent, which means writing a
  # row into the owner's index for a note they have not listed there.
  log "$base has no entry in MEMORY.md, and inventing one is not this script's to do"
else
  ind=""
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    ind="$ind  - $l $imk"$'\n'
  done <<EOF
${lines#$'\n'}
EOF
  itmp=$(mktemp)
  # ENVIRON, not -v: awk expands backslash escapes in a -v assignment, and the sentence carries
  # a page's own section headings.
  BRAIN_MK="$imk" BRAIN_KEY="]($base)" BRAIN_PTR="$ind" awk '
    index($0, ENVIRON["BRAIN_MK"]) { next }
    { print }
    index($0, ENVIRON["BRAIN_KEY"]) && !done { printf "%s", ENVIRON["BRAIN_PTR"]; done = 1 }
  ' "$idx" > "$itmp"
  # `MEMORY.md` is loaded only as far as its first 200 lines or 25 KB, so a pointer below that
  # cut is bytes spent on a line nothing loads. The guard is on where the pointer itself lands in
  # the file this would produce, not on the file's total size: in an index already past the cut, a
  # pointer near the top is still read. When it does not fit, nothing is written and the run says
  # so — which note to drop from a full index is the owner's call, not this script's.
  # LC_ALL=C so `length` is bytes: gawk in a UTF-8 locale counts characters, and an index whose
  # summaries are not ASCII would then be measured at a third of its real size against a byte cap.
  pos=$(BRAIN_MK="$imk" LC_ALL=C awk '{ b += length($0) + 1; if (index($0, ENVIRON["BRAIN_MK"])) { n = NR; bb = b } } END { if (n) print n "\t" bb }' "$itmp")
  iln=$(printf '%s' "$pos" | cut -f1); iby=$(printf '%s' "$pos" | cut -f2)
  if [ "${iln:-0}" -gt 200 ] || [ "${iby:-0}" -gt 25600 ]; then
    rm -f "$itmp"
    log "MEMORY.md has no room: the pointer would land at line ${iln:-?}, byte ${iby:-?}, past the 200-line and 25 KB prefix that is loaded — not written"
  else
    cat "$itmp" > "$idx"; rm -f "$itmp"
    log "pointed the MEMORY.md entry for $base"
  fi
fi

log "pointed $(basename "$note") at ${#pages[@]} page(s)"
