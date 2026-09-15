# Codex rollout JSONL, not the different `codex exec --json` event stream.
def text_content:
  [.content[]? | select(.type == "input_text" or .type == "output_text" or .type == "text") | .text // ""] | join("\n");
def injected:
  test("^\\s*(# AGENTS\\.md instructions|<environment_context>|<permissions instructions>|<INSTRUCTIONS>|<user_instructions>)");
def conversation:
  .type == "response_item" and .payload.type == "message"
  and (.payload.role == "user" or .payload.role == "assistant")
  and ((.payload | text_content | injected) | not);
def clip($n): if length > $n then .[0:$n] + " […]" else . end;
if $mode == "meta" then
  reduce (inputs | fromjson) as $l (
    {host: "codex", session: null, cwd: null, branch: null, title: null, first_ts: null, last_ts: null, turns: 0};
    if $l.type == "session_meta" then
      .session = ($l.payload.id // $l.payload.session_id)
      | .cwd = $l.payload.cwd
      | .branch = $l.payload.git.branch
      | .first_ts = ($l.payload.timestamp // $l.timestamp)
      | .internal = (($l.payload.source | type) == "object" and ($l.payload.source | has("subagent")))
    elif ($l | conversation) then
      .turns += 1 | .last_ts = $l.timestamp
      | if $l.payload.role == "user" then .title //= ($l.payload | text_content | gsub("\\s+"; " ") | .[0:60]) else . end
    else . end)
  | .end = $end | .last_ts //= .first_ts
else
  inputs | fromjson | . as $l
  | if conversation then
      "\(.payload.role | ascii_upcase): " + (.payload | text_content | clip(4000))
    elif .type == "response_item" and (.payload.type == "function_call" or .payload.type == "custom_tool_call") then
      "TOOL \(.payload.name): " + ((.payload.arguments // .payload.input // "") | tostring | clip(300))
    elif .type == "response_item" and (.payload.type == "function_call_output" or .payload.type == "custom_tool_call_output") then
      "RESULT: " + ((.payload.output // "") | tostring | gsub("\\s+"; " ") | clip(300))
    else empty end
  | "[\($l.timestamp // "" | .[0:16] | sub("T"; " "))] \(.)\n"
end
