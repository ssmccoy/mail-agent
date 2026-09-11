load helper

@test "system configuration renders all modes for seven projects and both harnesses" {
    jq '.policies.example_codex_execute.runtime.packages = "/opt/node_modules/@vendor/harness" |
        .policies.example_codex_execute as $template |
        .policies = ([range(0; 7) as $project |
            ["codex", "claude"][] as $driver |
            ["investigate", "plan", "execute", "research"][] as $mode |
            {key: "p\($project)_\($driver)_\($mode)",
             value: ($template | .project = "/srv/project\($project)" |
                 .driver = $driver | .mode = $mode)}] +
            [["codex", "claude"][] as $driver |
            {key: "free_\($driver)_research",
             value: ($template | .project = "" | .driver = $driver |
                 .mode = "research")}] | from_entries)' \
        "$project_root/system/system.example.json" > "$case_root/policy.json"
    run invoke "$case_home/bin/mail-agent-system-config" "$case_root/policy.json" "$case_root/compiled"

    [ "$status" -eq 0 ]
    [ "$(jq '.policies | length' "$case_root/compiled/system.json")" -eq 58 ]

    for policy in $(jq -r '.policies | keys[]' "$case_root/policy.json"); do
        [ -f "$case_root/compiled/mail-agent-$policy@.service" ]
        [ -f "$case_root/compiled/$policy.env" ]
        [ -f "$case_root/compiled/mailagent-$policy.slice" ]
    done
}

@test "system configuration rejects request-controlled policy and invalid endpoints" {
    run jq -e -f "$project_root/lib/system/config.jq" "$project_root/system/system.example.json"

    [ "$status" -eq 0 ]
    for mutation in '.policies.example_codex_execute.runtime.binary="/bin/sh;id"' \
        '.policies.example_codex_execute.allow=[{family:"ip",address:"127.0.0.1; accept",protocol:"tcp",port:80}]' \
        '.policies.example_codex_execute.allow=[{family:"ip",address:"127.0.0.1",protocol:"tcp",port:0}]' \
        '.policies.example_codex_execute.command="anything"'; do
        jq "$mutation" "$project_root/system/system.example.json" > "$case_root/policy.json"
        run jq -e -f "$project_root/lib/system/config.jq" "$case_root/policy.json"

        [ "$status" -ne 0 ]
    done
}

@test "system units deny network access by default and serialize policy variants" {
    jq '.policies.other = (.policies.example_codex_execute | .mode="research")' \
        "$project_root/system/system.example.json" > "$case_root/policy.json"
    run invoke "$case_home/bin/mail-agent-system-config" "$case_root/policy.json" "$case_root/compiled"

    [ "$status" -eq 0 ]
    unit="$case_root/compiled/mail-agent-example_codex_execute@.service"
    grep -Fx 'DynamicUser=yes' "$unit"
    grep -Fx 'StateDirectory=mail-agent-%i' "$unit"
    grep -Fx 'Conflicts=mail-agent-other@%i.service' "$unit"
    grep -Fx 'After=mail-agent-other@%i.service' "$unit"
    grep -Fx 'KillMode=control-group' "$unit"
    grep -F 'drop' "$case_root/compiled/firewall.nft"
    ! grep -F 'IPAddressAllow' "$unit"
    ! grep -F 'best-effort' "$case_root/compiled/phase.cfg"
}

