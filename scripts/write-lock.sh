#!/usr/bin/env bash
# Hold a vault lock across an agent's read/edit/finish tool calls.
# write-lock.sh acquire <vault-path>
# write-lock.sh release <vault-path> <lease>
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
op="${1:?acquire or release}" vp=$(expand_home "${2:?vault path}")
[ -d "$vp/.git" ] || { log "not a vault git checkout: $vp"; exit 2; }
d="$vp/.state/lock"
case "$op" in
  acquire)
    lock "$vp" || { log "vault is busy; retry after the other writer finishes"; exit 1; }
    # Do not replace a lease inherited from a caller.
    [ ! -f "$d/owner" ] || { log "already holding a lease"; exit 1; }
    lease=$(mktemp "${TMPDIR:-/tmp}/brain-lease.XXXXXXXX")
    lease=${lease##*/}
    rm -f "${TMPDIR:-/tmp}/$lease"
    printf '%s\n' "$lease" > "$d/owner"
    rm -f "$d/pid"
    printf '%s\n' "$lease"
    ;;
  release)
    [ -n "${3:-}" ] && [ "$(cat "$d/owner" 2>/dev/null)" = "$3" ] || {
      log "lease does not match; lock left intact"; exit 1;
    }
    rm -f "$d/owner"
    rmdir "$d"
    ;;
  *) log "usage: write-lock.sh acquire <vault> | release <vault> <lease>"; exit 2 ;;
esac
