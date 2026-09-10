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

prepare_worktree() {
    shared="$agent_root/repos/$(printf "%s" "$source_repo" | sed -e 's|^/||' -e 's|/|-|g')"
    invoke git clone -q --bare --no-hardlinks "$source_repo" "$shared"
    invoke git -C "$shared" worktree add -q "$work/repo"
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
    prepare_worktree
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

@test "non-execute profiles protect the checkout and shared Git storage" {
    for driver in claude codex pi; do
        profile="$project_root/landlock/mail-agent-$driver-ro.cfg"

        [ -f "$profile" ]
        grep -Fx "rox ." "$profile"
        ! grep -F "~/mail/.agent/repos" "$profile"
        ! grep -Eq "^best-effort|^rwx /proc|^rw[x]? ~/mail/.agent/repos" "$profile"
    done
}

@test "Claude uses a filesystem read-only profile in investigate and plan" {
    prepare_driver

    for mode in investigate plan; do
        invoke_driver claude "$mode"

        grep -F "mail-agent-claude-ro.cfg" "$case_root/launcher-arguments"
    done

    invoke_driver claude execute

    grep -F "mail-agent-claude.cfg" "$case_root/launcher-arguments"
}

@test "research tools exclude shell and delegation for every harness" {
    prepare_driver

    for driver in claude pi codex; do
        invoke_driver "$driver" research

        case "$driver" in
            claude)
                grep -Fx -- --tools "$case_root/cli-arguments"
                grep -Fx "Read,Write,Edit,Glob,Grep,WebSearch,WebFetch" "$case_root/cli-arguments"
                grep -Fx -- --strict-mcp-config "$case_root/cli-arguments"
                ;;
            pi)
                grep -Fx -- --tools "$case_root/cli-arguments"
                grep -Fx "read,write,edit,grep,find,ls" "$case_root/cli-arguments"
                ;;
            codex)
                grep -Fx "features.shell_tool=false" "$case_root/cli-arguments"
                grep -Fx "features.unified_exec=false" "$case_root/cli-arguments"
                grep -Fx "features.multi_agent=false" "$case_root/cli-arguments"
                ;;
        esac
    done
}

@test "each mode selects its own configurable tool profile" {
    prepare_driver

    for driver in claude codex pi; do
        for mode in investigate plan execute research; do
            case "$driver" in
                claude|pi)
                    printf '["--tools", "read"]\n' > "$case_home/.config/mail-agent/tools-$driver-$mode.json"
                    ;;
                codex)
                    printf '["-c", "features.shell_tool=false"]\n' > "$case_home/.config/mail-agent/tools-$driver-$mode.json"
                    ;;
            esac

            invoke_driver "$driver" "$mode"

            case "$driver" in
                claude|pi) grep -Fx "read" "$case_root/cli-arguments" ;;
                codex) grep -Fx "features.shell_tool=false" "$case_root/cli-arguments" ;;
            esac
        done
    done
}

@test "invalid and missing tool profiles fail before launching the CLI" {
    prepare_driver

    for driver in claude codex pi; do
        profile="$case_home/.config/mail-agent/tools-$driver-research.json"
        printf '{"bad": true}\n' > "$profile"
        run invoke_driver "$driver" research

        [ "$status" -ne 0 ]
        [ ! -e "$case_root/cli-arguments" ]
        rm "$profile"
        run invoke_driver "$driver" research

        [ "$status" -ne 0 ]
        [ ! -e "$case_root/cli-arguments" ]
    done
}

@test "tool profile arguments are passed without shell evaluation or word splitting" {
    prepare_driver
    jq -n --arg value 'Read,Write,$(touch SHOULD_NOT_EXIST),two words' \
        '["--tools",$value]' > "$case_home/.config/mail-agent/tools-claude-plan.json"
    invoke_driver claude plan

    grep -Fx 'Read,Write,$(touch SHOULD_NOT_EXIST),two words' "$case_root/cli-arguments"
    [ ! -e "$work/repo/SHOULD_NOT_EXIST" ]
}

