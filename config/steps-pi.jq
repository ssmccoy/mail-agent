# One line per step of a pi turn, from the event stream it prints with
# --mode json. The shapes differ from Claude's and codex's; the lines do
# not.
#
# Arguments: $work, a path prefix to strip.

def one($n): gsub($work; "") | gsub("\\s+"; " ")
    | if length > $n then .[0:$n] + "…" else . end;

def call:
    if .name == "bash" then "$ " + ((.arguments.command // "") | one(96))
    elif (.arguments.path // "") != "" then
        .name + " " + (.arguments.path | one(88))
    else .name + " " + ((.arguments // {}) | tostring | one(80))
    end;

# The whole message is repeated at message_end; read the steps from
# there rather than reassembling the deltas.
select(.type == "message_end" and .message.role == "assistant")
    | .message.content[]?
    | if .type == "thinking" then
          if (.thinking // "") == "" then empty
          else "· " + (.thinking | one(96)) end
      elif .type == "text" then "» " + (.text | one(96))
      elif .type == "toolCall" then call
      else empty
      end
