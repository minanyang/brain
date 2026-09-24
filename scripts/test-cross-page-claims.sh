#!/usr/bin/env bash
# Regression check for the advisory cross-page ticket scan; all fixture content is fabricated.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/brain-cross-page-test.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/projects" "$tmp/topics" "$tmp/decisions"
cat > "$tmp/projects/sample.md" <<'EOF'
# Sample project
As of 2026-01-01, TASK-123 is deployed to staging.
EOF
cat > "$tmp/topics/sample.md" <<'EOF'
# Sample topic
As of 2026-01-02, TASK-123 has never been deployed to staging.
EOF
cat > "$tmp/topics/unrelated.md" <<'EOF'
# Unrelated
As of 2026-01-02, unrelated service is deployed to staging.
EOF
cat > "$tmp/projects/old.md" <<'EOF'
# Old status
As of 2025-12-01, TASK-123 has never been deployed to staging.
EOF
cat > "$tmp/decisions/pointer.md" <<'EOF'
# Decision
As of 2026-01-02, TASK-123 status on [[topics/sample]]; this page records the decision rationale.
EOF
cat > "$tmp/projects/long.md" <<'EOF'
# Long cited claim
- TASK-777 Phase 2 was merged to `develop` on 2026-03-04 after the contract review, the generated client was refreshed in the same pass, and the submodule pointer moved with it (→ sources/sessions/2026-03-04-fabricated.md; → sources/sessions/2026-03-05-fabricated.md).
EOF
cat > "$tmp/topics/long.md" <<'EOF'
# Long cited counter-claim
- The contract change for TASK-777 was never merged to `develop`; as of 2026-03-05 it still sat on the feature branch awaiting a second review (→ sources/sessions/2026-03-05-fabricated.md).
EOF
cat > "$tmp/projects/generic.md" <<'EOF'
# Generic prose sharing a sentence with a ticket
- TASK-777 exposed it on 2026-03-04: unlike the other repos this codegen script has no override, so a not-yet-merged contract has to be passed to the generator by hand.
EOF
cat > "$tmp/topics/agreeing.md" <<'EOF'
# Two pages agreeing, negation after the verb
- TASK-888 shipped a validator that compiled on 2026-04-01, when CI ran no unit tests for it.
EOF
cat > "$tmp/projects/agreeing.md" <<'EOF'
# Same fact, negation before the verb
- As of 2026-04-01 the TASK-888 unit tests had never executed, because CI had no test step.
EOF
cat > "$tmp/topics/scoped.md" <<'EOF'
# Negation bound to a different predicate in the same clause
- Until TASK-999 fixed it on 2026-05-06, the checked-in client had not been generated from the contract.
EOF
cat > "$tmp/projects/scoped.md" <<'EOF'
# The same fix from the other side
- Fixed for TASK-999 with the pointer on `main` on 2026-05-06.
EOF


result=$("$root/scripts/cross-page-claims.sh" "$tmp")
printf '%s\n' "$result" | grep -q 'TASK-123' || { echo "FAIL cross-page candidate missing" >&2; exit 1; }
printf '%s\n' "$result" | grep -q 'unrelated service' && { echo "FAIL unrelated claim reported" >&2; exit 1; }
printf '%s\n' "$result" | grep -q 'Old status' && { echo "FAIL distant status reported" >&2; exit 1; }
printf '%s\n' "$result" | grep -q 'pointer.md' && { echo "FAIL status pointer reported" >&2; exit 1; }
printf '%s\n' "$result" | grep -q 'TASK-777' || { echo "FAIL long multi-clause claim missed" >&2; exit 1; }
printf '%s\n' "$result" | grep -q 'generic.md' && { echo "FAIL clause inheriting both ticket and date reported" >&2; exit 1; }
printf '%s\n' "$result" | grep -q 'TASK-888' && { echo "FAIL agreeing claims reported (negation after the verb)" >&2; exit 1; }
printf '%s\n' "$result" | grep -q 'TASK-999' && { echo "FAIL negation scoped to another predicate reported" >&2; exit 1; }
echo "PASS cross-page claim scan"
