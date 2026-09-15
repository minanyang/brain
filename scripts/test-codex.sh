#!/usr/bin/env bash
# Fabricated integration fixtures only. No real transcripts, vaults, or model calls.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/brain-test.XXXXXXXX")
trap 'rm -rf "$work"' EXIT
export BRAIN_CONFIG="$work/config.json" BRAIN_ROOT="$root"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=Fixture GIT_COMMITTER_NAME=Fixture
export GIT_AUTHOR_EMAIL=fixture@example.invalid GIT_COMMITTER_EMAIL=fixture@example.invalid
mkdir -p "$work/bin" "$work/claude/acme" "$work/codex/2026/09/15" "$work/project" "$work/codex-home"
export PATH="$work/bin:$PATH"
cat > "$work/bin/claude" <<'SH'
#!/usr/bin/env bash
cat >/dev/null
printf '## What happened\n- Reviewed retry behavior.\n\n## Learned\n- [project:acme-billing] Retries use a stable key.\n'
SH
cat > "$work/bin/codex" <<'SH'
#!/usr/bin/env bash
out=""
while [ $# -gt 0 ]; do
  case "$1" in --output-last-message) out="$2"; shift ;; esac
  shift
done
prompt=$(cat)
if [ -n "${BRAIN_TEST_FAIL:-}" ]; then exit 1; fi
if [ -n "${BRAIN_TEST_SECRET:-}" ]; then
  printf '## Continued (%s)\n### What happened\n- password=abcdefgh1234\n' "$(date +%Y-%m-%d)" > "$out"; exit 0
fi
header=$(printf '%s\n' "$prompt" | sed -n "s/.*headed exactly '\(## Continued[^']*\)'.*/\1/p" | head -1)
if [ -n "$header" ]; then printf '%s\n\n### What happened\n- Continued the review.\n' "$header" > "$out"
else printf '## What happened\n- Reviewed retry behavior.\n\n## Learned\n- [project:acme-billing] Retries use a stable key.\n' > "$out"; fi
SH
chmod +x "$work/bin/claude" "$work/bin/codex"
"$root/scripts/init-vault.sh" "$work/vault" --name shared --include "$work/project/**" >/dev/null
jq --arg a "$work/claude" --arg b "$work/codex" '.transcripts=[$a] | .codex_transcripts=[$b]' "$BRAIN_CONFIG" > "$work/config.tmp"
mv "$work/config.tmp" "$BRAIN_CONFIG"
text=$(printf 'Investigate retry behavior for acme-billing. %.0s' {1..16})
cf="$work/claude/acme/session.jsonl" xf="$work/codex/2026/09/15/rollout.jsonl"
jq -nc --arg cwd "$work/project" --arg text "$text" '{type:"user",sessionId:"shared-id",cwd:$cwd,timestamp:"2026-09-15T10:00:00Z",message:{content:$text}}' > "$cf"
jq -nc --arg cwd "$work/project" '{type:"session_meta",timestamp:"2026-09-15T10:00:00Z",payload:{id:"shared-id",cwd:$cwd,source:"cli",timestamp:"2026-09-15T10:00:00Z",git:{branch:"main"}}}' > "$xf"
jq -nc '{type:"response_item",payload:{type:"message",role:"developer",content:[{type:"input_text",text:"PRIVATE SYSTEM RULES"}]}}' >> "$xf"
jq -nc '{type:"response_item",payload:{type:"reasoning",summary:[{text:"PRIVATE REASONING"}]}}' >> "$xf"
jq -nc '{type:"response_item",payload:{type:"message",role:"user",content:[{type:"input_text",text:"<environment_context>INJECTED</environment_context>"}]}}' >> "$xf"
jq -nc --arg text "$text" '{type:"response_item",timestamp:"2026-09-15T10:01:00Z",payload:{type:"message",role:"user",content:[{type:"input_text",text:$text}]}}' >> "$xf"
# Event mirrors are ignored so user/assistant messages are not duplicated.
jq -nc '{type:"event_msg",payload:{type:"user_message",message:"DUPLICATE EVENT"}}' >> "$xf"
"$root/scripts/extract-transcript.sh" --meta "$xf" | jq -e '.host=="codex" and .session=="shared-id" and .turns==1' >/dev/null
clean=$("$root/scripts/extract-transcript.sh" "$xf")
! printf '%s' "$clean" | grep -qE 'PRIVATE|INJECTED|DUPLICATE'
[ "$(printf '%s' "$clean" | grep -c USER:)" = 1 ]
end=$(wc -c < "$xf" | tr -d ' ')
# An unfinished line larger than the former 64 KiB tail limit is not consumed.
printf '{"unfinished":"' >> "$xf"
dd if=/dev/zero bs=70000 count=1 2>/dev/null | tr '\0' x >> "$xf"
[ "$("$root/scripts/extract-transcript.sh" --meta "$xf" | jq .end)" = "$end" ]
head -c "$end" "$xf" > "$work/complete"; mv "$work/complete" "$xf"
printf 'ok rollout extraction, injection filtering, duplicate events, partial lines\n'

