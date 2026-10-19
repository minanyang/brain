#!/usr/bin/env bash
# status.sh <cwd> [--source <s>] [--transcript <path>]
#   → SessionStart context as JSON on stdout (nothing if idle).
#
# Reads only files, never the model. Emits:
#   - the default schema, when cwd is inside a vault
#   - one reminder line, when the routed vault has digests not yet ingested
#   - the routed vault's brief.md, when inject_brief is true
#   - a session map, when inject_brief is true: the wiki pages that this directory's
#     sessions of the last 30 days fed, most cited first, so the agent knows what to read
#   - after a compaction or a resume, the vault pages this conversation already cited
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
config_exists || exit 0
cwd="${1:-$PWD}"
shift || true
src="" transcript=""
while [ $# -gt 0 ]; do
  case "$1" in
    --source) src="${2:-}"; shift ;;
    --transcript) transcript="${2:-}"; shift ;;
  esac
  shift
done

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
  pending_files=$(pending_sources "$vp")
  pending=$(printf '%s' "$pending_files" | grep -c . || true)
  if [ "$pending" -gt 0 ]; then
    # A digest continued after it was ingested is pending since its last append, not since
    # the file's date — a workspace session resumed for a month read "since <a month ago>".
    since=$(printf '%s\n' "$pending_files" | while IFS= read -r f; do
      d=$(grep -o '^## Continued ([0-9-]\{10\}' "$f" 2>/dev/null | tail -1 | cut -c15-24 || true)
      [ -n "$d" ] && printf '%s\n' "$d" || basename "$f" | cut -c1-10
    done | sort | head -1)
    line="[brain] $pending source(s) pending in vault '$vault' since $since"
  fi
  wiki_dirs=$(find "$vp" -maxdepth 1 -mindepth 1 -type d ! -name sources ! -name '.*')
  open=$( { [ -n "$wiki_dirs" ] && grep -rh '^- \[open\]' $wiki_dirs 2>/dev/null; } | wc -l | tr -d ' ' || true)
  [ "$open" -gt 0 ] && line="${line:-[brain] vault '$vault'}${line:+,} $open open conflict(s)"
  if [ -n "${line:-}" ]; then
    ctx="${ctx:+$ctx$'\n\n'}$line — run /brain:ingest"
  fi
  if [ "$(config_get '.inject_brief' false)" = true ]; then
    if [ -s "$vp/brief.md" ] && "$BRAIN_ROOT/scripts/secret-gate.sh" < "$vp/brief.md" 2>/dev/null; then
      ctx="${ctx:+$ctx$'\n\n'}Brief from vault '$vault':"$'\n'"$(cat "$vp/brief.md")"
    fi
    # Session map. The brief says who the user is; it does not say which pages cover the
    # thing this session is about, and an agent never queries for a fact it does not know it
    # lacks. index.md is too big to inject whole, so: digests of the last 30 days whose cwd is
    # this directory or below it (walking up to the parent when a directory has none, since
    # a workspace root's sessions are about its sub-repositories), then the pages that cite
    # them, ranked by citing lines, capped at 20. The digest list reaches awk joined by "|"
    # (slugs never contain it): BSD awk rejects a newline inside a -v value.
    cutoff=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d '30 days ago' +%Y-%m-%d)
    digests="" probe="$cwd"
    while [ -z "$digests" ] && [ "$probe" != "$HOME" ] && [ "$probe" != / ]; do
      digests=$(find "$vp/sources/sessions" -type f -name '*.md' -print0 | xargs -0 awk -v prefix="$vp/" -v cwd="$probe" -v home="$HOME" -v cutoff="$cutoff" '
        FNR == 1 { n = split(FILENAME, a, "/"); base = a[n]; if (substr(base, 1, 10) < cutoff) nextfile }
        /^cwd:/ { c = substr($0, 6); sub(/^~/, home, c)
                  if (c == cwd || index(c, cwd "/") == 1) { relative = FILENAME; if (index(relative, prefix) == 1) relative = substr(relative, length(prefix) + 1); print relative }
                  nextfile }
        FNR > 10 { nextfile }' 2>/dev/null || true)
      probe=$(dirname "$probe")
    done
    map=""
    if [ -n "$digests" ] && [ -n "$wiki_dirs" ]; then
      while IFS= read -r page; do
        [ -n "$page" ] || continue
        map="$map"$'\n'"$(grep -F -m1 -- "- [[${page}]] " "$vp/index.md" 2>/dev/null || printf -- '- [[%s]]' "$page")"
      done < <(find $wiki_dirs -maxdepth 1 -name '*.md' -print0 | xargs -0 awk \
          -v list="$(printf '%s' "$digests" | tr '\n' '|')" -v vp="$vp/" 'BEGIN { n = split(list, d, "|") }
          index($0, "sources/sessions/") { for (i = 1; i <= n; i++) if (d[i] != "" && index($0, d[i])) { c[FILENAME]++; break } }
          END { for (f in c) { p = f; sub("^" vp, "", p); sub(/\.md$/, "", p); print c[f] "\t" p } }' 2>/dev/null \
        | sort -rn | head -20 | cut -f2)
    fi
    if [ -n "$map" ] && printf '%s' "$map" | "$BRAIN_ROOT/scripts/secret-gate.sh" 2>/dev/null; then
      # The instruction is measured, not assumed, and it has been wrong in both directions.
      # Told only to read the page first, agents answered status questions from a page that had
      # gone stale. Told that pages are notes and the system is the truth, they stopped opening
      # the vault at all (43 reads -> 3 across 60 runs) and then answered "there is no record"
      # to the one question only the vault could answer. This version says what a page is worth:
      # its claims carry the date and the check behind them, so they are citable as they stand,
      # and it names the categories where the vault is the only source. See architecture.md.
      ctx="${ctx:+$ctx$'\n\n'}Pages in vault '$vault' that sessions in this directory fed over the last 30 days, most cited first, at $vp/<page>.md. Read the page that covers your question and answer from it, citing it as [[dir/page]]. Some things only these pages record: whether something actually ran in an environment, why a choice was made, what happened during an incident, and how work moved across repositories. When your question is one of those, these pages are the primary source — look here before concluding that no record exists. A line below marked \`(deprecated …)\` is a page kept as history; it names what superseded it, and that is the page to read. Their status claims carry the date they were established, and most carry the check behind them — (verified 2026-09-22: ~/Repos/acme a1b2c3d in origin/main) — written by ingest after it ran that check against git. Treat a dated, checked claim as established and do not re-derive it. Verify before answering only when the claim has no date or no marker, when its date is older than a release or change you already know happened, or when something in front of you contradicts it — and say which of those applied. For why something was decided or what happened, the page names the primary document (a spec, runbook, release record); open it only when you need detail the page does not carry. The list is ranked by how often sessions in this directory cited each page, not by what you were asked, so a subject it does not name is usually still in the vault: search the vault itself before answering from the repository or concluding no record exists — the \`mcp__brain__search\` tool where it is available, a grep over the directory above otherwise.$map"
    fi
  fi
fi

# After a compaction the conversation keeps a summary of itself, and a summary of a vault page
# is the one thing the read side is built to prevent: the measured failure on "why was this
# decided" questions was an agent answering from a page's summary rather than the page. The
# pages this conversation already cited are therefore named again, as addresses to re-open —
# not re-quoted, which would spend the context the compaction just reclaimed.
#
# This is the whole of what can be done about it. PreCompact can block a compaction but cannot
# add anything to one, and PostCompact cannot either; SessionStart with source=compact is the
# documented place, and it is already where this script runs.
#
# A resume is included because it loses the same thing. A `clear` is not: the user asked for a
# fresh start and listing what the cleared conversation read would argue with them.
case "$src" in
  compact|resume)
    if [ -n "$transcript" ] && [ -f "$transcript" ] && [ -n "${vault:-}" ]; then
      # The existence test is inside an `if`, not a trailing `&&`: a `[[page]]` the vault does
      # not have — a link the agent invented, or a page since renamed — would otherwise make
      # the loop body exit non-zero on its last iteration, and under `set -e` that killed the
      # whole script. The symptom was this section never appearing, which looks exactly like
      # the feature not being built.
      read_pages=$( (grep -oE '\[\[[a-z0-9]+/[a-z0-9][a-z0-9.-]*\]\]' "$transcript" 2>/dev/null \
        | sed 's/^\[\[//; s/\]\]$//' | awk '!seen[$0]++' \
        | while IFS= read -r pg; do
            if [ -f "$vp/$pg.md" ]; then printf -- '- [[%s]]\n' "$pg"; fi
          done | head -10) || true)
      if [ -n "$read_pages" ]; then
        ctx="${ctx:+$ctx$'\n\n'}Vault pages this conversation already cited, at $vp/<page>.md. The conversation above is a summary of itself, so a claim it carries about one of these pages is a summary of a summary; re-open the page before stating what it says."$'\n'"$read_pages"
      fi
    fi
    ;;
esac

[ -n "$ctx" ] || exit 0
jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