system_phase_setup() {
    new_repository
    state="$case_root/system-state"
    service_runtime="$case_root/system-runtime"
    submissions="$case_root/submissions"
    results="$case_root/results"
    shared="$case_root/shared.git"
    invoke git clone -q --bare --no-hardlinks "$source_repo" "$shared"
    mkdir -p "$state" "$service_runtime" "$submissions/request1" "$results"
    jq -n --arg base "$(git -C "$source_repo" rev-parse HEAD)" \
        '{schema:1,request:"request1",task:"task1",action:"prepare",driver:"codex",mode:"execute",
          model:"-",effort:"",branch:"main",base:$base,agent_session:""}' > "$submissions/request.json"
    printf '#!/bin/sh\nexec git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"\n' \
        > "$case_home/bin/mail-agent-system-git"
    chmod +x "$case_home/bin/mail-agent-system-git"
    cp "$project_root/test/commands/driver" "$case_home/bin/mail-agent-codex"
    child_env+=("MAIL_AGENT_SYSTEM_RESULT_GROUP=$(id -g)" "STATE_DIRECTORY=$state" "RUNTIME_DIRECTORY=$service_runtime"
        "INVOCATION_ID=11111111111111111111111111111111" "SERVICE_RESULT=success"
        "MAIL_AGENT_SYSTEM_SESSION=$session" "MAIL_AGENT_SYSTEM_REQUEST=$submissions/request.json"
        "MAIL_AGENT_SYSTEM_INPUT=$submissions" "MAIL_AGENT_SYSTEM_OUTPUT=$results"
        "MAIL_AGENT_SYSTEM_PROJECT=$source_repo" "MAIL_AGENT_SYSTEM_SHARED=$shared"
        "MAIL_AGENT_SYSTEM_DRIVER=codex" "MAIL_AGENT_SYSTEM_MODE=execute")
}

@test "system phase prepares private Git state and exports correlated results" {
    system_phase_setup
    run invoke env MAIL_AGENT_SYSTEM_STAGE=run "$case_home/bin/mail-agent-system-phase"

    [ "$status" -eq 0 ]
    run invoke env MAIL_AGENT_SYSTEM_STAGE=export "$case_home/bin/mail-agent-system-phase"

    [ "$status" -eq 0 ]
    [ -f "$state/work/repo/file" ]
    [ ! -d "$work" ]
    jq -e '.request == "request1" and .task == "task1" and .status == 0' "$results/request1/outcome.json"
    cmp "$results/request1/head" "$state/work/base"
}

@test "system phase rejects a mode mismatch before executing a driver" {
    system_phase_setup
    run invoke env MAIL_AGENT_SYSTEM_STAGE=run MAIL_AGENT_SYSTEM_MODE=research \
        "$case_home/bin/mail-agent-system-phase"

    [ "$status" -ne 0 ]
    [ ! -e "$state/control" ]
    [ ! -e "$case_root/driver-arguments" ]
}

@test "bounded state copies reject special files and preserve working symlinks" {
    mkdir -p "$case_root/input"
    printf 'contents\n' > "$case_root/input/file"
    ln -s file "$case_root/input/link"
    run invoke "$case_home/bin/mail-agent-system-copy" "$case_root/input" "$case_root/copied" 1024

    [ "$status" -eq 0 ]
    [ "$(readlink "$case_root/copied/link")" = file ]
    mkfifo "$case_root/input/pipe"
    run invoke "$case_home/bin/mail-agent-system-copy" "$case_root/input" "$case_root/rejected" 1024

    [ "$status" -ne 0 ]
    [ ! -e "$case_root/rejected" ]
}

system_dispatch_setup() {
    new_repository
    shared="$case_root/shared.git"
    invoke git clone -q --bare --no-hardlinks "$source_repo" "$shared"
    jq --arg project "$source_repo" --arg shared "$shared" \
        '.policies.example_codex_execute.project=$project |
         .policies.example_codex_execute.shared=$shared' \
        "$project_root/system/system.example.json" > "$case_root/system.json"
    printf 'fixture codex -\n' > "$case_home/.config/mail-agent/agents"
    printf 'system\n' > "$case_home/.config/mail-agent/backend"
    touch "$case_root/qualified"
    mkdir -p "$case_root/submissions" "$case_root/results"
    cp "$project_root/test/commands/driver" "$case_home/bin/mail-agent-codex"
    printf '#!/bin/sh\nexec git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"\n' \
        > "$case_home/bin/mail-agent-system-git"
    chmod +x "$case_home/bin/mail-agent-system-git"
    child_env+=("MAIL_AGENT_SYSTEM_CONFIG=$case_root/system.json"
        "MAIL_AGENT_SYSTEM_QUALIFIED=$case_root/qualified"
        "MAIL_AGENT_SYSTEM_SUBMISSIONS=$case_root/submissions"
        "MAIL_AGENT_SYSTEM_RESULTS=$case_root/results"
        "MAIL_AGENT_SYSTEMCTL=$project_root/test/commands/systemctl")
}

