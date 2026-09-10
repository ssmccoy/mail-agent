load helper

file_call() {
    invoke "$case_home/bin/mail-agent-files" "$case_root/downloads" < "$case_root/request"
}

@test "file tools preserve contents and reject writes outside the working area" {
    mkdir -p "$case_root/downloads"
    jq -n --arg path "$case_root/downloads/a file" \
        '{id:1,method:"tools/call",params:{name:"write",arguments:{path:$path,content:"one\n\ntwo\n"}}}' -c > "$case_root/request"
    run file_call

    [ "$status" -eq 0 ]
    [ "$(jq -r '.result.isError' <<< "$output")" = false ]
    printf 'one\n\ntwo\n' > "$case_root/expected"
    cmp "$case_root/expected" "$case_root/downloads/a file"
    jq --arg path "$case_root/outside" '.params.arguments.path=$path' -c "$case_root/request" > "$case_root/denied"
    mv "$case_root/denied" "$case_root/request"
    run file_call

    [ "$(jq -r '.result.isError' <<< "$output")" = true ]
    [ ! -e "$case_root/outside" ]
}

@test "file tools edit one exact match and report ambiguous replacements" {
    mkdir -p "$case_root/downloads"
    printf 'first\nlast\n' > "$case_root/downloads/example"
    jq -n --arg path "$case_root/downloads/example" \
        '{id:1,method:"tools/call",params:{name:"edit",arguments:{path:$path,old:"first",new:"last"}}}' -c > "$case_root/request"
    run file_call

    [ "$(jq -r '.result.isError' <<< "$output")" = false ]
    [ "$(cat "$case_root/downloads/example")" = $'last\nlast' ]
    jq '.params.arguments.old="last"' -c "$case_root/request" > "$case_root/ambiguous"
    mv "$case_root/ambiguous" "$case_root/request"
    run file_call

    [ "$(jq -r '.result.isError' <<< "$output")" = true ]
    [ "$(cat "$case_root/downloads/example")" = $'last\nlast' ]
}

@test "file tools reject traversal and symlinks leaving the working area" {
    mkdir -p "$case_root/downloads" "$case_root/elsewhere"
    ln -s "$case_root/elsewhere" "$case_root/downloads/link"

    for path in "$case_root/downloads/../escaped" "$case_root/downloads/link/escaped"; do
        jq -n --arg path "$path" \
            '{id:1,method:"tools/call",params:{name:"write",arguments:{path:$path,content:"bad"}}}' -c > "$case_root/request"
        run file_call

        [ "$(jq -r '.result.isError' <<< "$output")" = true ]
    done

    [ ! -e "$case_root/escaped" ]
    [ ! -e "$case_root/elsewhere/escaped" ]
}

@test "MCP initialization and discovery expose only read write and edit" {
    mkdir -p "$case_root/downloads"
    printf '%s\n' \
        '{"id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}' \
        '{"method":"notifications/initialized"}' \
        '{"id":2,"method":"tools/list"}' > "$case_root/request"
    run file_call

    [ "$status" -eq 0 ]
    [ "$(jq -s 'length' <<< "$output")" -eq 2 ]
    [ "$(jq -r 'select(.id==2)|.result.tools[].name' <<< "$output")" = $'read\nwrite\nedit' ]
}
