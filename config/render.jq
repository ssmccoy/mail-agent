# Extract ordered transcript parts for mail-agent-render. Each output line is
# TSV; jq escapes embedded tabs, newlines, carriage returns, and backslashes.
#
# Argument: $since, a timestamp to start from, or the empty string for the
# whole transcript.

def flatten:
    if type == "string" then
        [{type: "text", text: .}]
    elif type == "array" then
        .
    else
        []
    end;

def text_of:
    if type == "string" then
        .
    elif type == "array" then
        map(if (.text // "") == "" then tojson else .text end) | join("\n")
    else
        tojson
    end;

def prefix_lines($prefix):
    split("\n") | map($prefix + .) | join("\n");

def shell_call($input):
    "> " + (($input.command // "") | gsub("\n"; "\n> "));

def edit_call($input):
    "edit \($input.file_path)\n\n"
    + (($input.old_string // "") | prefix_lines("-")) + "\n"
    + (($input.new_string // "") | prefix_lines("+"));

def write_call($input):
    "write \($input.file_path)\n\n\($input.content // "")";

def read_call($input):
    (if ($input.offset // 0) == 0 then
        ""
    else
        " +\($input.offset),\($input.limit // "")"
    end) as $span
    | "read \($input.file_path)\($span)";

def grep_call($input):
    "grep \($input.pattern) \($input.path // ".")";

def glob_call($input):
    "glob \($input.pattern)";

def agent_call($input):
    "agent \($input.subagent_type // "general"): "
    + "\($input.description // "")\n\n\($input.prompt // "")";

def fetch_call($input):
    "fetch \($input.url // $input.query // "")";

def call($name; $input):
    if $name == "Bash" then shell_call($input)
    elif $name == "Edit" then edit_call($input)
    elif $name == "Write" then write_call($input)
    elif $name == "Read" then read_call($input)
    elif $name == "Grep" then grep_call($input)
    elif $name == "Glob" then glob_call($input)
    elif $name == "Agent" or $name == "Task" then agent_call($input)
    elif $name == "WebFetch" or $name == "WebSearch" then fetch_call($input)
    else "\($name) \($input | tojson)"
    end;

def tool_label($name; $input):
    if $name == "Bash" and $input.description then
        $input.description
    elif $input.file_path then
        "\($name) \($input.file_path | split("/") | last)"
    else
        $name
    end;

def result_for($records; $id):
    [$records[]
        | ((.message.content // []) | flatten)[]
        | select(.type == "tool_result" and .tool_use_id == $id)
        | .content];

map(select($since == "" or (.timestamp // "") >= $since)) as $records
| ([$records[]
    | ((.message.content // []) | flatten)[]
    | select(.type == "tool_use")] | length) as $calls
| (["meta", ($records | length), $calls] | @tsv),
    ($records[]
        | select(.type == "assistant")
        | (if .isSidechain then "subagent " else "" end) as $mark
        | ((.message.content // []) | flatten)[]
        | if .type == "thinking" then
            if (.thinking // "") == "" then empty
            else ["thinking", .thinking] | @tsv
            end
        elif .type == "text" then
            ["text", .text] | @tsv
        elif .type == "tool_use" then
            . as $block
            | result_for($records; $block.id) as $results
            | [
                "call",
                call($block.name; $block.input),
                ($results | length),
                $mark + tool_label($block.name; $block.input),
                (if ($results | length) == 0 then
                    ""
                else
                    $results[-1] | text_of
                end)
            ] | @tsv
        else
            empty
        end)
