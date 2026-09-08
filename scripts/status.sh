#!/usr/bin/env bash
# status.sh <cwd> → SessionStart context as JSON on stdout (nothing if idle).
#
# Reads only files, never the model. Emits:
#   - the default schema, when cwd is inside a vault
#   - one reminder line, when the routed vault has digests not yet ingested
#   - the routed vault's brief.md, when inject_brief is true
#   - a session map, when inject_brief is true: the wiki pages that this directory's
#     sessions of the last 30 days fed, most cited first, so the agent knows what to read
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
  pending_files=$(grep -l '^ingested: false' "$vp"/sources/*/*.md 2>/dev/null || true)
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
      digests=$(awk -v cwd="$probe" -v home="$HOME" -v cutoff="$cutoff" '
        FNR == 1 { n = split(FILENAME, a, "/"); base = a[n]; if (substr(base, 1, 10) < cutoff) nextfile }
        /^cwd:/ { c = substr($0, 6); sub(/^~/, home, c)
                  if (c == cwd || index(c, cwd "/") == 1) print "sources/sessions/" base
                  nextfile }
        FNR > 8 { nextfile }' "$vp"/sources/sessions/*.md 2>/dev/null || true)
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
      ctx="${ctx:+$ctx$'\n\n'}Pages in vault '$vault' that sessions in this directory fed over the last 30 days, most cited first. Read one at $vp/<page>.md before stating facts about what it covers; use /brain:query for questions these do not answer.$map"
    fi
  fi
fi

[ -n "$ctx" ] || exit 0
jq -n --arg c "$ctx" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