@test "system dispatcher executes private work and mails exported patches" {
    system_dispatch_setup
    message "$queue/001" $'!execute\nPlease implement.'
    touch "$case_root/commit"
    run run_turn

    [ "$status" -eq 0 ]
    [ "$(mail_count)" -ge 2 ]
    [ -f "$case_root/private/$session/work/repo/file" ]
    [ ! -e "$work/repo" ]
    [ -f "$work/mailed" ]
    [ -f "$work/agent-session" ]
    [ "$(cat "$source_repo/file")" = original ]
    [ "$(jq -r .backend "$agent_root/streams/$session.json")" = system ]
    [ ! -e "$queue/001" ]
}

@test "system submission failure never invokes the local driver" {
    system_dispatch_setup
    message "$queue/001" $'!execute\nPlease implement.'
    touch "$case_root/system-fail"
    run run_turn

    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 1 ]
    [ ! -e "$case_root/driver-arguments" ]
    [ ! -e "$queue/001" ]
}

@test "global admission leaves mail queued when all slots are occupied" {
    new_repository
    printf '1\n' > "$case_home/.config/mail-agent/concurrency"
    message "$queue/001"
    mkdir -p "$agent_root/slots"
    exec 7> "$agent_root/slots/1"
    flock -n 7
    run invoke "$case_home/bin/mail-agent-admit" "$session"

    [ "$status" -eq 0 ]
    [ -f "$queue/001" ]
    [ ! -e "$case_root/driver-arguments" ]
    exec 7>&-
    run invoke "$case_home/bin/mail-agent-admit" "$session"

    [ "$status" -eq 0 ]
    [ ! -e "$queue/001" ]
}

@test "migration verifies private state and restores subsequent work on rollback" {
    system_dispatch_setup
    printf 'legacy\n' > "$case_home/.config/mail-agent/backend"
    message "$queue/001" $'!execute\nPlease inspect.'
    run run_turn

    [ "$status" -eq 0 ]
    legacy_shared=$(sed -n 's|^gitdir: \(.*\)/worktrees/.*|\1|p' "$work/repo/.git")
    jq --arg shared "$legacy_shared" '.policies.example_codex_execute.shared=$shared' \
        "$case_root/system.json" > "$case_root/system.new"
    mv "$case_root/system.new" "$case_root/system.json"
    printf 'staged\n' > "$work/repo/file"
    invoke git -C "$work/repo" add file
    printf 'unstaged\n' >> "$work/repo/file"
    printf 'ignored\n' > "$work/repo/working-cache"
    # Fixture drivers produce an ID without a transcript; this test focuses on
    # repository and index transfer rather than native CLI continuation.
    rm -f "$work/agent-session"
    invoke "$case_home/bin/mail-agent-stream" pause "$session"
    run invoke "$case_home/bin/mail-agent-migrate" apply "$session"

    [ "$status" -eq 0 ]
    [ "$(jq -r .backend "$agent_root/streams/$session.json")" = system ]
    [ "$(jq -r .state "$agent_root/streams/$session.json")" = paused ]
    cmp "$work/repo/file" "$case_root/private/$session/work/repo/file"
    printf 'private progress\n' >> "$case_root/private/$session/work/repo/file"
    run invoke "$case_home/bin/mail-agent-migrate" rollback "$session"

    [ "$status" -eq 0 ]
    [ "$(jq -r .backend "$agent_root/streams/$session.json")" = legacy ]
    grep -F 'private progress' "$work/repo/file"
    [ "$(cat "$work/repo/working-cache")" = ignored ]
    run invoke "$case_home/bin/mail-agent-migrate" apply "$session"

    [ "$status" -eq 0 ]
    [ "$(jq -r .backend "$agent_root/streams/$session.json")" = system ]
}

