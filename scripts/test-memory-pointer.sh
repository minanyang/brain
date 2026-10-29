#!/usr/bin/env bash
# test-memory-pointer.sh — behaviour tests for memory-pointer.sh, on a throwaway vault.
#
# Each case is a thing that would break the mechanism it exists for: a second run that
# duplicates the line instead of replacing it, a path that is not a memory note at all, and
# the region not being strippable — which is what keeps a pointer from coming back into the
# vault as a source and from making an unchanged note look changed to the next sync.
#
# The same sentence goes into `MEMORY.md` under the note's own entry, which is the placement that
# was measured at 50 runs of 50 against the note's own 32. Its cases are the ways that write
# could damage a file Brain does not own: replacing another note's pointer, inventing an entry
# for a note the owner never listed, forking the measured sentence into a shorter one, and
# spending bytes below the prefix that is actually loaded.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT

pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  ok %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s — %s\n' "$1" "$2" >&2; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }

mkdir -p "$t/vault/topics" "$t/projects/acme/memory"
printf -- '---\ntitle: T\ntype: topic\nupdated: 2026-03-04\n---\n\nA page.\n' > "$t/vault/topics/db-safety.md"
note="$t/projects/acme/memory/db-allow.md"
printf -- '---\nname: db-allow\n---\n\nRun the script.\n' > "$note"
printf '{"vaults":[{"name":"acme","path":"%s","include":["%s/work/**"]}]}\n' "$t/vault" "$t" > "$t/config.json"
export BRAIN_CONFIG="$t/config.json"
run() { "$here/memory-pointer.sh" --vault acme --note "$note" "$@" >/dev/null 2>&1; }

run --page topics/db-safety
is "writes one pointer" "$(grep -c '^<!-- brain:vault -->$' "$note")" "1"
is "names the page's own updated date, not today" "$(grep -c 'last 2026-03-04' "$note")" "1"

run --page topics/db-safety
is "a second run replaces rather than appends" "$(grep -c '^<!-- brain:vault -->$' "$note")" "1"
is "the note's own body survives" "$(grep -c 'Run the script.' "$note")" "1"

# What memory-sync.sh does before hashing or copying a note.
is "the region strips back to the note as written" \
  "$(sed '/^<!-- brain:vault -->$/,$d' "$note")" \
  "$(printf -- '---\nname: db-allow\n---\n\nRun the script.')"

run --page topics/no-such-page
is "a page that does not exist writes nothing" "$(grep -c 'no-such-page' "$note")" "0"

# The measured lever: told only that a page holds "the current state of this subject" the agent
# opened it in 1 of 4 runs; told what the page covers, in the page's own section headings, 6 of 8.
# The three housekeeping sections name no subject and are left out.
{ printf -- '---\ntitle: T\ntype: topic\nupdated: 2026-03-04\n---\n\nA page.\n'
  printf -- '\n## Logins\nx\n\n## Reaching the databases\ny\n\n## Open threads\n- z\n\n## Conflicts\n'
} > "$t/vault/topics/db-safety.md"
run --page topics/db-safety
case "$(grep -m1 '^\*\*Vault:' "$note")" in
  *"It covers: Logins; Reaching the databases."*) ok "the pointer names what the page covers" ;;
  *) bad "the pointer names what the page covers" "$(grep -m1 '^\*\*Vault:' "$note")" ;;
esac
case "$(grep -m1 '^\*\*Vault:' "$note")" in
  *"Open threads"*|*Conflicts*) bad "housekeeping sections are left out" "they were listed" ;;
  *) ok "housekeeping sections are left out" ;;
esac

# A pointer must not cost a snapshot. memory-sync.sh hashes the note as it sits on disk, so
# the write re-stamps that hash — without it, one session's sync re-snapshots what another
# session's sync just wrote, which on 2026-10-16 made five snapshots of one note in a day.
mkdir -p "$t/vault/.state"
printf -- '---\nname: db-allow\n---\n\nRun the script.\n' > "$note"
printf '{"%s": "%s"}\n' "$note" "$(git hash-object "$note")" > "$t/vault/.state/memory.json"
run --page topics/db-safety
is "the pointer's own write leaves the note looking unchanged to a sync" \
  "$(jq -r --arg f "$note" '.[$f]' "$t/vault/.state/memory.json")" "$(git hash-object "$note")"

# A note nothing has ever snapshotted has no entry, and inventing one would mean it is never
# snapshotted at all.
printf '{}\n' > "$t/vault/.state/memory.json"
run --page topics/db-safety
is "a note with no entry does not get one" \
  "$(jq -r --arg f "$note" 'has($f)' "$t/vault/.state/memory.json")" "false"

