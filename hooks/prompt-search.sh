#!/usr/bin/env bash
# UserPromptSubmit hook (sync): put the vault pages that answer this question in front of the
# agent, without being asked.
#
# Why this exists: measured on 2026-10-15 across 40 real sessions, the injected session-start
# brief reached 37 of them and a vault page was opened in 4; measured across 56 sessions where
# a vault lookup would have helped, the registered search tool was invoked organically in 1.
# Delivery is push, not pull — a tool in the list is not a tool that gets called — and the one
# thing the brief cannot do is answer a question it was written before anyone asked.
#
# Reads files only. No model call, no network, no write.
set -u
[ "${BRAIN_INNER:-}" = 1 ] && exit 0
root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -f "${BRAIN_CONFIG:-$HOME/.brain/config.json}" ] || exit 0
. "$root/scripts/lib.sh"

# Off until measured. The one thing established about the read side is that across 56 sessions
# where a vault lookup would have helped, the agent chose the search tool once — which is a
# reason to measure before pushing, not a reason to push. On by default this spends up to
# BUDGET characters on every prompt past the gate, and a page that is merely plausible is worse
# than none, because the agent cannot tell. The failure is silent either way: nothing in a
# transcript distinguishes an injection that helped from one that was ignored or that misled.
#
# `inject_brief` carries the same switch for the same reason, and its default has never moved
# on taste: it moved when a 120-run benchmark said what it was worth.
[ "$(config_get '.push_pages' false)" = true ] || exit 0

in=$(cat)
prompt=$(printf '%s' "$in" | jq -r '.prompt // empty' 2>/dev/null) || exit 0
[ -n "$prompt" ] || exit 0
cwd=$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null)

# The length gate. Measured over 2,650 real interactive prompts since 2026-10-01, the share
# carrying at least one term rare enough to rank anything runs 25% under 20 characters, 53% at
# 20–39, 69% at 40–79 and 96% at 80 and over — 88% at 40 and over, which is what this fires
# on. Under the gate a prompt is almost always a follow-up ("why?", "繼續", "do it") whose
# subject is in the turn above and not in its own words, so searching it spends a grep to
# inject the pages that answer the last question again.
#
# jq counts codepoints; `${#prompt}` counts bytes under a non-UTF-8 locale, which would read a
# 14-character Mandarin question as 42 and fire on it.
n=$(printf '%s' "$in" | jq -r '.prompt | length' 2>/dev/null) || exit 0
case "$n" in ''|*[!0-9]*) exit 0 ;; esac
[ "$n" -ge 40 ] || exit 0

# A command's arguments are the user's words, but the command name and its injected body are
# not a question about the vault. Both host spellings are listed because this script runs on
# both: Claude Code writes `/brain:ingest`, Codex writes `$brain-ingest`.
case "$prompt" in '<command-name>'*|'/'*|'$'*) exit 0 ;; esac

# The budget ladder, which is OpenViking's: the richest form that fits, then addresses only,
# then nothing. A result is never truncated to fit — a page quoted halfway through reads as the
# whole of what the page says, and that is worse than not quoting it, because the agent cannot
# tell the difference.
BUDGET=2000
find_pages() {  # find_pages <format>
  "$root/scripts/search.sh" --cwd "${cwd:-$PWD}" --require-rare-term --format "$1" -- "$prompt" 2>/dev/null
}
out=$(find_pages context)
case "$out" in
  'No Brain vault covers'*|'No page mentions'*|'Give at least one'*|'') exit 0 ;;
esac
if [ "${#out}" -gt "$BUDGET" ]; then
  out=$(find_pages pointer)
  [ "${#out}" -gt "$BUDGET" ] && exit 0
fi
[ -n "$out" ] || exit 0

# The marker is what keeps this out of the vault. An injected block lands inside the user's
# turn, and distill reads that turn as the user's own words, so without a region it can strip
# the vault's own prose would come back as a session source and be re-filed as something the
# user said — which is the loop 0.6.11 was released to close, arriving by a second door.
# scripts/extract-transcript.sh strips exactly these two lines and everything between them.
jq -n --arg c "<brain-vault>
$out
</brain-vault>" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