@test "system installation stages strict profiles without changing the home executor" {
    run make -C "$project_root" install-system DESTDIR="$case_root/stage"

    [ "$status" -eq 0 ]
    [ -x "$case_root/stage/usr/local/libexec/mail-agent/mail-agent-system-phase" ]
    ! grep -R '^best-effort' "$case_root/stage/etc/mail-agent/profiles"
    ! grep -R '^connect-tcp' "$case_root/stage/etc/mail-agent/profiles"
    grep -Fx 'unrestricted-network' "$case_root/stage/etc/mail-agent/profiles/mail-agent-codex.cfg"
    [ "$(cat "$case_home/.config/mail-agent/backend")" = legacy ]
}

@test "admission reserves a slot for a service whose controller exited" {
    system_dispatch_setup
    printf '1\n' > "$case_home/.config/mail-agent/concurrency"
    mkdir -p "$agent_root/slots" "$agent_root/streams"
    printf 'previous\n' > "$agent_root/slots/1.owner"
    printf '{"schema":1,"state":"active","backend":"system"}\n' > "$agent_root/streams/previous.json"
    touch "$case_root/system-busy"
    message "$queue/001"
    run invoke "$case_home/bin/mail-agent-admit" "$session"

    [ "$status" -eq 0 ]
    [ -f "$queue/001" ]
    [ "$(cat "$agent_root/slots/1.owner")" = previous ]
    [ ! -e "$case_root/driver-arguments" ]
}

@test "invalid exported files fail the task without following symlinks" {
    system_dispatch_setup
    message "$queue/001" $'!execute\nPlease inspect.'
    touch "$case_root/corrupt-export"
    printf 'confidential fixture\n' > "$case_root/secret"
    run run_turn

    [ "$status" -eq 0 ]
    [ "$(mail_count)" -eq 1 ]
    ! grep -R -F 'confidential fixture' "$case_root/outgoing"
    [ ! -e "$queue/001" ]
}

@test "system phases change mode and branch without using a legacy checkout" {
    system_dispatch_setup
    jq '.policies.plan = (.policies.example_codex_execute | .mode="plan")' \
        "$case_root/system.json" > "$case_root/system.new"
    mv "$case_root/system.new" "$case_root/system.json"
    message "$queue/001" '!execute'
    run_turn
    invoke git -C "$source_repo" checkout -qb release
    printf 'release\n' > "$source_repo/file"
    invoke git -C "$source_repo" commit -qam "Prepare release"
    release=$(invoke git -C "$source_repo" rev-parse HEAD)
    mkdir -p "$queue"
    message "$queue/002" $'!plan\n!branch release\nInspect release.'
    run run_turn

    [ "$status" -eq 0 ]
    [ "$(cat "$work/base")" = "$release" ]
    [ "$(cat "$work/branch")" = release ]
    [ "$(cat "$case_root/private/$session/work/repo/file")" = release ]
    [ ! -e "$work/repo" ]
    grep -Fx 'Mode: plan' "$case_root/prompts"
}