if "$here/memory-pointer.sh" --vault acme --note "$t/vault/topics/db-safety.md" \
   --page topics/db-safety >/dev/null 2>&1; then
  bad "refuses a path outside a memory directory" "it wrote to a vault page"
else
  ok "refuses a path outside a memory directory"
fi

if "$here/memory-pointer.sh" --vault acme --note "$t/projects/acme/memory/gone.md" \
   --page topics/db-safety >/dev/null 2>&1; then
  ok "a note that no longer exists is a no-op, not an error"
else
  bad "a note that no longer exists is a no-op, not an error" "non-zero exit"
fi

# --- the MEMORY.md entry (the measured placement) ---------------------------
idx="$t/projects/acme/memory/MEMORY.md"
other="$t/projects/acme/memory/other-note.md"
printf -- '---\nname: other-note\n---\n\nSomething else.\n' > "$other"
fresh_index() {
  { printf -- '- [other-note](other-note.md) — a hook\n'
    printf -- '- [db-allow](db-allow.md) — another hook\n'
  } > "$idx"
}

printf -- '---\nname: db-allow\n---\n\nRun the script.\n' > "$note"
fresh_index
run --page topics/db-safety
is "the index gets one pointer under the note's own entry" \
  "$(grep -c '^  - \*\*Vault:.*<!-- brain:vault db-allow.md -->$' "$idx")" "1"
is "it sits directly below that entry, not elsewhere" \
  "$(awk '/^- \[db-allow\]/ { getline; print ($0 ~ /brain:vault db-allow.md/) ? "below" : "elsewhere" }' "$idx")" "below"
is "the entry's own line is untouched" \
  "$(grep -c '^- \[db-allow\](db-allow.md) — another hook$' "$idx")" "1"

# A shorter variant in the index would save room in a budgeted file and would not be the sentence
# the 50-of-50 was measured on, so the two placements must carry the same text.
is "the index carries the note's sentence unchanged" \
  "$(sed -n 's/^  - \(\*\*Vault:.*\) <!-- brain:vault db-allow.md -->$/\1/p' "$idx")" \
  "$(grep -m1 '^\*\*Vault:' "$note")"

run --page topics/db-safety
is "a second run replaces the index line rather than appending" "$(grep -c 'brain:vault db-allow.md' "$idx")" "1"
is "the index keeps its other entry" "$(grep -c '^- \[other-note\]' "$idx")" "1"

# Every note's pointer lives in this one file, so a run must replace only its own.
"$here/memory-pointer.sh" --vault acme --note "$other" --page topics/db-safety >/dev/null 2>&1
is "pointing another note leaves the first note's line alone" "$(grep -c 'brain:vault db-allow.md' "$idx")" "1"
is "and writes its own" "$(grep -c 'brain:vault other-note.md' "$idx")" "1"

# An entry this script cannot find is one it would have to invent, in a file the owner maintains.
printf -- '- [other-note](other-note.md) — a hook\n' > "$idx"
run --page topics/db-safety
is "a note with no entry gets no invented one" "$(grep -c 'brain:vault db-allow.md' "$idx")" "0"
is "the note itself is still pointed" "$(grep -c '^<!-- brain:vault -->$' "$note")" "1"

rm -f "$idx"
run --page topics/db-safety
is "no index at all is a no-op, not an error" "$(grep -c '^<!-- brain:vault -->$' "$note")" "1"

# Only the first 200 lines or 25 KB of the index are loaded, so a pointer below that cut is bytes
# spent on a line nothing reads. The guard is on the pointer's own position, so an entry near the
# top of an over-long index still gets one.
{ printf -- '- [db-allow](db-allow.md) — another hook\n'
  i=0; while [ $i -lt 400 ]; do printf -- '- [filler-%d](filler-%d.md) — padding\n' "$i" "$i"; i=$((i+1)); done
} > "$idx"
run --page topics/db-safety
is "a pointer that lands inside the loaded prefix is written" "$(grep -c 'brain:vault db-allow.md' "$idx")" "1"

{ i=0; while [ $i -lt 400 ]; do printf -- '- [filler-%d](filler-%d.md) — padding\n' "$i" "$i"; i=$((i+1)); done
  printf -- '- [db-allow](db-allow.md) — another hook\n'
} > "$idx"
before=$(git hash-object "$idx")
run --page topics/db-safety
is "a pointer that would land past the loaded prefix is not written" "$(grep -c 'brain:vault db-allow.md' "$idx")" "0"
is "and the index is left byte-for-byte as it was" "$(git hash-object "$idx")" "$before"

printf 'test-memory-pointer: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
