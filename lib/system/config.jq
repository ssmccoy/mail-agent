def identifier: type == "string" and test("^[a-z][a-z0-9_]{0,31}$");
def path: type == "string" and test("^/[A-Za-z0-9_@./-]+$") and (contains("/../") | not);
def endpoint:
    keys == ["address","family","port","protocol"] and
    (.family | IN("ip","ip6")) and (.protocol | IN("tcp","udp")) and
    (.address | type == "string" and test("^[0-9a-fA-F:./]+$")) and
    (.port | type == "number" and floor == . and . >= 1 and . <= 65535);
def policy:
    (keys - ["allow","driver","groups","mode","network","project","runtime","shared"] | length == 0) and
    (if has("network") then .network | identifier else true end) and
    (.driver | IN("claude","codex","pi")) and
    (.mode | IN("investigate","plan","execute","research")) and
    (.project | . == "" or path) and (.shared | path) and
    (.groups | type == "array" and length > 0 and length <= 16 and all(.[]; identifier)) and
    (.allow | type == "array" and length <= 256 and all(.[]; endpoint)) and
    (.runtime | type == "object" and
        keys == ["auth","binary","cache","configuration","git_config","instructions","packages","toolchain","toolchain_config"] and
        all(.[]; path));
def networks:
    . as $configuration |
    if has("networks") then
        (.networks | type == "object" and length > 0 and
            all(to_entries[]; (.key | identifier) and
                (.value | keys == ["allow", "mode"] and (.mode | IN("research", "restricted")) and
                    (.allow | type == "array" and length <= 256 and all(.[]; endpoint))))) and
        all(.policies[]; . as $policy |
            ($configuration.networks[.network] |
                .allow == ($policy.allow | unique) and
                .mode == (if $policy.mode == "research" then "research" else "restricted" end))) and
        ([.policies[].network] | unique | sort) == (.networks | keys)
    else all(.policies[]; has("network") | not) end;
select((keys - ["dispatcher","networks","policies","schema"] | length == 0) and .schema == 1 and
    (.dispatcher | identifier) and
    (.policies | type == "object" and length > 0 and length <= 64 and
        all(to_entries[]; (.key | identifier) and (.value | policy))) and
    ([.policies[] | [.project,.driver,.mode]] | unique | length) == (.policies | length) and networks)