@test "system forks import history into a separate stream at the selected reply" {
    system_dispatch_setup
    message "$queue/001" '!execute'
    run_turn
    first_reply=$(cut -d ' ' -f1 "$work/turns")
    first_commit=$(cat "$work/base")
    mkdir -p "$queue"
    message "$queue/002" '!execute'
    touch "$case_root/commit"
    run_turn
    mkdir -p "$queue"
    message "$queue/003" '!execute'
    sed -i "1iIn-Reply-To: $first_reply" "$queue/003"
    run run_turn

    [ "$status" -eq 0 ]
    child=$(tail -1 "$case_root/scheduled")
    [ "$child" != "$session" ]
    [ "$(cat "$agent_root/work/$child/base")" = "$first_commit" ]
    [ -d "$agent_root/work/$child/import-history/codex" ]
    run invoke "$case_home/bin/mail-agent-run" "$child"

    [ "$status" -eq 0 ]
    [ "$(invoke git -C "$case_root/private/$child/work/repo" rev-parse HEAD)" = "$first_commit" ]
    [ "$(jq -r .backend "$agent_root/streams/$child.json")" = system ]
    [ ! -e "$agent_root/work/$child/repo" ]
}

@test "deployment manifests share network policies across projects harnesses and modes" {
    jq '.projects.cached = (.projects.example | .source="/srv/source/cached" |
        .shared="/var/lib/mail-agent-repositories/cached" | .group="ma_cached" |
        .cache="/var/cache/mail-agent/cached" | .endpoints=["depot"])' \
        "$project_root/system/manifest.example.json" > "$case_root/manifest.json"
    run invoke "$case_home/bin/mail-agent-system-config" "$case_root/manifest.json" "$case_root/compiled"

    [ "$status" -eq 0 ]
    jq -e '(.policies | length) == 18 and (.networks | length) == 5' "$case_root/compiled/system.json"

    for policy in $(jq -r '.policies | keys[]' "$case_root/compiled/system.json"); do
        network=$(jq -r --arg policy "$policy" '.policies[$policy].network' "$case_root/compiled/system.json")
        grep -Fx "Slice=mailagent-$network.slice" "$case_root/compiled/mail-agent-$policy@.service"
        [ -f "$case_root/compiled/mailagent-$network.slice" ]
        [ ! -f "$case_root/compiled/mailagent-$policy.slice" ]
    done

    run invoke "$case_home/bin/mail-agent-system-config" "$case_root/manifest.json" "$case_root/repeated"

    [ "$status" -eq 0 ]
    diff -r "$case_root/compiled" "$case_root/repeated"
}

@test "deployment manifests reject unresolved references and inconsistent project definitions" {
    for mutation in '.projects.example.endpoints=["missing"]' \
        '.projects.example.modes=["unknown"]' \
        '.harnesses.codex.runtime.auth="relative"' \
        '.harnesses.codex.runtime.command="/bin/sh"' \
        '.projects.duplicate=.projects.example' \
        '.projects.research.modes=["execute"]'; do
        jq "$mutation" "$project_root/system/manifest.example.json" > "$case_root/manifest.json"
        run invoke "$case_home/bin/mail-agent-system-config" "$case_root/manifest.json" "$case_root/compiled"

        [ "$status" -ne 0 ]
        [ ! -e "$case_root/compiled" ]
    done
}

project_fixture() {
    child_env+=("MAIL_AGENT_LIB=$case_home/lib/mail-agent")

    new_repository
    mkdir -p "$case_root/packages" "$case_root/toolchain" "$case_root/git-config" "$case_root/harness"
    touch "$case_root/packages/program"
    chmod 755 "$case_root/packages/program"
    touch "$case_root/auth.json" "$case_root/instructions" "$case_root/toolchain-config"
    jq --arg root "$case_root" --arg source "$source_repo" --arg account "$(id -un)" --arg group "$(id -gn)" '
        .dispatcher=$account | .harnesses |= {codex: .codex} |
        .harnesses.codex.groups=[$group] |
        .harnesses.codex.runtime={binary:($root+"/packages/program"),packages:($root+"/packages"),
            configuration:($root+"/harness"),auth:($root+"/auth.json")} |
        .runtime={git_config:($root+"/git-config"),instructions:($root+"/instructions"),
            toolchain:($root+"/toolchain"),toolchain_config:($root+"/toolchain-config")} |
        .projects={example:{source:$source,shared:($root+"/shared.git"),group:$group,
            cache:($root+"/cache"),endpoints:[]}}' "$project_root/system/manifest.example.json" > "$case_root/manifest.json"
}

