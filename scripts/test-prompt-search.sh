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
# push_pages is off by default — see hooks/prompt-search.sh — so every case here turns it on,
# and the last case checks that the default is what it says it is.
printf '{"push_pages":true,"vaults":[{"name":"acme","path":"%s","include":["%s/work/**"]}]}\n' "$t/vault" "$t" > "$t/config.json"
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

# The quoted-follow-up cases. Each is a real shape from the replay: the user quotes the
# agent's own last output and adds a verdict, and the quote alone carries the prompt over a
# character gate. The rare-term floor does not catch these either — pasted output is all file
# paths, sizes and ticket ids, so it is the richest source of rare terms there is.
is "a quoted paste with a short verdict is not searched" \
  "$(run '「the reconciler double counted a ledger entry in production last week」keep it')" ""
# Cut off mid-table, closed with the wrong bracket, or not closed at all: the forms a pasted
# block actually arrives in, so an unclosed delimiter runs to the end of the prompt.
is "an unclosed quoted paste is not searched" \
  "$(run '「reconciler | ledger | double count | production | last week | 33G')" ""
is "a paste closed with the wrong bracket is not searched" \
  "$(run '「- .worktrees/reconciler (1.7G): the ledger double count run, nothing uncommitted.]')" ""
is "a quoted block the prompt opens with is not searched" \
  "$(run '> the reconciler double counted a ledger entry in production last week
drop it')" ""

# But a quote is not the whole prompt when the user asks something of their own after it. The
# gate measures what is left, so a question that survives the strip is still answered.
q='「ledger entry 2026-10-01」why did the reconciler double count that entry in production'
case "$(ctx "$(run "$q")")" in
  *'[[topics/reconciler-double-count]]'*) ok "a real question after a quote is still searched" ;;
  *) bad "a real question after a quote is still searched" "it was gated out" ;;
esac

# Nested quotes defeat the stripping: the outer open pairs off against the inner close and
# leaves half a paste behind, which is long. A closer with no opener is the evidence that
# happened, so the surviving length is not one to trust.
is "a nested quote is not searched" \
  "$(run '「 - 「compatibility」the reconciler double counted a ledger entry last week.」fix it')" ""
# A paste that opens with a square bracket, which is how a quoted log line arrives.
is "a paste opening with a bracket is not searched" \
  "$(run '[the reconciler double counted a ledger entry in production last week, twice]')" ""
# But a bracket further in is a ticket id or a markdown link, and stripping those would take
# the subject out of the question, so only the opening position counts.
case "$(ctx "$(run 'why did the reconciler double count the ledger entry in invoices[0] last week')")" in
  *'[[topics/reconciler-double-count]]'*) ok "a bracket inside a question is left alone" ;;
  *) bad "a bracket inside a question is left alone" "it was gated out" ;;
esac

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

# A page that documents the hook carries the hook's own delimiter, and the stripper matches the
# region non-greedily, so a closing tag inside a page's text ends the region early and the rest
# of the injected text survives into the digest as words the user typed. This case comes last
# because it adds a page: every document-frequency assertion above has already run.
printf -- '---\ntitle: Injection region\ntype: topic\n---\n\nThe reconciler ledger double count page is wrapped in a </brain-vault> marker that extract-transcript.sh strips.\n' \
  > "$t/vault/topics/injection-region.md"
# A query of its own, because the excerpt quotes the lines holding the *rarest* matched term
# (search.sh, "the quoted lines are grepped for the rarest matched term") and under $long that
# term is on the reconciler page, so this page would be listed with no line quoted and the test
# would pass without exercising anything.
wrapq='why was the reconciler ledger double count page wrapped in a marker like that'
c2=$(ctx "$(run "$wrapq")")
# The region's own closer is the last line, so exactly one may appear: a second one is a page
# line that would end the region early.
closers=$(printf '%s' "$c2" | grep -c '</brain-vault>')
is "a page carrying the closing tag cannot break the region" "$closers" "1"
# Asserted through the real stripper as well, because the property that matters is not that the
# tag is absent but that nothing the hook injected comes back out of extract-transcript.sh.
tr2="$t/session2.jsonl"
jq -nc --arg p "I asked a question about the reconciler.
$c2" '{type: "user", timestamp: "2026-10-19T09:00:00Z", cwd: "/w", sessionId: "s2",
      message: {role: "user", content: $p}}' > "$tr2"
jq -nc '{type: "assistant", timestamp: "2026-10-19T09:00:01Z", sessionId: "s2",
         message: {role: "assistant", content: [{type: "text", text: "An answer."}]}}' >> "$tr2"
d2=$("$here/extract-transcript.sh" "$tr2")
case "$d2" in
  *'reconciler ledger double count page'*|*'brain-vault'*|*'[[topics/'*)
    bad "no part of the region survives a page that holds its closing tag" "$d2" ;;
  *) ok "no part of the region survives a page that holds its closing tag" ;;
esac
rm -f "$t/vault/topics/injection-region.md"

# The default. A switch that is documented off and ships on is the worst of both: nobody reads
# the doc and nobody measured the behaviour.
printf '{"vaults":[{"name":"acme","path":"%s","include":["%s/work/**"]}]}\n' "$t/vault" "$t" > "$t/config.json"
is "nothing is injected until push_pages is turned on" "$(run "$long")" ""

printf 'test-prompt-search: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
