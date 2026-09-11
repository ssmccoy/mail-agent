# Per-project provisioning helpers, sourced by mail-agent-system-project.
# Bash is used for a variable number of stream-lock file descriptors.

project_fail() {
    printf '%s\n' "$*" >&2
    return 78
}

project_git() {
    if [ "$(id -u)" -eq 0 ]; then
        runuser -u "$dispatcher" -- env GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
            git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"
    else
        env GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null \
            git -c core.hooksPath=/dev/null -c core.fsmonitor=false "$@"
    fi
}

project_load() {
    manifest=$1
    project_id=$2

    jq -e -f "$MAIL_AGENT_LIB/system/manifest.jq" "$manifest" >/dev/null || return 65
    jq -e --arg id "$project_id" '.projects | has($id)' "$manifest" >/dev/null || return 65
    dispatcher=$(jq -r .dispatcher "$manifest")
    account_home=$(getent passwd "$dispatcher" | cut -d: -f6)
    project_source=$(jq -r --arg id "$project_id" '.projects[$id].source' "$manifest")
    project_shared=$(jq -r --arg id "$project_id" '.projects[$id].shared' "$manifest")
    project_group=$(jq -r --arg id "$project_id" '.projects[$id].group' "$manifest")
    project_cache=$(jq -r --arg id "$project_id" '.projects[$id].cache' "$manifest")

    [ -n "$account_home" ] || project_fail "dispatcher account does not exist"
}

project_validate_storage() {
    local project_shared="$project_shared" project_cache="$project_cache" project_source="$project_source"

    [ ! -L "$project_shared" ] && [ ! -L "$project_cache" ] || { project_fail "storage must not be a symlink"; return 78; }

    project_shared=$(realpath -m -- "$project_shared")
    project_cache=$(realpath -m -- "$project_cache")
    project_source=${project_source:+$(realpath -m -- "$project_source")}

    for path in "$project_shared" "$project_cache"; do
        case "$path" in /|*/..|*/.) project_fail "invalid storage path: $path"; return 78 ;; esac

        if [ -n "$project_source" ]; then
            case "$project_source/" in "$path/"*) project_fail "storage contains the source: $path"; return 78 ;; esac
        fi
    done

    case "$project_shared/:$project_cache/" in
        "$project_cache/"*|*:"$project_shared/"*) project_fail "shared storage and cache overlap"; return 78 ;;
    esac

    return 0
}

project_validate_repository() {
    if [ -n "$project_source" ]; then
        [ -d "$project_source/.git" ] && [ ! -L "$project_source/.git" ] || {
            project_fail "source must have its own .git directory: $project_source"
            return 78
        }

        project_git -C "$project_source" rev-parse --verify HEAD >/dev/null
    fi

    if [ -e "$project_shared" ]; then
        [ "$(project_git -C "$project_shared" rev-parse --is-bare-repository)" = true ] || return 78
        [ ! -e "$project_shared/objects/info/alternates" ] || project_fail "resolve Git alternates before provisioning"
        [ -z "$(find "$project_shared" ! -type f ! -type d -print -quit)" ] || project_fail "shared storage contains symlinks or special files"
        project_git -C "$project_shared" fsck --connectivity-only --no-dangling
    fi
}

project_validate_runtime() {
    while IFS= read -r path; do
        [ -e "$path" ] || { project_fail "missing runtime path: $path"; return 78; }
    done < <(jq -r '[.runtime[], .harnesses[].runtime | if type == "object" then del(.configuration)[] else . end] | unique[]' "$manifest")

    while IFS= read -r path; do
        [ -f "$path" ] && [ ! -L "$path" ] || { project_fail "credential must be a regular file: $path"; return 78; }
    done < <(jq -r '.harnesses[].runtime.auth' "$manifest")
}

project_check() {
    project_validate_storage
    project_validate_repository
    project_validate_runtime
    state=absent
    links=0

    if [ -d "$project_shared" ]; then
        state=existing
        links=$(find "$project_shared" -type f -links +1 -printf '.\n' | wc -l)
    fi

    jq --arg id "$project_id" --arg state "$state" --argjson links "$links" \
        '{project: $id, dispatcher, storage: .projects[$id], harnesses: (.harnesses | keys),
          shared_state: $state, files_requiring_copy: $links}' "$manifest"
}

project_trusted() {
    path=$(realpath -e -- "$1")

    while [ "$path" != / ]; do
        [ "$(stat -c %u -- "$path")" -eq 0 ] || return 78
        [ -z "$(find "$path" -maxdepth 0 -perm /022 -print)" ] || return 78
        path=$(dirname "$path")
    done
}