@test "project checks describe provisioning without modifying repositories or credentials" {
    project_fixture
    before=$(sha256sum "$case_root/auth.json")
    run invoke "$case_home/bin/mail-agent-system-project" check "$case_root/manifest.json" example

    [ "$status" -eq 0 ]
    printf '%s\n' "$output" | jq -e '.shared_state == "absent" and .files_requiring_copy == 0'
    [ ! -e "$case_root/shared.git" ]
    [ ! -e "$case_root/cache" ]
    [ "$(sha256sum "$case_root/auth.json")" = "$before" ]

    run invoke "$case_home/bin/mail-agent-system-project" check "$case_root/manifest.json" missing

    [ "$status" -ne 0 ]
}

@test "project provisioning preserves refs and separates source object hardlinks on repeated runs" {
    project_fixture
    invoke git clone -q --bare "$source_repo" "$case_root/shared.git"
    original=$(git -C "$case_root/shared.git" rev-parse HEAD)
    object=$(find "$case_root/shared.git/objects" -type f -links +1 -print -quit)

    [ -n "$object" ]

    for attempt in first second; do
        run invoke bash -eu -c '
            . "$1/lib/system/project.sh"
            project_traverse() { :; }
            project_load "$2/manifest.json" example
            project_check >/dev/null
            project_backup="$2/backup-$3"
            mkdir "$project_backup"
            project_provision
        ' provision "$project_root" "$case_root" "$attempt"

        [ "$status" -eq 0 ]
        [ "$(git -C "$case_root/shared.git" rev-parse HEAD)" = "$original" ]
        [ "$(git -C "$source_repo" rev-parse HEAD)" = "$original" ]
        [ -z "$(find "$case_root/shared.git" -type f -links +1 -print -quit)" ]
        [ -f "$case_root/backup-$attempt/shared.git/HEAD" ]
    done
}

@test "compiled network assignments cannot broaden a restricted policy" {
    run invoke "$case_home/bin/mail-agent-system-config" "$project_root/system/manifest.example.json" "$case_root/compiled"

    [ "$status" -eq 0 ]
    jq '(.policies | to_entries | map(select(.value.mode == "research"))[0].value.network) as $research |
        .policies.example_cdx_exec.network=$research' "$case_root/compiled/system.json" > "$case_root/invalid.json"
    run jq -e -f "$project_root/lib/system/config.jq" "$case_root/invalid.json"

    [ "$status" -ne 0 ]
}

@test "project provisioning refuses an active stream before repository maintenance" {
    project_fixture
    mkdir -p "$work" "$agent_root/lock"
    printf '%s\n' "$source_repo" > "$work/project"
    exec {lock_fd}>"$agent_root/lock/$session"
    flock --nonblock "$lock_fd"
    run invoke bash -eu -c '
        . "$1/lib/system/project.sh"
        project_load "$2/manifest.json" example
        account_home=$3
        project_lock_streams
    ' provision "$project_root" "$case_root" "$case_home"

    [ "$status" -eq 75 ]
    [ ! -e "$case_root/shared.git" ]
    exec {lock_fd}>&-
}

@test "project checks reject storage aliases that contain the source" {
    project_fixture
    jq --arg cache "$case_root//" '.projects.example.cache=$cache' \
        "$case_root/manifest.json" > "$case_root/aliased.json"
    run invoke "$case_home/bin/mail-agent-system-project" check "$case_root/aliased.json" example

    [ "$status" -eq 78 ]
    [[ "$output" == *"storage contains the source"* ]]
}
