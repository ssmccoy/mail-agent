setup() {
    project_root="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    case_root="$BATS_TEST_TMPDIR/case"
    case_home="$case_root/home"
    session="11111111-1111-4111-a111-111111111111"
    agent_root="$case_home/mail/.agent"
    work="$agent_root/work/$session"
    queue="$agent_root/queue/$session"
    source_repo="$case_root/source"

    mkdir -p "$case_home/bin" "$case_home/.config/mail-agent" \
        "$case_home/.local/bin" "$case_home/.config/landlock" \
        "$case_root/tmp" "$case_root/outgoing" "$agent_root/lock" \
        "$agent_root/repos" "$queue"
    cp "$project_root"/config/* "$case_home/.config/mail-agent/"

    # Wrappers select the interpreter for nested invocations as well.
    for script in "$project_root"/bin/*; do
        if [ "$(head -1 "$script")" = "#!/bin/sh" ]; then
            printf '#!/bin/sh\nexec %s "%s" "$@"\n' \
                "${TEST_SHELL:-/bin/sh}" "$script" \
                > "$case_home/bin/${script##*/}"
        else
            cp "$script" "$case_home/bin/"
        fi
    done

    chmod +x "$case_home"/bin/*
    cp "$project_root/test/commands/driver" "$case_home/bin/mail-agent-fixture"
    printf "fixture fixture -\n" >> "$case_home/.config/mail-agent/agents"

    child_env=(env -i "HOME=$case_home" "PATH=/usr/bin:/bin"
        "TMPDIR=$case_root/tmp" "LC_ALL=C" "TZ=UTC"
        "GIT_CONFIG_NOSYSTEM=1" "GIT_CONFIG_GLOBAL=/dev/null"
        "GIT_AUTHOR_NAME=Test Author" "GIT_AUTHOR_EMAIL=author@example.invalid"
        "GIT_COMMITTER_NAME=Test Author" "GIT_COMMITTER_EMAIL=author@example.invalid"
        "MAIL_AGENT_USER=test" "CASE_ROOT=$case_root"
        "MAIL_AGENT_SENDMAIL=$project_root/test/commands/sendmail"
        "MAIL_AGENT_SYSTEMD_RUN=$project_root/test/commands/systemd-run"
        "MAIL_AGENT_OUTPUT_DIR=$case_root/tmp")
}

invoke() {
    "${child_env[@]}" "$@"
}

new_repository() {
    invoke git init -q -b main "$source_repo"
    printf "original\n" > "$source_repo/file"
    invoke git -C "$source_repo" add file
    invoke git -C "$source_repo" commit -qm "Create example file"
    printf "sample %s\n" "$source_repo" > "$case_home/.config/mail-agent/projects"
}

message() {
    local destination="$1"
    local body="${2:-Please inspect.}"
    local subject="${3:-sample: example}"

    printf 'From: Sender <sender@example.invalid>\nTo: test+fixture@example.invalid\nSubject: %s\nMessage-Id: <incoming@example.invalid>\nX-Mail-Agent: fixture\n\n%s\n' \
        "$subject" "$body" > "$destination"
}

message_with_attachment() {
    local destination="$1"
    local attachment="$case_root/attached.txt"

    printf "attachment contents\n" > "$attachment"
    {
        printf "From: Sender <sender@example.invalid>\n"
        printf "To: test+fixture@example.invalid\n"
        printf "Subject: sample: example\n"
        printf "Message-Id: <incoming@example.invalid>\n"
        printf "X-Mail-Agent: fixture\n\n"
        printf "Please inspect the attachment.\n"
        printf "#text/plain %s>example.txt\n" "$attachment"
    } | mmime > "$destination"
}

run_turn() {
    invoke "$case_home/bin/mail-agent-run" "$session"
}

mail_count() {
    find "$case_root/outgoing" -type f | wc -l
}