@test "Codex research configures required file tools in its writable working area" {
    prepare_driver
    invoke_driver codex research
    directory=$(cat "$case_root/research-directory")

    grep -Fx 'mcp_servers.mail_agent_files.required=true' "$case_root/cli-arguments"
    grep -Fx "mcp_servers.mail_agent_files.command=\"$case_home/bin/mail-agent-files\"" "$case_root/cli-arguments"
    grep -Fx "mcp_servers.mail_agent_files.args=[\"$directory\"]" "$case_root/cli-arguments"
    [ ! -d "$directory" ]
}

@test "driver histories are private to a mail stream and persist across turns" {
    prepare_driver
    mkdir -p "$case_home/mail/.agent/codex/sessions"
    printf 'private unrelated history\n' > "$case_home/mail/.agent/codex/sessions/unrelated.jsonl"

    for driver in claude codex pi; do
        invoke_driver "$driver" research
        state="$work/harness/$driver"

        [ -d "$state" ]
        [ "$(cat "$case_root/driver-home")" = "$state" ]
        printf 'preserve history\n' > "$state/sentinel"
        invoke_driver "$driver" research

        [ "$(cat "$state/sentinel")" = "preserve history" ]
        [ ! -e "$state/sessions/unrelated.jsonl" ]
    done
}

@test "fork state imports only its selected parent transcript" {
    prepare_driver
    child="$agent_root/work/22222222-2222-4222-a222-222222222222"
    mkdir -p "$child/repo" "$work/harness/codex/sessions"
    printf 'parent-session\n' > "$child/agent-session"
    printf 'selected\n' > "$work/harness/codex/sessions/rollout-parent-session.jsonl"
    printf 'unrelated\n' > "$work/harness/codex/sessions/rollout-other-session.jsonl"
    run invoke "$case_home/bin/mail-agent-state" codex "$child" "$work"

    [ "$status" -eq 0 ]
    [ "$(cat "$child/harness/codex/sessions/rollout-parent-session.jsonl")" = selected ]
    [ ! -e "$child/harness/codex/sessions/rollout-other-session.jsonl" ]
}

@test "research profiles grant only stream runtime state and read-only credentials" {
    for driver in claude codex pi; do
        profile="$project_root/landlock/mail-agent-$driver-research.cfg"

        grep -Fx 'rw "$MAIL_AGENT_DRIVER_HOME"' "$profile"
        ! grep -Eq '^rw[x]? (~/(mail/\.agent|\.claude|\.codex|\.pi)|/proc)' "$profile"
    done
}

@test "drivers grant only their project's Git storage with mode-specific access" {
    prepare_driver
    prepare_worktree
    objects=$(git -C "$work/repo" rev-parse --path-format=absolute --git-common-dir)

    for driver in claude codex pi; do
        for mode in investigate plan research execute; do
            invoke_driver "$driver" "$mode"
            permission=-r

            if [ "$mode" = execute ]; then
                permission=-w
            fi

            awk -v permission="$permission" -v objects="$objects" \
                'previous == permission && $0 == objects { found = 1 }
                { previous = $0 } END { exit !found }' "$case_root/launcher-arguments"
        done
    done
}

@test "research prompts identify the writable working area without a shell lookup" {
    prepare_driver

    for driver in claude codex pi; do
        invoke_driver "$driver" research
        directory=$(cat "$case_root/research-directory")

        grep -Fx "Research working area: $directory" "$case_root/cli-prompt"
        grep -Fx "Please inspect." "$case_root/cli-prompt"
    done
}

@test "every mode uses private temporary storage and removes it after execution" {
    prepare_driver

    for driver in claude codex pi; do
        for mode in investigate plan execute research; do
            invoke_driver "$driver" "$mode"
            directory=$(cat "$case_root/temporary-directory")

            [ -n "$directory" ]
            [ ! -d "$directory" ]
        done
    done

    ! grep -E '^rw[x]? /tmp/mail-agent$' "$project_root"/landlock/*.cfg
}

@test "a modified worktree pointer cannot grant writes to the original Git directory" {
    prepare_driver
    printf 'gitdir: %s/.git\n' "$source_repo" > "$work/repo/.git"

    for driver in claude codex pi; do
        invoke_driver "$driver" execute

        ! awk -v directory="$source_repo/.git" \
            'previous == "-w" && $0 == directory { found = 1 }
            { previous = $0 } END { exit !found }' "$case_root/launcher-arguments"
    done
}
