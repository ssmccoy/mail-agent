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
        "$case_root/prompt" "$2" "example-model"
}

@test "all drivers convert fixture events and preserve prompts" {
    prepare_driver

    for driver in claude codex pi; do
        rm -f "$work/agent-session"
        run invoke_driver "$driver" investigate

        [ "$status" -eq 0 ]
        [ "$(cat "$case_root/result/reply.md")" = "Inspection complete." ]
        [ "$(cat "$work/agent-session")" = "fixture-session" ]
        cmp "$case_root/prompt" "$case_root/cli-prompt"
        [ -s "$case_root/result/steps.txt" ]
        [ -s "$case_root/result/usage.html" ]

        if [ "$driver" = claude ]; then
            [ "$(cat "$case_root/result/cost")" = "0.25" ]
            grep -Fx plan "$case_root/cli-arguments"
            grep -F '$0.25 this turn' "$case_root/result/usage.html"
        else
            [ "$(cat "$case_root/result/cost")" = "0" ]
            grep -F "mail-agent-$driver-ro.cfg" "$case_root/launcher-arguments"
            grep -F '<td class="n">12</td>' "$case_root/result/usage.html"
        fi
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
