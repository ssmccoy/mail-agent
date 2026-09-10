load helper

prepare_phase() {
    new_repository
    mkdir -p "$work/repo" "$case_root/result"
    printf 'Please inspect.\n' > "$case_root/result/prompt"
    jq -n '{schema:1,task:"001",driver:"fixture",mode:"investigate",model:"-",effort:""}' > "$case_root/result/request.json"
}

@test "phase interface executes an approved driver and reports its result" {
    prepare_phase
    run invoke "$case_home/bin/mail-agent-phase" "$work" "$case_root/result"

    [ "$status" -eq 0 ]
    [ "$(jq -r '.task' "$case_root/result/outcome.json")" = 001 ]
    [ "$(jq -r '.status' "$case_root/result/outcome.json")" = 0 ]
    [ -s "$case_root/result/reply.md" ]
    [ "$(mail_count)" -eq 0 ]
}

@test "phase rejects executable selection and malformed requests before execution" {
    prepare_phase
    cp "$case_root/result/request.json" "$case_root/original"

    for mutation in '.driver="../../bin/sh"' '.mode="unknown"' '.command="touch unexpected"' '.model="--config bad"' '.model="--version"' '.task="../another"'; do
        jq "$mutation" "$case_root/result/request.json" > "$case_root/request"
        mv "$case_root/request" "$case_root/result/request.json"
        run invoke "$case_home/bin/mail-agent-phase" "$work" "$case_root/result"

        [ "$status" -ne 0 ]
        [ ! -e "$case_root/driver-arguments" ]
        cp "$case_root/original" "$case_root/result/request.json"
    done
}

@test "phase preserves timeout and driver failure exit statuses" {
    prepare_phase

    for expected in 75 124; do
        printf '%s\n' "$expected" > "$case_root/status"
        run invoke "$case_home/bin/mail-agent-phase" "$work" "$case_root/result"

        [ "$status" -eq "$expected" ]
        [ "$(jq -r '.status' "$case_root/result/outcome.json")" = "$expected" ]
    done
}
