# Expand shared deployment definitions into fixed execution authorizations.
def identifier: type == "string" and test("^[a-z][a-z0-9_]{0,31}$");
def path: type == "string" and test("^/[A-Za-z0-9_@./-]+$") and (contains("/../") | not);
def modes: type == "array" and length > 0 and length <= 4 and
    (unique | length) == length and all(.[]; IN("investigate", "plan", "execute", "research"));
def endpoint:
    keys == ["address", "family", "port", "protocol"] and
    (.family | IN("ip", "ip6")) and (.protocol | IN("tcp", "udp")) and
    (.address | type == "string" and test("^[0-9a-fA-F:./]+$")) and
    (.port | type == "number" and floor == . and . >= 1 and . <= 65535);
def references($endpoints): type == "array" and all(.[]; identifier and in($endpoints));
def harness($endpoints):
    keys == ["endpoints", "groups", "runtime"] and
    (.endpoints | references($endpoints)) and
    (.groups | type == "array" and length > 0 and length <= 15 and all(.[]; identifier)) and
    (.runtime | keys == ["auth", "binary", "configuration", "packages"] and all(.[]; path));
def project($endpoints):
    (keys - ["cache", "endpoints", "group", "modes", "shared", "source"] | length == 0) and
    (.source | . == "" or path) and (.shared | path) and (.cache | path) and
    (.group | identifier) and (.endpoints | references($endpoints)) and
    (if has("modes") then .modes | modes else true end) and
    (if .source == "" then .modes == ["research"] else true end);
def valid_manifest:
    .endpoints as $endpoints |
    keys == ["dispatcher", "endpoints", "harnesses", "modes", "projects", "runtime", "schema"] and
    .schema == 2 and (.dispatcher | identifier) and (.modes | modes) and
    (.runtime | keys == ["git_config", "instructions", "toolchain", "toolchain_config"] and all(.[]; path)) and
    (.endpoints | type == "object" and all(to_entries[];
        (.key | identifier) and (.value | type == "array" and length <= 256 and all(.[]; endpoint)))) and
    (.harnesses | type == "object" and length > 0 and
        all(to_entries[]; (.key | IN("claude", "codex", "pi")) and (.value | harness($endpoints)))) and
    (.projects | type == "object" and length > 0 and length <= 64 and
        all(to_entries[]; (.key | test("^[a-z][a-z0-9_]{0,19}$")) and (.value | project($endpoints)))) and
    ([.projects[].source] | unique | length) == (.projects | length) and
    ([.projects[].shared] | unique | length) == (.projects | length);
def driver_id: {claude: "cld", codex: "cdx", pi: "pi"}[.];
def mode_id: {investigate: "inv", plan: "plan", execute: "exec", research: "res"}[.];
def authorizations:
    . as $manifest |
    [.projects | to_entries[] | . as $project |
        $manifest.harnesses | to_entries[] | . as $harness |
        ($project.value.modes // $manifest.modes)[] as $mode |
        {key: ($project.key + "_" + ($harness.key | driver_id) + "_" + ($mode | mode_id)),
         value: {
            project: $project.value.source, shared: $project.value.shared,
            driver: $harness.key, mode: $mode,
            groups: ([$project.value.group] + $harness.value.groups | unique),
            runtime: ($manifest.runtime + $harness.value.runtime + {cache: $project.value.cache}),
            allow: (if $mode == "research" then [] else
                [$harness.value.endpoints[], $project.value.endpoints[] |
                    $manifest.endpoints[.][]] | unique end)
         }}] | from_entries;
def network_policy:
    {mode: (if .mode == "research" then "research" else "restricted" end), allow: (.allow | unique)};
def compile:
    {schema: 1, dispatcher: .dispatcher, policies: authorizations} |
    ([.policies[] | network_policy] | unique) as $networks |
    .networks = ($networks | to_entries | map({key: ("n" + (.key | tostring)), value: .value}) | from_entries) |
    .policies |= with_entries(.value |= (. as $policy |
        .network = ("n" + ($networks | index($policy | network_policy) | tostring))));
if valid_manifest then compile |
    if (.policies | length) <= 64 and all(.policies[]; (.allow | length) <= 256)
    then . else error("deployment exceeds authorization or endpoint limits") end
else error("invalid deployment manifest") end
