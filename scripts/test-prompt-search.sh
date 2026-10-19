#!/usr/bin/env bash
# test-prompt-search.sh — behaviour tests for the UserPromptSubmit hook, on a throwaway vault.
#
# Each case is a thing that would break the mechanism it exists for: a gate that fires on the
# follow-up prompts it was measured to be useless on, a result injected past its budget with a
# page quoted halfway through, and — the one that matters most — an injected block that is not
# strippable, which would put the vault's own prose back into the vault as something the user
# said.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
t="$(mktemp -d)"
trap 'rm -r -f "$t"' EXIT

pass=0 fail=0
ok()  { pass=$((pass+1)); printf '  ok %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s — %s\n' "$1" "$2" >&2; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$3', got '$2'"; fi; }

mkdir -p "$t/vault/topics" "$t/work"
printf -- '---\ntitle: Reconciler double count\ntype: topic\n---\n\nThe reconciler counted a ledger entry twice.\n\nA line about the reconciler here.\nA line about the reconciler here.\nA line about the ledger here.\n' \
  > "$t/vault/topics/reconciler-double-count.md"
# Twelve pages, because document frequency says nothing below ten: `the` has to be on most of
# the vault for the rare-term floor to be the thing under test rather than vault size.
i=1
while [ "$i" -le 11 ]; do
  printf -- '---\ntitle: Filler %s\ntype: topic\n---\n\nA page about the release process.\n\nA line about the deploy here.\n' "$i" \
    > "$t/vault/topics/filler-$i.md"
  i=$((i + 1))
done
printf '{"vaults":[{"name":"acme","path":"%s","include":["%s/work/**"]}]}\n' "$t/vault" "$t" > "$t/config.json"
export BRAIN_CONFIG="$t/config.json"
export CLAUDE_PLUGIN_ROOT="$(cd "$here/.." && pwd)"

run() {  # run <prompt> [cwd] → the hook's stdout
  jq -n --arg p "$1" --arg c "${2:-$t/work}" '{prompt: $p, cwd: $c}' \
    | "$here/../hooks/prompt-search.sh" 2>/dev/null
}
ctx() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }

long='why did the reconciler double count a ledger entry in production last week'
out=$(run "$long")
is "a question over the gate is answered with context" \
  "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // "none"')" "UserPromptSubmit"
case "$(ctx "$out")" in
  *'[[topics/reconciler-double-count]]'*) ok "the page that answers it is named" ;;
  *) bad "the page that answers it is named" "$(ctx "$out")" ;;
esac

# The measured gate: under 40 characters, 25–53% of real prompts carry a term rare enough to
# rank anything, and the subject of a follow-up is in the turn above rather than in its words.
is "a short follow-up is not searched" "$(run 'why?')" ""
is "a 39-character prompt is under the gate" "$(run "$(printf 'reconciler ledger double count prod abc')")" ""
# 40 codepoints of Mandarin is 120 bytes, so a byte count would read this as over the gate.
is "a short Mandarin prompt is measured in characters, not bytes" "$(run '為什麼對帳會重複計算？')" ""

# A slash command's body is injected text, not a question about the vault.
is "a slash command is not searched" "$(run '/brain:ingest reconciler ledger double count now')" ""

# Nothing to say is said by saying nothing: an empty additionalContext would reach the model as
# a vault that holds nothing on the subject.
is "a question nothing matches injects nothing" \
  "$(run 'how does the kafka consumer group rebalance itself on restart')" ""
is "a directory no vault covers injects nothing" "$(run "$long" "$t/elsewhere")" ""

# The anti-loop region. distill reads an injected block as the user's own words, so the block
# has to be strippable by exactly what extract-transcript.sh strips.
c=$(ctx "$(run "$long")")
case "$c" in
  '<brain-vault>'*'</brain-vault>') ok "the injected block is a closed region" ;;
  *) bad "the injected block is a closed region" "$c" ;;
esac
# Asserted through the real extract-transcript.sh, not an equivalent expression: the whole
# point is that the one script distill runs strips this, and a test of a copy of its jq would
# pass while the script itself kept the region.
tr="$t/session.jsonl"
jq -nc --arg p "I asked a question about the reconciler.
$c" '{type: "user", timestamp: "2026-10-19T09:00:00Z", cwd: "/w", sessionId: "s1",
      message: {role: "user", content: $p}}' > "$tr"
jq -nc '{type: "assistant", timestamp: "2026-10-19T09:00:01Z", sessionId: "s1",
         message: {role: "assistant", content: [{type: "text", text: "An answer."}]}}' >> "$tr"
digest=$("$here/extract-transcript.sh" "$tr")
case "$digest" in
  *'I asked a question about the reconciler.'*) ok "the user's own words survive the strip" ;;
  *) bad "the user's own words survive the strip" "$digest" ;;
esac
case "$digest" in
  *'brain-vault'*|*'[[topics/reconciler-double-count]]'*|*'Read one before stating facts'*)
    bad "no injected vault page reaches the digest" "$digest" ;;
  *) ok "no injected vault page reaches the digest" ;;
esac

# The budget ladder. With the budget forced below the rich form, the hook degrades to page
# addresses rather than truncating a page's quoted lines — a page quoted halfway through reads
# as the whole of what the page says.
narrow=$(sed 's|^BUDGET=2000$|BUDGET=200|' "$here/../hooks/prompt-search.sh")
printf '%s' "$narrow" > "$t/narrow.sh"; chmod +x "$t/narrow.sh"
nout=$(jq -n --arg p "$long" --arg c "$t/work" '{prompt: $p, cwd: $c}' | "$t/narrow.sh" 2>/dev/null)
nctx=$(ctx "$nout")
case "$nctx" in
  *'do not guess a path that is not listed'*) ok "a result over budget degrades to addresses" ;;
  *) bad "a result over budget degrades to addresses" "$nctx" ;;
esac
case "$nctx" in
  *'A line about reconciler here'*) bad "the degraded form quotes no page lines" "it still quoted one" ;;
  *) ok "the degraded form quotes no page lines" ;;
esac

# And with no budget at all it drops, rather than injecting a header with nothing under it.
printf '%s' "$(sed 's/^BUDGET=2000$/BUDGET=1/' "$here/../hooks/prompt-search.sh")" > "$t/none.sh"
chmod +x "$t/none.sh"
is "no budget at all injects nothing" \
  "$(jq -n --arg p "$long" --arg c "$t/work" '{prompt: $p, cwd: $c}' | "$t/none.sh" 2>/dev/null)" ""

# An inner run is the plugin's own agent working, and injecting into it would feed the vault to
# the process that writes the vault.
is "an inner run is left alone" "$(BRAIN_INNER=1 run "$long")" ""

printf 'test-prompt-search: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