"$root/scripts/distill.sh" "$cf" >/dev/null
"$root/scripts/distill.sh" --provider codex "$xf" >/dev/null
state="$work/vault/.state/distilled.json"
jq -e 'length==2 and .["shared-id"].host=="claude" and .["codex:shared-id"].host=="codex"' "$state" >/dev/null
digest=$(jq -r '.["codex:shared-id"].digest' "$state")
case "$digest" in sources/sessions/codex/*) ;; *) exit 1 ;; esac
[ "$(find "$work/vault/sources/sessions" -name '*.md' | wc -l | tr -d ' ')" = 2 ]
before=$(git -C "$work/vault" rev-parse HEAD)
"$root/scripts/distill.sh" --all --provider codex --jobs 2 >/dev/null
[ "$before" = "$(git -C "$work/vault" rev-parse HEAD)" ]
# A resumed session appends and becomes pending again.
sed 's/ingested: false/ingested: true/' "$work/vault/$digest" > "$work/digest"; mv "$work/digest" "$work/vault/$digest"
jq -nc --arg text "$text" '{type:"response_item",timestamp:"2026-09-15T11:00:00Z",payload:{type:"message",role:"assistant",content:[{type:"output_text",text:$text}]}}' >> "$xf"
"$root/scripts/distill.sh" --provider codex "$xf" >/dev/null
grep -q '^## Continued' "$work/vault/$digest"
grep -q '^ingested: false' "$work/vault/$digest"
"$root/scripts/ingest-prep.sh" --vault shared > "$work/prep"
grep -q 'sources/sessions/codex/' "$work/prep"
grep -q 'sources/sessions/claude/' "$work/prep"
printf 'ok shared routing, separate host sources, idempotency, resumed session, recursive prep\n'

# Failure and gate rejection leave the offset unchanged, so a retry is possible.
offset=$(jq '.["codex:shared-id"].offset' "$state")
jq -nc --arg text "$text" '{type:"response_item",timestamp:"2026-09-15T12:00:00Z",payload:{type:"message",role:"user",content:[{type:"input_text",text:$text}]}}' >> "$xf"
BRAIN_TEST_FAIL=1 "$root/scripts/distill.sh" --provider codex "$xf" >/dev/null
[ "$offset" = "$(jq '.["codex:shared-id"].offset' "$state")" ]
BRAIN_TEST_SECRET=1 "$root/scripts/distill.sh" --provider codex "$xf" >/dev/null
[ "$offset" = "$(jq '.["codex:shared-id"].offset' "$state")" ]
printf 'ok failed model and secret gate preserve retry state\n'

lease=$("$root/scripts/write-lock.sh" acquire "$work/vault")
! "$root/scripts/write-lock.sh" acquire "$work/vault" 2>/dev/null
! "$root/scripts/write-lock.sh" release "$work/vault" wrong 2>/dev/null
"$root/scripts/ingest-prep.sh" --vault shared --lease "$lease" >/dev/null
printf '%s\n' "$digest" > "$work/sources"
"$root/scripts/finish.sh" --vault "$work/vault" --op ingest --lease "$lease" --sources "$work/sources" >/dev/null
[ -f "$work/vault/.state/lock/owner" ]
"$root/scripts/write-lock.sh" release "$work/vault" "$lease"
[ ! -d "$work/vault/.state/lock" ]
grep -q '^ingested: true' "$work/vault/$digest"
printf 'ok cross-call writer lease, competing writer rejection, finish, release\n'

printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo existing"}]}]}}\n' > "$work/codex-home/hooks.json"
"$root/scripts/install-codex.sh" --codex-home "$work/codex-home" >/dev/null
"$root/scripts/install-codex.sh" --codex-home "$work/codex-home" >/dev/null
jq -e '.hooks.SessionStart|length==2' "$work/codex-home/hooks.json" >/dev/null
grep -q 'echo existing' "$work/codex-home/hooks.json"
grep -q '^name: brain-query' "$work/codex-home/skills/brain-query/SKILL.md"
grep -q '^---$' "$work/codex-home/skills/brain-query/SKILL.md"
! grep -q '^"---' "$work/codex-home/skills/brain-query/SKILL.md"
! grep -q 'CLAUDE_PLUGIN_ROOT' "$work/codex-home/skills/brain-query/SKILL.md"
! grep -q '^argument-hint:' "$work/codex-home/skills/brain-query/SKILL.md"
[ "$(grep -c '^<!-- brain-codex -->' "$work/vault/AGENTS.md")" = 1 ]
printf 'ok repeatable install, existing hooks preserved, shared vault instructions\n'
printf 'PASS Codex integration fixtures\n'
