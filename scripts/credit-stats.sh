#!/usr/bin/env bash
# credit-stats.sh [--brief|--push|--both] [<transcript.jsonl>…] — of the pages this plugin put in
# front of the agent unasked, how many reached an answer? Default corpus: every transcript under
# ~/.claude/projects that holds an injection.
#
# Why this exists: the comment in hooks/prompt-search.sh says the failure is silent either way —
# nothing in a transcript distinguishes an injection that helped from one that was ignored or
# that misled. That holds only while nobody counts. The denominator is already on disk: the brief
# arrives as a SessionStart hook record and the pushed pages as a <brain-vault> region inside a
# user turn, so a transcript says exactly which sessions and turns were injected into.
#
# It reads finished transcripts rather than hooking the end of a turn, and that is why it is a
# script and not a hook. Measured live the count reads low and the error is invisible: the host
# writes the assistant message after the end-of-turn hook has already run, so the text carrying a
# citation is not on disk yet when the hook looks. That looks like the instruction failing rather
# than the clock.
#
# Two injections, two units, because they do not arrive at the same rate:
#   --brief  one list of pages per session (inject_brief). Unit: the session.
#   --push   the pages one question matched (push_pages). Unit: the turn.
#
# Three measures per unit, because the first is zero by construction until a crediting rule ships:
#   cited  the answer carries the citation marker.
#   named  the answer names an injected page at all ([[dir/page]]). Weaker — it cannot separate a
#          page used from a page echoed — but it is the only signal that exists before the rule,
#          so it is what a baseline can be made of.
#   read   the answer opened an injected page with Read. Reported against `named` rather than on
#          its own: an answer can name a page to satisfy a rule instead of because it opened one,
#          and an instrument blind to that is measuring compliance with itself.
set -uo pipefail

MARKER='from brain vault'   # matched case-insensitively
MODE=both

while [ $# -gt 0 ]; do
  case "$1" in
    --brief) MODE=brief; shift ;;
    --push)  MODE=push; shift ;;
    --both)  MODE=both; shift ;;
    --) shift; break ;;
    -*) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
    *) break ;;
  esac
done

base="${CLAUDE_PROJECTS:-$HOME/.claude/projects}"
collect() {  # collect <grep pattern> — transcripts holding that injection, newest last
  grep -rl "$1" "$base" --include='*.jsonl' 2>/dev/null | LC_ALL=C sort
}

# --- the brief: one record per session ---------------------------------------------------------
# The brief arrives as a hook_success attachment, not as a message, so it is addressed by record
# type rather than by role. Its page list is the [[dir/page]] addresses in that record.
brief_rows() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    jq -s -r --arg marker "$MARKER" '
      def pages: [scan("\\[\\[([a-z]+/[a-z0-9-]+)\\]\\]") | .[0]] | unique;
      (map(select(.type == "attachment")
           | select((.attachment.type // "") == "hook_success")
           | (.attachment | tostring)
           | select(test("Pages in vault")))
       | join("\n") | pages) as $inj
      | select($inj | length > 0)
      | (map(select(.type == "assistant")
             | .message.content // [] | .[]? | select(.type == "text") | .text) | join("\n")) as $ans
      | (map(select(.type == "assistant")
             | .message.content // [] | .[]?
             | select(.type == "tool_use") | select(.name == "Read")
             | .input.file_path // empty) | join(" ")) as $reads
      | ($ans | pages) as $m
      | [ (map(.sessionId // empty) | first // "?") [0:8],
          (map(.timestamp // empty) | first // "") [0:10],
          ($inj | length),
          (if ($ans | ascii_downcase | test($marker)) then 1 else 0 end),
          (if ([$inj[] | select(. as $p | $m | index($p))] | length) > 0 then 1 else 0 end),
          (if ([$inj[] | select(. as $p | $reads | contains($p + ".md"))] | length) > 0 then 1 else 0 end) ]
      | @tsv' "$f" 2>/dev/null
  done < <(collect 'Pages in vault')
}

# --- the push: one record per injected turn ----------------------------------------------------
# A turn starts at a typed user prompt — a user record whose content is a string — and runs to the
# next one. Tool results also arrive as user records, with array content, and are not turns.
push_rows() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    jq -s -r --arg marker "$MARKER" '
      def pages: [scan("\\[\\[([a-z]+/[a-z0-9-]+)\\]\\]") | .[0]] | unique;
      map(select(.type == "user" or .type == "assistant"))
      | reduce .[] as $l ([];
          if $l.type == "user" and ($l.message.content | type) == "string" then
            . + [{ s: ($l.sessionId // "?"), ts: ($l.timestamp // ""),
                   inj: ([$l.message.content
                          | scan("<brain-vault>(?:.|\\n)*?</brain-vault>")] | join("\n") | pages),
                   text: "", reads: [] }]
          elif length == 0 then .
          elif $l.type == "assistant" then
            (.[length - 1] |= (
              .text += ([$l.message.content // [] | .[]? | select(.type == "text") | .text] | join("\n"))
              | .reads += [$l.message.content // [] | .[]?
                           | select(.type == "tool_use") | select(.name == "Read")
                           | .input.file_path // empty]))
          else . end)
      | map(select(.inj | length > 0)) | .[]
      | (.text | pages) as $m | (.reads | join(" ")) as $reads
      | [ .s[0:8], .ts[0:16], (.inj | length),
          (if (.text | ascii_downcase | test($marker)) then 1 else 0 end),
          (if ([.inj[] | select(. as $p | $m | index($p))] | length) > 0 then 1 else 0 end),
          (if ([.inj[] | select(. as $p | $reads | contains($p + ".md"))] | length) > 0 then 1 else 0 end) ]
      | @tsv' "$f" 2>/dev/null
  done < <(collect 'brain-vault')
}

report() {  # report <label> <unit> <rows>
  local label="$1" unit="$2" rows="$3"
  if [ -z "$rows" ]; then
    printf '\n== %s ==\n(no %s carried an injection)\n' "$label" "$unit"
    return
  fi
  printf '\n== %s: %s %ss ==\n' "$label" "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')" "$unit"
  printf '%s\n' "$rows" | awk -F'\t' -v marker="$MARKER" -v unit="$unit" '
    { t++; p += $3; c += $4; n += $5; r += $6; if ($5 && !$6) nr++ }
    END {
      printf "injected %-12s %d\n", unit "s", t
      printf "pages injected      %d  (mean %.1f per %s)\n", p, (t ? p / t : 0), unit
      printf "cited               %d/%d  (%.3f)   marker: \"%s\"\n", c, t, (t ? c / t : 0), marker
      printf "named a page        %d/%d  (%.3f)\n", n, t, (t ? n / t : 0)
      printf "named and read it   %d/%d  (%.3f)\n", r, t, (t ? r / t : 0)
      printf "named, never read   %d   <- a mention the transcript cannot corroborate\n", nr
    }'
}

case "$MODE" in
  brief) report "inject_brief" session "$(brief_rows)" ;;
  push)  report "push_pages" turn "$(push_rows)" ;;
  both)  report "inject_brief" session "$(brief_rows)"; report "push_pages" turn "$(push_rows)" ;;
esac
