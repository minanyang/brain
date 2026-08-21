#!/usr/bin/env bash
# route.sh <cwd> → vault name on stdout, exit 1 if none.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
route "${1:?cwd}"
