# One line per step of a session: reasoning, each tool call in the
# notation of its tool, and the size of what it returned.
#
# Arguments: $work, a path prefix to strip; $since, a timestamp to start
# from, or the empty string for the whole session.

def one($n): gsub($work; "") | gsub("\\s+"; " ")
    | if length > $n then .[0:$n] + "…" else . end;

def lines: if type == "array" then map(.text // "") | join("\n") else (. // "") end;

def step:
    if .type == "assistant" then
        .message.content[]? |
            if .type == "thinking" then
                if (.thinking // "") == "" then empty
                else "· " + (.thinking | one(96))
                end
            elif .type == "text" then "» " + (.text | one(96))
            elif .type == "tool_use" then
                if .name == "Bash" then "$ " + (.input.command | one(96))
                elif .name == "Edit" then
                    (((.input.new_string // "") | split("\n") | length) as $added
                     | ((.input.old_string // "") | split("\n") | length) as $cut
                     | "edit " + (.input.file_path | one(72)) +
                       "  +\($added) -\($cut)")
                elif .name == "Write" then
                    (((.input.content // "") | split("\n") | length) as $added
                     | "write " + (.input.file_path | one(72)) + "  +\($added)")
                elif .input.file_path then
                    (.name | ascii_downcase) + " " + (.input.file_path | one(96))
                else .name + " " + (.input | tostring | one(80))
                end
            else empty
            end
    elif .type == "user" then
        .message.content[]? | select(.type == "tool_result") |
            (.content | lines) as $out
            # An edit or write answers with a sentence saying it worked,
            # which the call line already said better.
            | if ($out | test("has been updated|File created successfully|^Applied [0-9]+ edit")) then
                empty
              else
                ($out | split("\n") | length) as $count
                | "  ← \($count) " + (if $count == 1 then "line" else "lines" end)
              end
    else empty
    end;

select(.type == "assistant" or .type == "user")
    | select($since == "" or (.timestamp // "") >= $since)
    | ((.timestamp // "           ")[11:19]) as $clock
    | step
    | "\($clock)  \(.)"
