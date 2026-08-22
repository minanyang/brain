#!/usr/bin/env bash
# Distill Claude Code transcripts into session digests.
#
#   distill.sh <transcript.jsonl> [...]     distill the given transcripts
#   distill.sh --all [--days N] [--jobs J]  every transcript under the configured
#                                           roots (only those modified in the last
#                                           N days when --days is given), J runners
#                                           in parallel (default 1)
#   distill.sh --quiet ...                  only report what was written or blocked
#
# For each transcript: route its cwd to a vault, read from the byte offset
# recorded in <vault>/.state/distilled.json, turn the new part into clean text,
# redact credential patterns, ask a small model to fill the digest template,
# run the secret gate on the result, and write sources/sessions/<date>-<slug>.md
# (or append a "## Continued" section). Very long sessions are summarized in
# parts at turn boundaries. Idempotent: unchanged transcripts are no-ops.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ "${BRAIN_INNER:-}" = 1 ] && exit 0
config_exists || { log "no config at $BRAIN_CONFIG — run /brain:init first"; exit 0; }

all=0 days="" quiet=0 jobs=1 files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --all) all=1 ;;
    --days) days="$2"; shift ;;
    --jobs) jobs="$2"; shift ;;
    --quiet) quiet=1 ;;
    *) files+=("$1") ;;
  esac
  shift
done

model=$(config_get '.distill_model' haiku)
min_chars=400
max_chars="${BRAIN_MAX_CHARS:-250000}"   # per model call; roughly 60–80k tokens
written=0 skipped=0 blocked=0
work=$(mktemp -d "${TMPDIR:-/tmp}/brain-distill.XXXXXX")
trap 'rm -r "$work"' EXIT

say() { [ $quiet = 1 ] || log "$@"; }

to_local_date() { # ISO timestamp → YYYY-MM-DD in local time
  local ts="${1%%.*}"
  date -j -u -f '%Y-%m-%dT%H:%M:%S' "$ts" '+%Y-%m-%d' 2>/dev/null \
    || date -d "${1}" '+%Y-%m-%d' 2>/dev/null \
    || printf '%s' "${1:0:10}"
}

# digest_prompt <section-header or "">  — empty header means "fill the whole template"
digest_prompt() {
  cat <<EOF
You are writing a session digest for a personal knowledge vault. Below is the cleaned transcript of one working session between a user and an AI coding agent. Output only the markdown body, no frontmatter, no preamble.

Rules:
- Past tense, concrete, terse. Only what the transcript supports; no speculation.
- No tool output, no code blocks longer than 5 lines, no credentials or tokens, no verbatim pasted documents — state the fact, not the artifact.
- Write in English. Keep file names, commands, and proper nouns as they appear.
- In "Learned", tag every bullet: [me] for how the user works or prefers things, [person:<name>] for people or teams, [project:<name>] for the repository or product (use the repository name), [topic:<name>] for technical or domain concepts. Omit a section if it has nothing, except "What happened".
- Dates absolute (YYYY-MM-DD), never relative.

EOF
  if [ -n "$1" ]; then
    cat <<EOF
The transcript below is one part of a session whose digest already has other sections. Produce ONLY a section headed exactly '$1', containing the sub-sections '### What happened', '### Decisions', '### Learned', '### Open threads' for this part alone.
EOF
  else
    cat <<'T'
Fill in this template exactly:

## What happened
- 3–6 bullets.

## Decisions
- <decision> — because <reason>.

## Learned
- [me] …
- [person:<name>] …
- [project:<name>] …
- [topic:<name>] …

## Open threads
- Things left unfinished or explicitly deferred.
T
  fi
  printf '\nTranscript:\n'
}

slugify() { # title → slug (keeps unicode letters), empty if nothing usable
  jq -rn --arg t "$1" '$t | ascii_downcase | gsub("[^\\p{L}\\p{N}]+"; "-") | gsub("^-+|-+$"; "") | .[0:40] | gsub("-+$"; "")'
}

digest_trailer() { # repeated after the transcript so the instruction is the most recent thing the model reads
  printf '\nEnd of transcript. Now write the digest as instructed above'
  if [ -n "$1" ]; then printf ': one section headed exactly %s with ### What happened, ### Decisions, ### Learned, ### Open threads. Do not copy headings from the transcript.\n' "'$1'"
  else printf ': the template starting with "## What happened". Do not copy headings from the transcript.\n'; fi
}

