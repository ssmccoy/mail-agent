load helper

@test "existing streams remain legacy when the new-stream default changes" {
    mkdir -p "$work/repo"
    printf 'system\n' > "$case_home/.config/mail-agent/backend"
    run invoke "$case_home/bin/mail-agent-stream" ensure "$session"

    [ "$status" -eq 0 ]
    [ "$(jq -r .backend <<< "$output")" = legacy ]
    [ "$(jq -r .backend "$agent_root/streams/$session.json")" = legacy ]
}

@test "backend selection persists and unavailable backends never execute locally" {
    printf 'system\n' > "$case_home/.config/mail-agent/backend"
    run invoke "$case_home/bin/mail-agent-stream" ensure "$session"

    [ "$status" -eq 0 ]
    [ "$(jq -r .backend <<< "$output")" = system ]
    printf 'legacy\n' > "$case_home/.config/mail-agent/backend"
    message "$queue/001"
    run invoke "$case_home/bin/mail-agent-dispatch" "$session" 001

    [ "$status" -eq 0 ]
    [ "$(jq -r .backend "$agent_root/streams/$session.json")" = system ]
    [ ! -e "$case_root/driver-arguments" ]
    [ ! -e "$case_root/scheduled" ]
    [ ! -e "$queue/001" ]
    [ "$(mail_count)" -eq 1 ]
}

@test "paused streams retain queued mail and already scheduled workers do not execute" {
    new_repository
    invoke "$case_home/bin/mail-agent-stream" ensure "$session"
    invoke "$case_home/bin/mail-agent-stream" pause "$session"
    message "$queue/001"
    run invoke "$case_home/bin/mail-agent-dispatch" "$session" 001

    [ "$status" -eq 0 ]
    [ -f "$queue/001" ]
    [ ! -e "$case_root/scheduled" ]
    run run_turn

    [ "$status" -eq 0 ]
    [ -f "$queue/001" ]
    [ ! -d "$work" ]
    [ ! -e "$case_root/driver-arguments" ]
    invoke "$case_home/bin/mail-agent-stream" resume "$session"
    run run_turn

    [ "$status" -eq 0 ]
    [ ! -e "$queue/001" ]
    [ -e "$case_root/driver-arguments" ]
}

@test "pause cannot race an executing stream" {
    invoke "$case_home/bin/mail-agent-stream" ensure "$session"
    exec 8> "$agent_root/lock/$session"
    flock -n 8
    run invoke "$case_home/bin/mail-agent-stream" pause "$session"

    [ "$status" -eq 75 ]
    [ "$(jq -r .state "$agent_root/streams/$session.json")" = active ]
    exec 8>&-
}

@test "forks inherit their parent's backend independent of defaults" {
    child=22222222-2222-4222-a222-222222222222
    invoke "$case_home/bin/mail-agent-stream" ensure "$session"
    printf 'system\n' > "$case_home/.config/mail-agent/backend"
    run invoke "$case_home/bin/mail-agent-stream" fork "$session" "$child"

    [ "$status" -eq 0 ]
    [ "$(jq -r .backend "$agent_root/streams/$child.json")" = legacy ]
    [ "$(jq -r .parent "$agent_root/streams/$child.json")" = "$session" ]
}

@test "malformed stream records and defaults prevent execution" {
    new_repository
    mkdir -p "$agent_root/streams"
    printf '{"backend":"legacy"}\n' > "$agent_root/streams/$session.json"
    message "$queue/001"
    run run_turn

    [ "$status" -ne 0 ]
    [ ! -e "$case_root/driver-arguments" ]
    [ ! -d "$work" ]
    rm "$agent_root/streams/$session.json"
    printf 'invalid\n' > "$case_home/.config/mail-agent/backend"
    run invoke "$case_home/bin/mail-agent-stream" ensure "$session"

    [ "$status" -ne 0 ]
    [ ! -e "$agent_root/streams/$session.json" ]
}

@test "retirement prevents queued workers from recreating a forgotten stream" {
    new_repository
    message "$queue/001"
    run_turn
    invoke "$case_home/bin/mail-agent-forget" "$session"
    mkdir -p "$queue"
    message "$queue/002"
    rm "$case_root/driver-arguments"
    run run_turn

    [ "$status" -ne 0 ]
    [ ! -d "$work" ]
    [ ! -e "$case_root/driver-arguments" ]
    run invoke "$case_home/bin/mail-agent-stream" resume "$session"

    [ "$status" -ne 0 ]
    [ "$(jq -r .state "$agent_root/streams/$session.json")" = retired ]
}

@test "inspection reports paused admission and the recorded backend" {
    new_repository
    message "$queue/001"
    run_turn
    invoke "$case_home/bin/mail-agent-stream" pause "$session" > /dev/null
    run invoke "$case_home/bin/mail-agent-details" "$session"

    [ "$status" -eq 0 ]
    [[ "$output" == *"backend   legacy"* ]]
    [[ "$output" == *"paused, 0 waiting"* ]]
    run invoke "$case_home/bin/mail-agent-sessions"

    [ "$status" -eq 0 ]
    [[ "$output" == *"paused"* ]]
}
