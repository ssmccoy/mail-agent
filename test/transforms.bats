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

@test "usage formats model totals, tools, and the session ledger" {
    jq -n '{
        session_id: "fixture-session",
        total_cost_usd: 1.2012,
        duration_ms: 1200,
        duration_api_ms: 800,
        num_turns: 2,
        modelUsage: {
            first: {
                canonicalModel: "one",
                inputTokens: 1234567,
                outputTokens: 2,
                thinkingTokens: 3,
                cacheReadInputTokens: 4,
                cacheCreationInputTokens: 5,
                costUSD: 0.0012
            },
            second: {
                inputTokens: 3,
                outputTokens: 4,
                thinkingTokens: 5,
                cacheReadInputTokens: 6,
                cacheCreationInputTokens: 7,
                costUSD: 1.2
            }
        },
        subagent_stats: {spawned: 2, completed: 1},
        permission_denials: [{}, {}]
    }' > "$case_root/result"
    printf '\n2026-01-01T00:00:00Z 1.25\n' > "$case_root/ledger"

    run invoke "$case_home/bin/mail-agent-usage" "$case_root/result" \
        "$project_root/test/fixtures/claude.jsonl" "" "$case_root/ledger"

    [ "$status" -eq 0 ]
    [[ "$output" == *'<caption>$1.20 this turn</caption>'* ]]
    [[ "$output" == *'<td>one</td><td class="n">1,234,567</td>'* ]]
    [[ "$output" == *'<th>total</th><th class="n">1,234,570</th>'* ]]
    [[ "$output" == *'$1.25 over 1 turn'* ]]
    [[ "$output" == *'<td class="n">Bash 1</td>'* ]]
    [[ "$output" == *'2 spawned, 1 completed'* ]]
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

@test "draft effort replacement preserves other headers and body" {
    printf 'To: reader@example.invalid\r\nx-mail-effort: low\r\n continuation\r\nSubject: example\r\nX-Mail-Effort: medium\r\n\r\nX-Mail-Effort: body text\r\n\000tail' > "$case_root/draft"
    printf 'To: reader@example.invalid\r\nSubject: example\r\nX-Mail-Effort: max\r\n\r\nX-Mail-Effort: body text\r\n\000tail' > "$case_root/expected"

    invoke "$case_home/bin/mail-agent-set-effort" max "$case_root/draft"

    cmp "$case_root/expected" "$case_root/draft"
    invoke "$case_home/bin/mail-agent-set-effort" max "$case_root/draft"

    cmp "$case_root/expected" "$case_root/draft"
}

@test "draft effort validation leaves malformed drafts unchanged" {
    printf 'No header separator\n' > "$case_root/draft"
    cp "$case_root/draft" "$case_root/expected"

    run invoke "$case_home/bin/mail-agent-set-effort" high "$case_root/draft"

    [ "$status" -ne 0 ]
    cmp "$case_root/expected" "$case_root/draft"

    run invoke "$case_home/bin/mail-agent-set-effort" bogus "$case_root/draft"

    [ "$status" -ne 0 ]
    cmp "$case_root/expected" "$case_root/draft"
}
