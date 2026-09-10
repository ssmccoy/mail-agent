def classifier($level; $path): "socket cgroupv2 level " + ($level|tostring) + " \"" + $path + "\"";
def rules($direction):
    .policies | to_entries[] | . as $p |
    " chain " + $direction + "_" + .key + " {\n" +
    (if .value.mode == "research" then "  accept\n" else
      ([.value.allow[] |
        "  " + .family + (if $direction == "out" then " daddr " else " saddr " end) + .address + " " +
        .protocol + (if $direction == "out" then " dport " else " sport " end) + (.port|tostring) + " accept\n"] | join("")) end) +
    "  drop\n }";
def dispatch($direction):
    " chain " + $direction + "_dispatch {\n" +
    ([.policies | keys[] | "  " + classifier(2; "mailagent.slice/mailagent-" + . + ".slice") +
      " goto " + $direction + "_" + . + "\n"] | join("")) + "  drop\n }";
"table inet mail_agent {\n" +
([rules("out"), rules("in"), dispatch("out"), dispatch("in")] | join("\n")) +
"\n chain output { type filter hook output priority 0; policy accept;\n  " +
classifier(1; "mailagent.slice") + " jump out_dispatch\n }\n" +
" chain input { type filter hook input priority 0; policy accept;\n  " +
classifier(1; "mailagent.slice") + " jump in_dispatch\n }\n}\n"
