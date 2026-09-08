load helper

@test "hook ignores unknown aliases and schedules new sessions" {
    message "$case_root/incoming"
    invoke env EXTENSION=absent "$case_home/bin/mail-agent-hook" < "$case_root/incoming"

    [ ! -e "$case_root/scheduled" ]
    invoke env EXTENSION=fixture "$case_home/bin/mail-agent-hook" < "$case_root/incoming"

    grep -Fx flock "$case_root/scheduled"
    queued=$(find "$agent_root/queue" -type f)
    generated=$(basename "$(dirname "$queued")")

    [[ "$generated" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-a[0-9a-f]{3}-[0-9a-f]{12}$ ]]
    [ "$(mhdr -h x-mail-agent "$queued" | head -1)" = fixture ]
}

@test "References alone routes to the existing session" {
    message "$case_root/incoming"
    sed -i "1iReferences: <c.$session.123@example.invalid>" "$case_root/incoming"
    invoke env EXTENSION=fixture "$case_home/bin/mail-agent-hook" < "$case_root/incoming"

    [ "$(find "$queue" -type f | wc -l)" -eq 1 ]
    grep -Fx "$session" "$case_root/scheduled"
}

@test "details replies immediately without scheduling a turn" {
    message "$case_root/incoming" '!details'
    invoke env EXTENSION=fixture "$case_home/bin/mail-agent-hook" < "$case_root/incoming"

    [ ! -e "$case_root/scheduled" ]
    [ "$(mail_count)" -eq 1 ]
    [ "$(find "$agent_root/queue" -type f | wc -l)" -eq 0 ]
    mshow -R "$case_root"/outgoing/* | grep -q 'nothing to report'
}

@test "session inspection and retirement preserve unrelated threads" {
    new_repository
    message "$queue/001"
    run_turn
    other="22222222-2222-4222-a222-222222222222"
    mkdir -p "$agent_root/work/$other"
    printf "%s\n" "$other" > "$agent_root/work/$other/root"

    run invoke "$case_home/bin/mail-agent-details" "$session"

    [ "$status" -eq 0 ]
    [[ "$output" == *'idle, 0 waiting'* ]]
    [[ "$output" == *'1, $0.25 in total'* ]]

    run invoke "$case_home/bin/mail-agent-forget" "$session"

    [ "$status" -eq 0 ]
    [ ! -e "$work" ]
    [ -d "$agent_root/work/$other" ]
    shared=$(find "$agent_root/repos" -mindepth 1 -maxdepth 1 -type d)
    [ "$(invoke git -C "$shared" worktree list --porcelain | grep -c '^worktree ')" -eq 1 ]
}

@test "drain skips a locked session and processes an independent session" {
    other="22222222-2222-4222-a222-222222222222"
    mkdir -p "$agent_root/queue/$other"
    message "$queue/001"
    message "$agent_root/queue/$other/001"
    printf '#!/bin/sh\nprintf "%%s\\n" "$1" >> "$CASE_ROOT/drained"\n' > "$case_home/bin/mail-agent-run"

    # The test owns the descriptor; drain must acquire a separate lock.
    exec 9> "$agent_root/lock/$session"
    flock 9
    run invoke timeout 5 "$case_home/bin/mail-agent-drain"
    exec 9>&-

    [ "$status" -eq 0 ]
    [ "$(cat "$case_root/drained")" = "$other" ]
    invoke timeout 5 "$case_home/bin/mail-agent-drain"

    [ "$(grep -c "$session" "$case_root/drained")" -eq 1 ]
}
