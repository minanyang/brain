#!/usr/bin/env bash
# test-status-compact.sh — behaviour tests for the pages status.sh names again after a
# compaction, on a throwaway vault.
#
# The mechanism is narrow because the host leaves no other opening: a PreCompact hook can block
# a compaction but cannot add anything to one, and a PostCompact hook cannot either, so
# SessionStart with source=compact is the only documented place to put something in front of the
# agent once the conversation has become a summary of itself.
#
# What can break silently here: a link to a page the vault does not have (the agent invents one,
# or a page is renamed) once killed the whole script, because the existence test was the last
# command in a loop body under `set -e`, and the symptom was this section never appearing —
# indistinguishable from the feature not being built.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
t="$(mktemp -d)"
trap 'rm -r -f "$t"' EXIT

pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  ok %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s — %s\n' "$1" "$2" >&2; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }

mkdir -p "$t/vault/topics" "$t/vault/sources/sessions" "$t/work"
for p in release-process dunning-schedule; do
  printf -- '---\ntitle: %s\ntype: topic\n---\n\nA lead.\n' "$p" > "$t/vault/topics/$p.md"
done
printf 'A brief.\n' > "$t/vault/brief.md"
printf '{"vaults":[{"name":"acme","path":"%s","include":["%s/work/**"]}],"inject_brief":true}\n' \
  "$t/vault" "$t" > "$t/config.json"
export BRAIN_CONFIG="$t/config.json"

# The third link is to a page the vault does not have, which is the case that used to kill it.
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"see [[topics/release-process]] and [[topics/dunning-schedule]] and [[topics/no-such-page]]"}]}}' \
  > "$t/tr.jsonl"

ctx() { "$here/status.sh" "$t/work" --source "$1" --transcript "${2:-$t/tr.jsonl}" 2>/dev/null \
  | jq -r '.hookSpecificOutput.additionalContext // ""'; }
cited() { ctx "$1" "${2:-}" | grep -c 'already cited' | tr -d ' '; }

is "a compaction names the pages the conversation cited" "$(cited compact)" "1"
is "a resume does too, having lost the same thing"       "$(cited resume)"  "1"
# A fresh start has nothing to re-open, and a clear is the user asking for one: listing what
# the cleared conversation read would argue with them.
is "a fresh start names none"                            "$(cited startup)" "0"
is "a clear names none"                                  "$(cited clear)"   "0"

out=$(ctx compact)
case "$out" in
  *'- [[topics/release-process]]'*) ok "an existing page is listed" ;;
  *) bad "an existing page is listed" "$out" ;;
esac
case "$out" in
  *'no-such-page'*) bad "a link the vault cannot resolve is dropped" "it was listed" ;;
  *) ok "a link the vault cannot resolve is dropped" ;;
esac
case "$out" in
  *'summary of a summary'*) ok "the reason to re-open the page is given, not just the path" ;;
  *) bad "the reason to re-open the page is given, not just the path" "$out" ;;
esac
# Addresses, not content: the point is to spend none of the context the compaction reclaimed.
case "$out" in
  *'A lead.'*) bad "no page content is quoted" "a page lead was inlined" ;;
  *) ok "no page content is quoted" ;;
esac

# A transcript that cites nothing adds nothing, rather than an empty heading.
printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"text","text":"no citations here"}]}}' \
  > "$t/bare.jsonl"
is "a conversation that cited nothing adds nothing" "$(cited compact "$t/bare.jsonl")" "0"

# A transcript path the host gave that no longer exists must not fail the hook: the brief still
# has to reach the session.
missing=$("$here/status.sh" "$t/work" --source compact --transcript "$t/gone.jsonl" 2>/dev/null \
  | jq -r '.hookSpecificOutput.additionalContext // ""')
case "$missing" in
  *'A brief.'*) ok "a missing transcript still lets the brief through" ;;
  *) bad "a missing transcript still lets the brief through" "$missing" ;;
esac

# The positional form is what hooks/codex-session.sh calls, and it must keep working.
if "$here/status.sh" "$t/work" >/dev/null 2>&1; then ok "the cwd-only call still works"
else bad "the cwd-only call still works" "non-zero exit"; fi

printf 'test-status-compact: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
