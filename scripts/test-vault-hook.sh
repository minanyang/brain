#!/usr/bin/env bash
# test-vault-hook.sh — behaviour tests for the vault pre-commit validator, on a throwaway
# git repository.
#
# What each case protects: a mechanism that blocks the sanctioned write path is worse than no
# mechanism, because the first thing anyone does is take it off; and one that lets through the
# three breaches it was written for is decoration. Both failures are quiet, so both are here.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
t="$(mktemp -d)"
trap 'rm -r -f "$t"' EXIT

pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  ok %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s — %s\n' "$1" "$2" >&2; }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Fixture GIT_COMMITTER_NAME=Fixture
export GIT_AUTHOR_EMAIL=fixture@example.invalid GIT_COMMITTER_EMAIL=fixture@example.invalid

mkdir -p "$t/topics" "$t/sources/sessions"
cd "$t"
git init -q .
printf 'err\n' > .git/info/exclude   # the test writes stderr beside the repo it is testing
printf 'generated\n' > index.md
printf 'generated\n' > brief.md
printf 'generated\n' > log.md
printf -- '---\ntitle: T\ntype: topic\nupdated: 2026-03-04\n---\n\nA page.\n\n## Conflicts\n- [open] 2026-03-01: "one" (→ sources/sessions/a.md) vs "two" (→ sources/sessions/b.md)\n' > topics/a.md
printf 'line one\nline two\nline three\n' > sources/sessions/a.md
git add -A >/dev/null; git commit -q -m init

# The hook runs from .git/hooks as a two-line shim, which is how the logic stays with the
# plugin version rather than being copied into a directory git does not track.
printf '#!/usr/bin/env bash\nexec %q\n' "$here/vault-hook.sh" > .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

try() { git commit -q -m "$1" 2>"$t/err"; }
blocked() { if try "$1"; then bad "$2" "the commit went through"; else ok "$2"; fi; }
allowed() { if try "$1"; then ok "$2"; else bad "$2" "$(cat "$t/err")"; fi; }
undo() { git reset -q --hard HEAD; }

# 1. Generated files.
printf 'hand written\n' > brief.md; git add brief.md
blocked 'edit brief' "a hand-edited brief.md is refused"
grep -q 'generated' "$t/err" || bad "the refusal says why brief.md is refused" "$(cat "$t/err")"
undo

# finish.sh is the sanctioned path and must not be blocked by its own guard.
printf 'regenerated\n' > brief.md; git add brief.md
if BRAIN_FINISH=1 git commit -q -m 'finish' 2>"$t/err"; then ok "finish.sh writing the generated files is allowed"
else bad "finish.sh writing the generated files is allowed" "$(cat "$t/err")"; fi

# The check that must survive the exemption: finish.sh is the only sanctioned write path, so an
# agent that resolves a conflict and then runs finish.sh is the scenario the rule exists for. A
# blanket exemption made this unreachable, which is how the first version of the hook managed to
# pass its own tests while guarding nothing that mattered.
printf -- '---\ntitle: T\ntype: topic\nupdated: 2026-03-05\n---\n\nA page.\n\n## Conflicts\n- [resolved 2026-03-05] "one" — decided: one\n' > topics/a.md
git add topics/a.md
if BRAIN_FINISH=1 git commit -q -m 'resolve via finish' 2>"$t/err"; then
  bad "finish.sh does not exempt the conflict rule" "the commit went through"
else ok "finish.sh does not exempt the conflict rule"; fi
undo

# finish.sh flips a source's ingested: line, which deletes one, so that it must exempt.
printf 'line one\nline three\n' > sources/sessions/a.md; git add sources/sessions/a.md
if BRAIN_FINISH=1 git commit -q -m 'mark ingested' 2>"$t/err"; then ok "finish.sh may rewrite a source line"
else bad "finish.sh may rewrite a source line" "$(cat "$t/err")"; fi
undo
# That commit left the digest two lines long. Put the third back before the append-only cases
# below, which need a line to lose; a fixture that carries state between cases reports the next
# one on the wrong evidence, which is what it did.
printf 'line one\nline two\nline three\n' > sources/sessions/a.md
git add sources/sessions/a.md; BRAIN_FINISH=1 git commit -q -m 'restore digest'

# 2. Only a human resolves a conflict.
printf -- '---\ntitle: T\ntype: topic\nupdated: 2026-03-05\n---\n\nA page.\n\n## Conflicts\n- [resolved 2026-03-05] "one" — decided: one\n' > topics/a.md
git add topics/a.md
blocked 'resolve it myself' "a [resolved] conflict with no human citation is refused"
undo

printf -- '---\ntitle: T\ntype: topic\nupdated: 2026-03-05\n---\n\nIt is one (→ human, 2026-03-05).\n\n## Conflicts\n- [resolved 2026-03-05] "one" — decided: one\n' > topics/a.md
git add topics/a.md
allowed 'human resolved it' "a [resolved] conflict the page cites a human for is allowed"

# [unresolvable] is a human's mark for the same reason, so it is held to the same test.
printf -- '---\ntitle: U\ntype: topic\nupdated: 2026-03-05\n---\n\nA page.\n\n## Conflicts\n- [unresolvable 2026-03-05] "one" vs "two" — the log was rotated\n' > topics/b.md
git add topics/b.md
blocked 'mark it unresolvable' "an [unresolvable] conflict with no human citation is refused"
undo

# 3. Provenance is append-only.
printf 'line one\nline three\n' > sources/sessions/a.md; git add sources/sessions/a.md
blocked 'drop a line from a digest' "a digest that loses a line is refused"
grep -q 'append-only' "$t/err" || bad "the refusal says why the digest is refused" "$(cat "$t/err")"
undo

# Appending is how distill continues a resumed session, so it must pass.
printf 'line one\nline two\nline three\nline four\n' > sources/sessions/a.md
git add sources/sessions/a.md
allowed 'append to a digest' "appending to a digest is allowed"

# A new source is not a modification at all.
printf 'a new digest\n' > sources/sessions/c.md; git add sources/sessions/c.md
allowed 'add a digest' "adding a source is allowed"

# An ordinary page edit is the common case and must cost nothing.
printf -- '---\ntitle: T\ntype: topic\nupdated: 2026-03-06\n---\n\nIt is one (→ human, 2026-03-05). More detail.\n\n## Conflicts\n- [resolved 2026-03-05] "one" — decided: one\n' > topics/a.md
git add topics/a.md
allowed 'ordinary edit' "an ordinary page edit is allowed"

# The escape hatch stays open: a human who means it should not have to fight the tooling.
printf 'hand written again\n' > brief.md; git add brief.md
if git commit -q --no-verify -m 'override' 2>"$t/err"; then ok "--no-verify overrides the validator"
else bad "--no-verify overrides the validator" "$(cat "$t/err")"; fi

printf 'test-vault-hook: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
