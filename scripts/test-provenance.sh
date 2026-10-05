#!/usr/bin/env bash
# test-provenance.sh — behaviour tests for provenance.sh, on a throwaway vault.
#
# Each case is a defect that happened, not a shape that might: an ASCII character class
# silently dropped every Chinese-named digest (most of them); the roll-up counted its own
# frontmatter as evidence; a second run appended a duplicate `sources_cited:`.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
v="$(mktemp -d)"
trap 'rm -rf "$v"' EXIT

pass=0 fail=0
ok()   { pass=$((pass+1)); printf '  ok %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  FAIL %s — %s\n' "$1" "$2" >&2; }
is()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }

mkdir -p "$v/topics" "$v/me" "$v/sources/sessions/claude"

page() {  # page <path> <frontmatter sources line> <body>
  { printf -- '---\ntitle: T\ntype: topic\nbrief: false\nvolatile: false\nlocked: false\nupdated: 2026-01-01\n%s\n---\n\n%s\n' "$2" "$3"; } > "$v/$1"
}
field() { grep -m1 "^$2:" "$v/$1" | sed "s/^$2: *//"; }

# 1. A Chinese filename is a path like any other. An ASCII-only class truncated it and the
#    citation vanished from the roll-up without any error.
page topics/cjk.md 'sources: [sources/sessions/claude/2026-01-01-stale.md]' \
  'A claim (→ sources/sessions/claude/2026-09-24-壓測成本優化.md) and another (→ sources/sessions/claude/2026-09-25-系統評分與餐廳訂位系統審核.md).'
"$here/provenance.sh" "$v" topics/cjk.md >/dev/null
is "counts both Chinese-named sources" "$(field topics/cjk.md sources_cited)" "2"
case "$(field topics/cjk.md sources)" in
  *壓測成本優化.md*系統評分*|*系統評分*壓測成本優化.md*) ok "keeps the Chinese paths whole" ;;
  *) bad "keeps the Chinese paths whole" "got $(field topics/cjk.md sources)" ;;
esac
case "$(field topics/cjk.md sources)" in
  *2026-01-01-stale.md*) bad "drops a frontmatter-only source" "stale entry survived" ;;
  *) ok "drops a frontmatter-only source" ;;
esac

# 2. The cap bounds the list; the count stays true.
body=''
for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15; do
  body="$body (→ sources/sessions/claude/2026-02-$i-s.md)"
done
page topics/many.md 'sources: []' "Claims:$body"
BRAIN_SOURCES_CAP=12 "$here/provenance.sh" "$v" topics/many.md >/dev/null
is "cap limits the list to 12" "$(field topics/many.md sources | tr ',' '\n' | grep -c 'sources/')" "12"
is "count is the true total, not the cap" "$(field topics/many.md sources_cited)" "15"
case "$(field topics/many.md sources)" in
  *2026-02-15-s.md*) ok "keeps the most recent" ;;
  *) bad "keeps the most recent" "2026-02-15 missing" ;;
esac

# 3. Idempotent, and never two `sources_cited:` lines.
"$here/provenance.sh" "$v" topics/many.md >/dev/null
before="$(cat "$v/topics/many.md")"
"$here/provenance.sh" "$v" topics/many.md >/dev/null
if [ "$before" = "$(cat "$v/topics/many.md")" ]; then ok "second run is a no-op"; else bad "second run is a no-op" "file changed"; fi
is "exactly one sources_cited line" "$(grep -c '^sources_cited:' "$v/topics/many.md")" "1"

# 4. A duplicate citation is one source.
page topics/dup.md 'sources: []' 'One (→ sources/sessions/claude/2026-03-01-a.md) and again (→ sources/sessions/claude/2026-03-01-a.md).'
"$here/provenance.sh" "$v" topics/dup.md >/dev/null
is "repeated citation counted once" "$(field topics/dup.md sources_cited)" "1"

# 5. A page with no citations gets an empty list, not a kept-by-accident stale one.
page topics/bare.md 'sources: [sources/sessions/claude/2026-01-01-gone.md]' 'Prose with no citation.'
"$here/provenance.sh" "$v" topics/bare.md >/dev/null
is "uncited page reports zero" "$(field topics/bare.md sources_cited)" "0"
is "uncited page lists nothing" "$(field topics/bare.md sources)" "[]"

# 6. The generated files and the vault's own instructions are not pages.
printf -- '# Index\n\nsources: [sources/sessions/claude/2026-01-01-x.md]\n' > "$v/index.md"
printf -- 'sources: [sources/sessions/claude/2026-01-01-x.md]\n' > "$v/CLAUDE.md"
"$here/provenance.sh" "$v" >/dev/null
is "index.md untouched" "$(grep -c '^sources_cited:' "$v/index.md")" "0"
is "CLAUDE.md untouched" "$(grep -c '^sources_cited:' "$v/CLAUDE.md")" "0"

printf 'test-provenance: %s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
