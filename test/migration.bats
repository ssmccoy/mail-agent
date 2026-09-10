load helper

prepare_migration() {
    new_repository
    message "$queue/001"
    run_turn
    invoke "$case_home/bin/mail-agent-stream" pause "$session" > /dev/null
}

@test "migration inspection inventories retained state without executing Git or exposing credentials" {
    prepare_migration
    printf 'staged\n' > "$work/repo/staged"
    invoke git -C "$work/repo" add staged
    printf 'untracked\n' > "$work/repo/untracked"
    printf 'ignored\n' > "$work/repo/.gitignore"
    printf 'build output\n' > "$work/repo/ignored"
    mkdir -p "$work/harness/codex/sessions"
    printf 'private token\n' > "$case_root/auth.json"
    ln -s "$case_root/auth.json" "$work/harness/codex/auth.json"
    printf 'history\n' > "$work/harness/codex/sessions/continuation.jsonl"
    invoke git -C "$work/repo" config core.fsmonitor "touch $case_root/UNEXPECTED"
    mkdir -p "$queue"
    message "$queue/002"
    run invoke "$case_home/bin/mail-agent-migrate" inspect "$session"

    [ "$status" -eq 0 ]
    jq -e '.schema == 1 and .backend == "legacy" and .state == "paused" and
        .queue.entries == 1 and .workspace.files >= 4 and
        .history.symlinks == 1 and .storage.alternates == false and
        .storage.linked_objects == 0 and .metadata.turns.bytes > 0 and
        .ready == false' <<< "$output"
    [[ "$output" != *"private token"* ]]
    [ ! -e "$case_root/UNEXPECTED" ]
    [ -f "$work/repo/untracked" ]
    [ -f "$work/repo/ignored" ]
    [ -f "$queue/002" ]
}

@test "migration inspection detects multiply linked objects and alternates" {
    prepare_migration
    shared="$agent_root/repos/$(printf "%s" "$source_repo" | sed -e 's|^/||' -e 's|/|-|g')"
    object=$(find "$shared/objects" -type f | head -1)
    ln "$object" "$object.test-link"
    printf '%s\n' "$source_repo/.git/objects" > "$shared/objects/info/alternates"
    run invoke "$case_home/bin/mail-agent-migrate" inspect "$session"

    [ "$status" -eq 0 ]
    jq -e '.storage.linked_objects >= 1 and .storage.alternates == true and
        (.blockers | index("shared-object-links")) != null and
        (.blockers | index("git-alternates")) != null' <<< "$output"
}

@test "migration inspection rejects active streams and unsafe metadata pointers" {
    prepare_migration
    invoke "$case_home/bin/mail-agent-stream" resume "$session" > /dev/null
    run invoke "$case_home/bin/mail-agent-migrate" inspect "$session"

    [ "$status" -eq 75 ]
    invoke "$case_home/bin/mail-agent-stream" pause "$session" > /dev/null
    rm "$work/project"
    ln -s "$case_root/secret" "$work/project"
    run invoke "$case_home/bin/mail-agent-migrate" inspect "$session"

    [ "$status" -ne 0 ]
}

@test "migration inspection detects a pointer to another stream's worktree registration" {
    prepare_migration
    shared="$agent_root/repos/$(printf "%s" "$source_repo" | sed -e 's|^/||' -e 's|/|-|g')"
    invoke git -C "$shared" worktree add -q -b other "$case_root/other"
    cp "$case_root/other/.git" "$work/repo/.git"
    run invoke "$case_home/bin/mail-agent-migrate" inspect "$session"

    [ "$status" -eq 0 ]
    jq -e '.storage.worktree_pointer == false and
        (.blockers | index("worktree-registration")) != null' <<< "$output"
}
