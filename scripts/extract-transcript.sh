#!/usr/bin/env bash
# Turn a Claude Code transcript (JSONL) into clean conversation text.
#
#   extract-transcript.sh <transcript.jsonl> [byte-offset]   → text on stdout
#   extract-transcript.sh --meta <transcript.jsonl>          → JSON on stdout
#
# Text mode reads from the byte offset (default 0) up to the last complete
# line and prints one block per turn. Tool results are truncated, thinking
# blocks and injected skill prompts are dropped, system-reminder tags are
# stripped. Meta mode reports session id, cwd, branch, title, first/last
# timestamp, and the byte offset text mode would stop at.
#
# Any other agent's transcript can be adapted by producing the same output:
# "[YYYY-MM-DD HH:MM] ROLE: text" blocks separated by blank lines.
set -euo pipefail

mode=text
if [ "${1:-}" = "--meta" ]; then mode=meta; shift; fi
file="${1:?transcript path}"
offset="${2:-0}"

# Stop at the last newline so a line still being written is never parsed.
size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file")
end=$size
if [ "$size" -gt 0 ] && [ "$(tail -c 1 "$file" | od -An -c | tr -d ' ')" != '\n' ]; then
  # Byte length of the unterminated last line, subtracted from the size.
  partial=$(tail -c 65536 "$file" | LC_ALL=C awk 'BEGIN{RS="\n"} {l=length($0)} END{print l+0}')
  end=$((size - partial))
fi

slice() { head -c "$end" "$file" | tail -c +"$((offset + 1))"; }

if [ "$mode" = meta ]; then
  head -c "$end" "$file" | jq -n -R --arg end "$end" '
    reduce (inputs | fromjson?) as $l (
      {session: null, cwd: null, branch: null, title: null, first_ts: null, last_ts: null, turns: 0};
      if $l.type == "ai-title" then .title = $l.aiTitle
      elif ($l.type == "user" or $l.type == "assistant") and ($l.isMeta != true) and ($l.isSidechain != true) then
        .session //= $l.sessionId
        | .cwd //= $l.cwd
        | .branch //= $l.gitBranch
        | .first_ts //= $l.timestamp
        | .last_ts = ($l.timestamp // .last_ts)
        | (if $l.type == "user" and ($l.message.content | type) == "string" then
             .first_prompt //= $l.message.content else . end)
        | .turns += 1
      else . end)
    | .title = (.title // (.first_prompt // ""
        | if test("<command-name>") then
            "/" + ((capture("<command-name>(?<c>[^<]*)</command-name>").c // "") | ltrimstr("/"))
            + " " + (capture("<command-args>(?<a>[^<]*)</command-args>").a // "")
          else gsub("<system-reminder>(?:.|\\n)*?</system-reminder>"; "") end
        | gsub("\\s+"; " ") | gsub("^ | $"; "") | .[0:60]))
    | .end = ($end | tonumber)
    | del(.first_prompt)'
  exit 0
fi

slice | jq -r -R '
  def clip($n): if length > $n then .[0:$n] + " […]" else . end;
  def ts: (.timestamp // "" | .[0:16] | sub("T"; " "));
  def strip_reminders: gsub("<system-reminder>(?:.|\\n)*?</system-reminder>"; "") | gsub("^\\s+|\\s+$"; "");
  def tool_summary:
    .name as $n
    | if $n == "Bash" then (.input.command // "" | clip(300))
      elif ($n == "Edit" or $n == "Write" or $n == "Read" or $n == "NotebookEdit") then (.input.file_path // "")
      elif $n == "Agent" then (.input.description // "" )
      elif $n == "Skill" then (.input.skill // "")
      else (.input | tostring | clip(200)) end;
  def result_text:
    if type == "string" then .
    elif type == "array" then map(select(.type == "text") | .text) | join("\n")
    else tostring end;
  def user_text:
    if test("<command-name>") then
      "ran " + (capture("<command-name>(?<c>[^<]*)</command-name>").c // "")
      + " " + (capture("<command-args>(?<a>[^<]*)</command-args>").a // "")
    elif test("<local-command-stdout>") then
      "(command output) " + (capture("<local-command-stdout>(?<o>(?:.|\\n)*?)</local-command-stdout>").o // "" | clip(300))
    else strip_reminders | clip(4000) end;

  fromjson? | select(.type == "user" or .type == "assistant")
  | select(.isMeta != true and .isSidechain != true)
  | . as $l
  | if .type == "user" then
      (if (.message.content | type) == "string" then
         [.message.content | user_text]
       else
         [.message.content[] |
           if .type == "text" then (.text | user_text)
           elif .type == "tool_result" then "RESULT: " + (.content | result_text | gsub("\\s+"; " ") | clip(300))
           else empty end]
       end)
      | map(select(length > 0))
      | if length == 0 then empty
        else map(if startswith("RESULT: ") then "[\($l | ts)] \(.)" else "[\($l | ts)] USER: \(.)" end) | join("\n") end
    else
      [.message.content[] |
        if .type == "text" then "[\($l | ts)] ASSISTANT: " + (.text | clip(4000))
        elif .type == "tool_use" then "[\($l | ts)] TOOL \(.name): " + tool_summary
        else empty end]
      | select(length > 0) | join("\n")
    end
  | . + "\n"'