summarize() { # <chunk-file> <section-header>
  { digest_prompt "$2"; cat "$1"; digest_trailer "$2"; } \
    | BRAIN_INNER=1 claude -p --model "$model" --no-session-persistence --tools "" --setting-sources "" --output-format text 2>/dev/null
}

well_formed() { # <text> <expected section header or "">
  if [ -n "$2" ]; then printf '%s\n' "$1" | grep -qF -- "$2"
  else printf '%s\n' "$1" | grep -q '^## What happened'; fi
}

process() {
  local file="$1" meta session cwd branch title first_ts last_ts end
  meta=$("$BRAIN_ROOT/scripts/extract-transcript.sh" --meta "$file") || { say "unreadable: $file"; skipped=$((skipped+1)); return; }
  session=$(jq -r '.session // empty' <<<"$meta")
  [ -n "$session" ] || { say "no session id: $file"; skipped=$((skipped+1)); return; }
  cwd=$(jq -r '.cwd // empty' <<<"$meta")
  end=$(jq -r '.end' <<<"$meta")

  local vault vpath
  vault=$(route "$cwd") || { say "no vault for $cwd ($session)"; skipped=$((skipped+1)); return; }
  vpath=$(vault_path "$vault")
  [ -d "$vpath" ] || { log "vault $vault missing at $vpath"; skipped=$((skipped+1)); return; }

  local state="$vpath/.state/distilled.json" offset digest
  mkdir -p "$vpath/.state" "$vpath/sources/sessions"
  [ -f "$state" ] || echo '{}' > "$state"
  offset=$(jq -r --arg s "$session" '.[$s].offset // 0' "$state")
  digest=$(jq -r --arg s "$session" '.[$s].digest // empty' "$state")
  [ "$end" -le "$offset" ] && return   # nothing new

  local text
  text=$("$BRAIN_ROOT/scripts/extract-transcript.sh" "$file" "$offset" | "$BRAIN_ROOT/scripts/secret-gate.sh" --redact)
  if [ "${#text}" -lt "$min_chars" ]; then
    # Too little new material to be worth a model call; remember where we are
    # only if a digest already exists (a fresh, tiny session may still grow).
    if [ -n "$digest" ]; then
      jq --arg s "$session" --argjson o "$end" '.[$s].offset = $o' "$state" > "$state.tmp" && mv "$state.tmp" "$state"
    fi
    say "too short, skipped: $session"; skipped=$((skipped+1)); return
  fi

  branch=$(jq -r '.branch // ""' <<<"$meta")
  title=$(jq -r '.title // ""' <<<"$meta")
  first_ts=$(jq -r '.first_ts // ""' <<<"$meta")
  last_ts=$(jq -r '.last_ts // ""' <<<"$meta")
  local date today mode
  date=$(to_local_date "$first_ts")
  today=$(date '+%Y-%m-%d')
  mode=new; [ -n "$digest" ] && [ -f "$vpath/$digest" ] && mode=continued

  # Split at turn boundaries (blank lines) once a chunk exceeds max_chars.
  local dir="$work/$session" n k header body part
  mkdir -p "$dir"
  printf '%s\n' "$text" | awk -v max="$max_chars" -v pfx="$dir/chunk-" '
    BEGIN { n = 1; f = sprintf("%s%03d", pfx, n); size = 0 }
    { if (size > max && $0 == "") { close(f); n++; f = sprintf("%s%03d", pfx, n); size = 0; next }
      print > f; size += length($0) + 1 }'
  n=$(ls "$dir"/chunk-* | wc -l | tr -d ' ')
  [ "$n" -gt 1 ] && say "long session, $n parts: $session"

  body="" k=0
  for chunk in "$dir"/chunk-*; do
    k=$((k+1))
    if [ "$mode" = continued ]; then
      header="## Continued ($today)"; [ "$n" -gt 1 ] && header="$header, part $k of $n"
    elif [ "$k" -gt 1 ]; then
      header="## Part $k of $n"
    else
      header=""
    fi
    part=$(summarize "$chunk" "$header") || { log "model call failed (part $k of $n): $session"; skipped=$((skipped+1)); return; }
    if ! well_formed "$part" "$header"; then   # small models sometimes answer instead of filling the template; one retry
      part=$(summarize "$chunk" "$header") || { log "model call failed (part $k of $n): $session"; skipped=$((skipped+1)); return; }
      well_formed "$part" "$header" || { log "malformed digest (part $k of $n), not written: $session"; skipped=$((skipped+1)); return; }
    fi
    body="${body:+$body

}$part"
  done

  if ! printf '%s' "$body" | "$BRAIN_ROOT/scripts/secret-gate.sh" 2>/dev/null; then
    log "secret gate blocked digest for $session ($file)"; blocked=$((blocked+1)); return
  fi

  lock_wait "$vpath" || { log "vault $vault stayed locked for 2 minutes, giving up on $session"; skipped=$((skipped+1)); return; }
  trap 'unlock "$vpath"' RETURN

  if [ "$mode" = continued ]; then
    printf '\n%s\n' "$body" >> "$vpath/$digest"
  else
    local slug
    slug=$(slugify "$title"); [ -n "$slug" ] || slug="${session:0:8}"
    digest="sources/sessions/$date-$slug.md"
    if [ -e "$vpath/$digest" ]; then digest="sources/sessions/$date-$slug-${session:0:8}.md"; fi
    {
      printf -- '---\nsession: %s\ndate: %s\ncwd: %s\nbranch: %s\ntitle: %s\ningested: false\n---\n\n' \
        "$session" "$date" "${cwd/#$HOME/~}" "$branch" "$(printf '%s' "$title" | tr -d '\n' | sed 's/"/\\"/g')"
      printf '%s\n' "$body"
    } > "$vpath/$digest"
  fi

  jq --arg s "$session" --argjson o "$end" --arg d "$digest" --arg t "$last_ts" --arg f "$file" \
     '.[$s] = {offset: $o, digest: $d, last_ts: $t, transcript: $f}' "$state" > "$state.tmp" && mv "$state.tmp" "$state"
  written=$((written+1)); case " $written_in " in *" $vault "*) ;; *) written_in="$written_in $vault" ;; esac
  log "$mode → $vault/$digest"
}

