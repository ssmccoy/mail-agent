# One line per step of a codex turn, from the event stream it prints
# with --json. The shapes differ from Claude's; the output does not.
#
# Arguments: $work, a path prefix to strip.

def one($n): gsub($work; "") | gsub("\\s+"; " ")
    | if length > $n then .[0:$n] + "…" else . end;

# Every command arrives wrapped in the shell codex invokes it with.
def unwrap: sub("^/bin/(ba)?sh -lc ['\"]"; "") | sub("['\"]$"; "");

select(.type == "item.completed")
    | .item
    | if .type == "agent_message" then "» " + (.text | one(96))
      elif .type == "reasoning" then
          if (.text // "") == "" then empty else "· " + (.text | one(96)) end
      elif .type == "command_execution" then
          ("$ " + (.command | unwrap | one(96))),
          ("  ← exit \(.exit_code // 0)" +
              (if (.aggregated_output // "") == "" then ""
               else ", \((.aggregated_output | split("\n") | length)) lines"
               end))
      elif .type == "file_change" then
          (.changes[]? | "\(.kind) \(.path | one(88))")
      elif .type == "error" then "! " + ((.message // .text // "") | one(96))
      else empty
      end