project_lock_streams() {
    project_locks=()

    for work in "$account_home/mail/.agent/work/"*; do
        [ -d "$work" ] || continue
        [ "$(cat "$work/project" 2>/dev/null || true)" = "$project_source" ] || continue
        session=${work##*/}
        [[ "$session" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || return 78
        lock="$account_home/mail/.agent/lock/$session"

        [ -f "$lock" ] && [ ! -L "$lock" ] || { project_fail "missing stream lock: $session"; return 78; }
        exec {descriptor}<"$lock"
        flock --nonblock "$descriptor" || { printf "stream is active: %s\n" "$session" >&2; return 75; }
        project_locks+=("$descriptor")
    done
}

project_save_acl() {
    path=$1
    checksum=$(printf '%s' "$path" | sha256sum | cut -d ' ' -f1)
    record="$project_backup/$checksum.acl"

    if [ ! -f "$record" ]; then
        getfacl -p -- "$path" > "$record"
    fi
}

project_traverse() {
    path=$(dirname "$(realpath -e -- "$1")")
    group=$2

    while [ "$path" != / ]; do
        project_save_acl "$path"
        setfacl -m "g:$group:x" -- "$path"
        path=$(dirname "$path")
    done
}

project_create_groups() {
    for group in "$project_group" $(jq -r '.harnesses[].groups[]' "$manifest" | sort -u); do
        getent group "$group" >/dev/null || groupadd --system "$group"
    done
}

project_separate_objects() {
    while IFS= read -r -d '' file; do
        replacement=$(mktemp "${file%/*}/.independent.XXXXXXXX")
        cp --preserve=all --reflink=auto -- "$file" "$replacement"
        cmp -- "$file" "$replacement"
        mv -fT -- "$replacement" "$file"
    done < <(find "$project_shared" -type f -links +1 -print0)

    [ -z "$(find "$project_shared" -type f -links +1 -print -quit)" ] || return 78
}

project_repository() {
    if [ -d "$project_shared" ]; then
        cp -a --reflink=auto -- "$project_shared" "$project_backup/shared.git"
        project_separate_objects
    else
        [ -d "${project_shared%/*}" ] || install -d -o "$dispatcher" -m 0755 "${project_shared%/*}"

        if [ -n "$project_source" ]; then
            project_git clone --bare --no-hardlinks --dissociate -- "$project_source" "$project_shared"
        else
            project_git init --bare --shared=group "$project_shared"
        fi
    fi

    find "$project_shared" -type d -exec chgrp "$project_group" {} + -exec chmod g+rws {} +
    find "$project_shared" -type f -exec chgrp "$project_group" {} + -exec chmod g+rw {} +
    project_git -C "$project_shared" config core.sharedRepository 0660
    project_git -C "$project_shared" fsck --connectivity-only --no-dangling
    project_traverse "$project_shared" "$project_group"
}

project_source_access() {
    if [ -n "$project_source" ]; then
        getfacl -Rp "$project_source/.git" > "$project_backup/source.acl"
        setfacl -Rm "g:$project_group:rX" "$project_source/.git"
        project_traverse "$project_source/.git" "$project_group"
    fi

    install -d -o "$dispatcher" -g "$project_group" -m 2770 "$project_cache"
    project_traverse "$project_cache" "$project_group"
}

project_harness_configuration() {
    driver=$1
    directory=$(jq -r --arg driver "$driver" '.harnesses[$driver].runtime.configuration' "$manifest")

    if [ ! -d "$directory" ]; then
        install -d -m 0755 "$directory"
    fi

    case "$driver" in
        claude)
            if [ ! -e "$directory/settings.json" ]; then
                install -m 0644 "$MAIL_AGENT_LIB/system/claude-settings.json" "$directory/settings.json"
            fi
            ;;
        codex)
            if [ ! -e "$directory/config.toml" ]; then
                install -m 0644 "$MAIL_AGENT_LIB/system/codex-config.toml" "$directory/config.toml"
            fi
            ;;
    esac
}

project_read_path() {
    target=$(realpath -e -- "$1")
    group=$2
    checksum=$(printf '%s' "$target" | sha256sum | cut -d ' ' -f1)
    record="$project_backup/$checksum.runtime.acl"

    if [ ! -f "$record" ]; then
        getfacl -RPp -- "$target" > "$record"
    fi

    setfacl -RPm "g:$group:rX" -- "$target"
    project_traverse "$target" "$group"
}

project_runtime_access() {
    for driver in $(jq -r '.harnesses | keys[]' "$manifest"); do
        project_harness_configuration "$driver"
        credential=$(jq -r --arg driver "$driver" '.harnesses[$driver].runtime.auth' "$manifest")
        project_save_acl "$credential"

        for group in $(jq -r --arg driver "$driver" '.harnesses[$driver].groups[]' "$manifest"); do
            setfacl -m "g:$group:rw" -- "$credential"
            project_traverse "$credential" "$group"

            while IFS= read -r runtime_path; do
                project_read_path "$runtime_path" "$group"
            done < <(jq -r --arg driver "$driver" \
                '[.runtime[], (.harnesses[$driver].runtime | del(.auth)[])] | unique[]' "$manifest")
        done
    done
}

project_provision() {
    project_create_groups
    project_repository
    project_source_access
    project_runtime_access
}