written_in=""

if [ $all = 1 ]; then
  while read -r root; do
    [ -d "$root" ] || continue
    if [ -n "$days" ]; then
      find "$root" -mindepth 2 -maxdepth 2 -name '*.jsonl' -mtime "-${days}" -print0
    else
      find "$root" -mindepth 2 -maxdepth 2 -name '*.jsonl' -print0
    fi
  done < <(transcript_roots) | sort -z | while IFS= read -r -d '' f; do printf '%s\n' "$f"; done > "$work/list"
  while IFS= read -r f; do files+=("$f"); done < "$work/list"
fi

[ ${#files[@]} -gt 0 ] || { say "nothing to distill"; exit 0; }

if [ "$jobs" -gt 1 ] && [ ${#files[@]} -gt 1 ]; then
  # Deal the files round-robin to J child runners. Writes are serialized by the
  # vault lock and each child commits its own output.
  i=0
  for f in "${files[@]}"; do echo "$f" >> "$work/jobs-$((i % jobs))"; i=$((i+1)); done
  for j in "$work"/jobs-*; do
    ( while IFS= read -r f; do printf '%s\0' "$f"; done < "$j" | xargs -0 "$BRAIN_ROOT/scripts/distill.sh" $( [ $quiet = 1 ] && echo --quiet ) ) &
  done
  wait
  log "done: $jobs runners finished (see the lines above for their counts)"
  exit 0
fi

for f in "${files[@]}"; do [ -f "$f" ] && process "$f"; done

for v in $written_in; do
  vp=$(vault_path "$v")
  lock_wait "$vp" || { log "could not lock $v to commit; digests are written but uncommitted"; continue; }
  printf '## [%s] distill | %s\n' "$(date '+%Y-%m-%d')" "$(git -C "$vp" status --porcelain sources/sessions/ | wc -l | tr -d ' ') session file(s)" >> "$vp/log.md"
  git -C "$vp" add sources/sessions/ log.md >/dev/null 2>&1 && git -C "$vp" commit -q -m "distill: $(date '+%Y-%m-%d')" >/dev/null 2>&1 || true
  unlock "$vp"
done

log "done: $written written, $skipped skipped, $blocked blocked by secret gate"
