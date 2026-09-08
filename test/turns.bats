load helper

@test "execute mails an applicable patch once and records the reply" {
    new_repository
    message "$queue/001" $'!execute\nPlease change the file.'
    touch "$case_root/commit"

    run run_turn

    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 2 ]
    [ ! -e "$queue/001" ]
    [ "$(cat "$work/mailed")" = "$(invoke git -C "$work/repo" rev-parse HEAD)" ]
    invoke git clone -q "$source_repo" "$case_root/recipient"

    for mail in "$case_root"/outgoing/*; do
        if mhdr -h subject "$mail" | grep -q '\[PATCH'; then
            patch="$mail"
        else
            cover="$mail"
        fi
    done

    [ "$(mhdr -h in-reply-to "$patch")" = "$(mhdr -h message-id "$cover")" ]
    invoke "$case_home/bin/git-am-mail" "$case_root/recipient" < "$patch"
    [ "$(cat "$case_root/recipient/file")" = changed ]
    [ "$(invoke git -C "$case_root/recipient" log -1 --format=%s)" = "Change example file" ]
    mkdir -p "$queue"
    message "$queue/002"
    run_turn

    [ "$(mail_count)" -eq 3 ]
    [ "$(wc -l < "$work/turns")" -eq 2 ]
}

@test "default mode strips trailing quotes but retains inline answers" {
    new_repository
    message "$queue/001" $'> Keep this question?\nYes.\n\nSender wrote:\n> Old trailing text' 'Re: Fwd: sample: example'
    run_turn

    grep -Fx 'Mode: investigate' "$case_root/prompts"
    grep -Fx '> Keep this question?' "$case_root/prompts"
    grep -Fx 'Yes.' "$case_root/prompts"
    ! grep -q 'Old trailing text\|Sender wrote:' "$case_root/prompts"
}

@test "retry retains mail and notifies once until success" {
    new_repository
    message "$queue/001"
    printf '75\n' > "$case_root/status"
    run_turn
    run_turn

    [ -f "$queue/001" ]
    [ -f "$work/notified" ]
    [ "$(mail_count)" -eq 1 ]
    printf '0\n' > "$case_root/status"
    run_turn

    [ ! -e "$queue/001" ]
    [ ! -e "$work/notified" ]
    [ "$(mail_count)" -eq 2 ]
}

@test "timeout consumes the message without recording a successful turn" {
    new_repository
    message "$queue/001"
    printf '124\n' > "$case_root/status"
    run_turn

    [ ! -e "$queue/001" ]
    [ ! -e "$work/turns" ]
    [ "$(mail_count)" -eq 1 ]
    mshow -R "$case_root"/outgoing/* | grep -q 'exceeded'
}

@test "queued messages run in order and retain their original project" {
    new_repository
    message "$queue/002" "Second request." "different: ignored"
    message "$queue/001" "First request."
    run_turn

    [ "$(cat "$work/project")" = "$source_repo" ]
    [ "$(grep 'request\.' "$case_root/prompts")" = $'First request.\nSecond request.' ]
    [ "$(mail_count)" -eq 2 ]
}

@test "invalid project, branch, and directive do not invoke the driver" {
    new_repository
    message "$queue/001" "Please inspect." "absent: project"
    run_turn

    [ ! -e "$work" ]
    [ ! -e "$case_root/driver-arguments" ]
    message "$queue/002" $'!branch absent\nPlease inspect.'
    run_turn

    [ ! -e "$work" ]
    message "$queue/003" $'!unknown\nPlease inspect.'
    run_turn

    [ ! -e "$case_root/driver-arguments" ]
    [ "$(mail_count)" -eq 3 ]
}

@test "empty queue does not invoke a driver or send mail" {
    run run_turn

    [ "$status" -eq 0 ]
    [ ! -e "$case_root/driver-arguments" ]
    [ "$(mail_count)" -eq 0 ]
}

@test "branch changes reset the patch base to the selected branch" {
    new_repository
    invoke git -C "$source_repo" checkout -qb release
    printf "release\n" > "$source_repo/file"
    invoke git -C "$source_repo" commit -qam "Prepare release"
    release=$(invoke git -C "$source_repo" rev-parse HEAD)
    invoke git -C "$source_repo" checkout -q main
    message "$queue/001"
    run_turn
    mkdir -p "$queue"
    message "$queue/002" $'!plan\n!branch release\nInspect release.'
    run_turn

    [ "$(cat "$work/branch")" = release ]
    [ "$(cat "$work/base")" = "$release" ]
    [ "$(cat "$work/repo/file")" = release ]
    grep -Fx 'Mode: plan' "$case_root/prompts"
    ! grep -q '^!branch' "$case_root/prompts"
}

@test "replying to an older turn creates a related worktree at that commit" {
    new_repository
    message "$queue/001"
    run_turn
    first_reply=$(cut -d ' ' -f1 "$work/turns")
    first_commit=$(cat "$work/base")
    mkdir -p "$queue"
    message "$queue/002" '!execute'
    touch "$case_root/commit"
    run_turn
    parent_head=$(invoke git -C "$work/repo" rev-parse HEAD)
    mkdir -p "$queue"
    message "$queue/003" 'Reconsider the first answer.'
    sed -i "1iIn-Reply-To: $first_reply" "$queue/003"
    run_turn
    child=$(tail -1 "$case_root/scheduled")
    child_work="$agent_root/work/$child"

    [ "$child" != "$session" ]
    [ "$(cat "$child_work/root")" = "$session" ]
    [ "$(cat "$child_work/base")" = "$first_commit" ]
    [ "$(invoke git -C "$child_work/repo" rev-parse HEAD)" = "$first_commit" ]
    [ "$(invoke git -C "$work/repo" rev-parse HEAD)" = "$parent_head" ]
    [ "$(find "$agent_root/queue/$child" -type f | wc -l)" -eq 1 ]
    invoke "$case_home/bin/mail-agent-forget" "$child"

    [ ! -e "$child_work" ]
    [ ! -e "$work" ]
}

@test "a refusal comes from the alias the message was sent to" {
    new_repository
    printf "sample %s\n" "$source_repo" > "$case_home/.config/mail-agent/projects"
    message "$queue/001" $'!branch absent\nPlease inspect.'
    run_turn

    [ ! -e "$work" ]
    grep -Fq "There is no branch" "$case_root/outgoing"/*
    grep -Eq '^From: Fixture <test\+fixture@' "$case_root/outgoing"/*
}

@test "a branch the sender tracks but has not checked out is usable" {
    new_repository
    invoke git clone -q "$source_repo" "$case_root/colleague"
    printf "theirs\n" > "$case_root/colleague/file"
    invoke git -C "$case_root/colleague" commit -qam "Write their change"
    theirs=$(invoke git -C "$case_root/colleague" rev-parse HEAD)

    # The sender has their branch only as a remote-tracking ref, which is
    # what a fetch of someone else's work leaves behind.
    invoke git -C "$source_repo" remote add colleague "$case_root/colleague"
    invoke git -C "$source_repo" fetch -q colleague \
        "+refs/heads/main:refs/remotes/origin/theirs"

    message "$queue/001" $'!branch theirs\nPlease inspect.'
    run_turn

    [ "$(cat "$work/branch")" = theirs ]
    [ "$(cat "$work/base")" = "$theirs" ]
    [ "$(cat "$work/repo/file")" = theirs ]
}
