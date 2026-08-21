#!/usr/bin/env bash
# Secret gate. Patterns follow docs/privacy.md rule 2.
#
#   secret-gate.sh            scan stdin; exit 1 and report if anything matches
#   secret-gate.sh --redact   copy stdin to stdout with matches replaced by [redacted]
set -uo pipefail

pattern='AKIA[0-9A-Z]{16}|sk-[A-Za-z0-9_-]{20,}|ghp_[A-Za-z0-9]{36}|gho_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}|xox[abpr]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|Bearer [A-Za-z0-9._~+/=-]{20,}|(password|passwd|secret|api[_-]?key|token)[[:space:]]*[:=][[:space:]]*["'"'"']?[A-Za-z0-9_./+=-]{8,}'

if [ "${1:-}" = "--redact" ]; then
  sed -E "s/$pattern/[redacted]/gI"
  exit 0
fi

hits=$(grep -n -E -i "$pattern" || true)
if [ -n "$hits" ]; then
  echo "secret gate: possible credentials found" >&2
  echo "$hits" | cut -c1-60 | sed 's/$/…/' >&2
  exit 1
fi
exit 0
