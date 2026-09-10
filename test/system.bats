load helper

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

@test "system installation stages strict profiles without changing the home executor" {
    run make -C "$project_root" install-system DESTDIR="$case_root/stage"

    [ "$status" -eq 0 ]
    [ -x "$case_root/stage/usr/local/libexec/mail-agent/mail-agent-system-phase" ]
    ! grep -R '^best-effort' "$case_root/stage/etc/mail-agent/profiles"
    ! grep -R '^connect-tcp' "$case_root/stage/etc/mail-agent/profiles"
    grep -Fx 'unrestricted-network' "$case_root/stage/etc/mail-agent/profiles/mail-agent-codex.cfg"
    [ "$(cat "$case_home/.config/mail-agent/backend")" = legacy ]
}

