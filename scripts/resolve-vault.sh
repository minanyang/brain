#!/usr/bin/env bash
# resolve-vault.sh [--vault <name>] [--cwd <dir>] → "<name>\t<path>" on stdout, exit 1 if none.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
config_exists || { echo "no config at $BRAIN_CONFIG — run /brain:init first" >&2; exit 1; }
name="" cwd="$PWD"
while [ $# -gt 0 ]; do case "$1" in --vault) name="$2"; shift ;; --cwd) cwd="$2"; shift ;; esac; shift; done
v=$(resolve_vault "$name" "$cwd") || { echo "no vault for $cwd; pass --vault <name>" >&2; exit 1; }
printf '%s\t%s\n' "$v" "$(vault_path "$v")"
