#!/usr/bin/env bash
# test-memory-pointer.sh — behaviour tests for memory-pointer.sh, on a throwaway vault.
#
# Each case is a thing that would break the mechanism it exists for: a second run that
# duplicates the line instead of replacing it, a path that is not a memory note at all, and
# the region not being strippable — which is what keeps a pointer from coming back into the
# vault as a source and from making an unchanged note look changed to the next sync.
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

printf 'test-memory-pointer: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
