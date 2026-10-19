#!/usr/bin/env bash
# vault-hook.sh — the vault's pre-commit validator. Run from a vault's .git/hooks/pre-commit,
# which is a two-line shim so that this logic travels with the plugin version instead of being
# copied into a directory git does not track.
#
# Why a hook at all: the rules it enforces are the ones the agent will negotiate with rather
# than forget — that only a human resolves a conflict, that generated files are generated, that
# provenance is append-only — and until now they were prose in a skill. Prose is advice; a
# non-zero exit is a mechanism. This is Letta's precedent (a zero-dependency validator on the
# commit path) applied to the three invariants whose breach leaves no trace.
#
# It gates the staged tree only, so it has nothing to say about the working copy.
#
# BRAIN_FINISH=1, set by finish.sh and init-vault.sh, exempts **two of the three checks and not
# the third**, and that distinction is the whole value of the hook. A blanket exemption was the
# first version and it was useless: finish.sh is the only sanctioned write path, so an agent
# that resolves a conflict and then runs finish.sh is the exact scenario the conflict rule
# guards against, and a guard that cannot fire on the main path is decoration. The two it does
# exempt are things finish.sh legitimately does — regenerate the generated files, and flip a
# source's `ingested:` line — and blocking those would block the write path itself, which is
# worse than no guard because the first thing anyone does is take it off.
#
# `--no-verify` is git's own escape and is deliberately left working; a human who means it
# should not have to fight the tooling, and the point is that skipping it is a decision rather
# than the default.
set -uo pipefail
finish="${BRAIN_FINISH:-}"

fail=0
say() { printf 'brain: %s\n' "$1" >&2; fail=1; }
staged() { git diff --cached --name-only --diff-filter=ACM -- "$@" 2>/dev/null; }

# 1. Generated files are generated. index.md, brief.md and log.md are rebuilt from the pages by
#    index.sh and finish.sh, so a hand edit is overwritten on the next operation and the drift
#    is invisible until someone reads a stale brief.
for g in index.md brief.md log.md; do
  [ "$finish" = 1 ] && break   # finish.sh is what regenerates them
  if [ -n "$(staged "$g")" ]; then
    say "$g is generated — finish.sh rebuilds it from the pages, so this edit will be overwritten. Unstage it and change the page instead."
  fi
done

# 2. Only a human resolves a conflict. The losing claim leaves no trace, so a wrong silent merge
#    cannot be found later; the citation is what distinguishes a decision from an agent that got
#    tired of the entry. Checked on the staged content rather than the diff, because an entry
#    re-prefixed and then reflowed shows up as an unrelated line.
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$f" in sources/*) continue ;; esac
  blob=$(git show ":$f" 2>/dev/null) || continue
  marks=$(printf '%s' "$blob" | grep -c '^- \[\(resolved\|unresolvable\)' 2>/dev/null || true)
  [ "${marks:-0}" -gt 0 ] || continue
  if ! printf '%s' "$blob" | grep -q '(→ human,'; then
    say "$f carries a [resolved] or [unresolvable] conflict but the page cites no human decision. Only a human may settle one: put the winning claim in the body cited (→ human, <date>), or leave the entry [open]."
  fi
done < <(staged '*.md')

# 3. Provenance is append-only. A digest or a ref is the record of what a session actually said;
#    rewriting one re-writes the evidence every page above it cites. Appending is how distill
#    continues a resumed session, so the check is on deleted lines, not on modification.
while IFS= read -r line; do
  [ "$finish" = 1 ] && break   # finish.sh flips a source's `ingested:` line, which deletes one
  [ -n "$line" ] || continue
  del=$(printf '%s' "$line" | awk '{print $2}')
  path=$(printf '%s' "$line" | cut -f3-)
  case "$del" in ''|*[!0-9]*) continue ;; esac
  [ "$del" -gt 0 ] || continue
  say "$path loses $del line(s) — sources/ is append-only provenance: the pages above it cite what it said. Restore the lines, or add a new source."
done < <(git diff --cached --numstat --diff-filter=M -- sources/ 2>/dev/null)

if [ "$fail" != 0 ]; then
  printf 'brain: commit refused by the vault validator. `git commit --no-verify` overrides it if you mean to.\n' >&2
  exit 1
fi
exit 0
