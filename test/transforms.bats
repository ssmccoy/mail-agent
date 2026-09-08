load helper

@test "rewrap preserves headers, figures, and the complete diff" {
    printf 'Subject: a long subject which must remain unchanged\n\none two three four five six seven\n\n    a long indented figure remains unchanged\n\n---\n file | 1 +\ndiff --git a/file b/file\n+one two three four five six seven\n' > "$case_root/patch"
    invoke "$case_home/bin/mail-agent-rewrap" 16 < "$case_root/patch" > "$case_root/wrapped"
    sed -n '/^---$/,$p' "$case_root/patch" > "$case_root/before"
    sed -n '/^---$/,$p' "$case_root/wrapped" > "$case_root/after"

    cmp "$case_root/before" "$case_root/after"
    grep -Fx 'one two three' "$case_root/wrapped"
    grep -Fx 'four five six' "$case_root/wrapped"
    grep -Fx '    a long indented figure remains unchanged' "$case_root/wrapped"
    [ "$(head -1 "$case_root/patch")" = "$(head -1 "$case_root/wrapped")" ]
}

@test "renderer escapes prose and tool results and filters timestamps" {
    run invoke "$case_home/bin/mail-agent-render" "$project_root/test/fixtures/claude.jsonl"

    [ "$status" -eq 0 ]
    [[ "$output" == *'Inspect &lt;script&gt; &amp; input.'* ]]
    [[ "$output" == *'&lt;tag&gt; &amp; value'* ]]
    [[ "$output" == *'3 records, 1 tool calls'* ]]

    run invoke "$case_home/bin/mail-agent-render" "$project_root/test/fixtures/claude.jsonl" "2027-01-01"

    [ "$status" -eq 0 ]
    [[ "$output" == *'0 records, 0 tool calls'* ]]
}

@test "codex steps unwrap commands and summarize replies" {
    run invoke jq -r --arg work "/example/" -f "$project_root/config/steps-codex.jq" "$project_root/test/fixtures/codex.jsonl"

    [ "$status" -eq 0 ]
    [ "$output" = $'$ pwd\n  ← exit 0, 1 lines\n» Inspection complete.' ]
}

@test "questions preserve numbering and choices" {
    printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"AskUserQuestion","input":{"questions":[{"question":"Which branch?","options":[{"label":"main","description":"Use main."}]}]}}]}}' > "$case_root/questions"

    run invoke jq -rs -f "$project_root/config/questions.jq" "$case_root/questions"

    [ "$status" -eq 0 ]
    [[ "$output" == *'### 1. Which branch?'* ]]
    [[ "$output" == *'**main** — Use main.'* ]]
}
