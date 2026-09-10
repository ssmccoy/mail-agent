load helper

prepare_driver() {
    new_repository
    mkdir -p "$work/repo" "$case_root/result"
    printf "%s\n" "$source_repo" > "$work/project"
    printf "Please inspect.\n" > "$case_root/prompt"
    cp "$project_root"/test/fixtures/*.jsonl "$case_root/"
    cp "$project_root/test/commands/landlock" "$case_home/bin/landlock"

    for driver in claude codex pi; do
        cp "$project_root/test/commands/agent" "$case_home/.local/bin/$driver"
    done
}

invoke_driver() {
    invoke "$case_home/bin/mail-agent-$1" "$work" "$case_root/result" \
        "$case_root/prompt" "$2" \
        "$([ "$1" = codex ] && echo gpt-5.6-sol || echo example-model)"
}

@test "all drivers convert fixture events and preserve prompts" {
    prepare_driver
    mkdir "$case_root/attachments"

    for driver in claude codex pi; do
        rm -f "$work/agent-session"
        run invoke_driver "$driver" investigate

        [ "$status" -eq 0 ]
        [ "$(cat "$case_root/result/reply.md")" = "Inspection complete." ]
        [ "$(cat "$work/agent-session")" = "fixture-session" ]
        cmp "$case_root/prompt" "$case_root/cli-prompt"
        grep -Fx "$case_root/attachments" "$case_root/launcher-arguments"
        [ -s "$case_root/result/steps.txt" ]
        [ -s "$case_root/result/usage.html" ]

        if [ "$driver" = claude ]; then
            [ "$(cat "$case_root/result/cost")" = "0.25" ]
            grep -Fx plan "$case_root/cli-arguments"
            grep -F '$0.25 this turn' "$case_root/result/usage.html"
        elif [ "$driver" = codex ]; then
            [ "$(cat "$case_root/result/cost")" = "0.0001172" ]
            grep -F '$0.0001 this turn' "$case_root/result/usage.html"
            grep -F '<td>gpt-5.6-sol</td><td class="n">9</td>' \
                "$case_root/result/usage.html"
            grep -F "mail-agent-$driver-ro.cfg" "$case_root/launcher-arguments"
        else
            [ "$(cat "$case_root/result/cost")" = "0" ]
            grep -F "mail-agent-$driver-ro.cfg" "$case_root/launcher-arguments"
            grep -F '<td class="n">12</td>' "$case_root/result/usage.html"
        fi
    done
}

@test "codex result conversion applies cached and output token rates" {
    prepare_driver

    jq -c 'if .type == "turn.completed" then
            .usage = {
                input_tokens: 1000000,
                cached_input_tokens: 250000,
                output_tokens: 100000,
                reasoning_output_tokens: 10000
            }
        else . end' "$case_root/codex.jsonl" > "$case_root/priced-codex.jsonl"

    for specification in \
        "gpt-6-astra 12.75" \
        "gpt-5.6-sol 5.1" \
        "gpt-5.6-terra 2.75" \
        "gpt-5.6-luna 0.275" \
        "gpt-5.5 6.875" \
        "gpt-5.4-mini 1.03125"; do
        model=${specification% *}
        expected=${specification#* }

        run jq -rs --arg model "$model" \
            -f "$case_home/.config/mail-agent/result-codex.jq" \
            "$case_root/priced-codex.jsonl"

        [ "$status" -eq 0 ]
        [ "$(jq -r '.total_cost_usd' <<< "$output")" = "$expected" ]
        [ "$(jq -r --arg model "$model" \
            '.modelUsage[$model].inputTokens' <<< "$output")" = "750000" ]
    done
}

@test "driver continuation and execute permissions use their CLI interfaces" {
    prepare_driver

    for driver in claude codex pi; do
        printf "parent-session\n" > "$work/agent-session"
        invoke_driver "$driver" execute

        grep -Fx parent-session "$case_root/cli-arguments"

        case "$driver" in
            claude)
                grep -Fx -- --resume "$case_root/cli-arguments"
                grep -Fx -- --fork-session "$case_root/cli-arguments"
                grep -Fx bypassPermissions "$case_root/cli-arguments"
                ;;
            codex)
                grep -Fx fork "$case_root/cli-arguments"
                grep -F mail-agent-codex.cfg "$case_root/launcher-arguments"
                ;;
            pi)
                grep -Fx -- --fork "$case_root/cli-arguments"
                ! grep -Fx -- --exclude-tools "$case_root/cli-arguments"
                ;;
        esac
    done
}

@test "drivers propagate timeout and classify CLI failure as retryable" {
    prepare_driver

    for driver in claude codex pi; do
        printf "1\n" > "$case_root/status"
        run invoke_driver "$driver" plan

        [ "$status" -eq 75 ]
        printf "124\n" > "$case_root/status"
        run invoke_driver "$driver" plan

        [ "$status" -eq 124 ]
    done
}

@test "a claude reply ending in a fence keeps every line" {
    prepare_driver

    jq -c 'if .type == "result" then
            .result = "The answer.\n\n```\nkubectl get pods\n```"
        else . end' \
        "$project_root/test/fixtures/claude.jsonl" > "$case_root/claude.jsonl"

    run invoke_driver claude investigate

    [ "$status" -eq 0 ]
    grep -Fx "The answer." "$case_root/result/reply.md"
    grep -Fx "kubectl get pods" "$case_root/result/reply.md"
    [ "$(cat "$work/agent-session")" = "fixture-session" ]
}

@test "codex session usage includes the current turn before ledger append" {
    prepare_driver

    jq -c 'if .type == "turn.completed" then
            .usage = {
                input_tokens: 465000,
                cached_input_tokens: 0,
                output_tokens: 0,
                reasoning_output_tokens: 0
            }
        else . end' "$case_root/codex.jsonl" > "$case_root/priced-codex.jsonl"
    mv "$case_root/priced-codex.jsonl" "$case_root/codex.jsonl"
    printf "2026-01-01T00:00:00Z 0\n" > "$work/cost"
    cp "$work/cost" "$case_root/ledger-before"

    run invoke_driver codex investigate

    [ "$status" -eq 0 ]
    [ "$(cat "$case_root/result/cost")" = "1.86" ]
    grep -F '<caption>$1.86 this turn</caption>' "$case_root/result/usage.html"
    grep -F '<td>session so far</td><td class="n">$1.86 over 2 turns</td>' \
        "$case_root/result/usage.html"
    cmp "$case_root/ledger-before" "$work/cost"
}

@test "research drivers use restricted profiles without repository grants" {
    prepare_driver
    rm "$work/project"

    for driver in claude codex pi; do
        run invoke_driver "$driver" research

        [ "$status" -eq 0 ]
        grep -F "mail-agent-$driver-research.cfg" "$case_root/launcher-arguments"
        ! grep -Fx "$source_repo" "$case_root/launcher-arguments"
    done

    invoke_driver codex research
    grep -Fx "project_root_markers=[]" "$case_root/cli-arguments"
    grep -Fx "web_search=\"live\"" "$case_root/cli-arguments"
}

@test "research profiles deny writes to code and shared build directories" {
    for driver in claude codex pi; do
        profile="$project_root/landlock/mail-agent-$driver-research.cfg"

        [ -f "$profile" ]
        ! grep -E "^rw[x]? (\.|~/mail/\.agent/(repos|go)|/proc|/tmp/mail-agent)$" "$profile"
        grep -Fx "rox ." "$profile"
        grep -Fx "connect-tcp 443" "$profile"
    done
}

@test "research grants read access to an existing worktree object directory" {
    prepare_driver
    invoke git -C "$source_repo" worktree add -q "$work/repo"
    objects=$(git -C "$work/repo" rev-parse --path-format=absolute --git-common-dir)

    for driver in claude codex pi; do
        invoke_driver "$driver" research

        grep -Fx "$objects" "$case_root/launcher-arguments"
        directory=$(cat "$case_root/research-directory")

        [ -n "$directory" ]
        [ ! -d "$directory" ]
    done
}

@test "repository-free plan turns retain research filesystem restrictions" {
    prepare_driver
    rm "$work/project"

    for driver in claude codex pi; do
        invoke_driver "$driver" plan

        grep -F "mail-agent-$driver-research.cfg" "$case_root/launcher-arguments"
    done
}
