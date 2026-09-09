# Extract values for mail-agent-usage. Each output line is TSV; jq escapes
# embedded tabs, newlines, carriage returns, and backslashes.
#
# Inputs: $result and $transcript from --slurpfile; $since; and the session
# ledger values $session_present, $session_turns, and $session_cost.

def tool_calls($records; $start):
    reduce ($records[]
        | select(.type == "assistant"
            and ((.timestamp == null) or .timestamp >= $start))
        | .message.content[]?
        | select(.type == "tool_use")
        | .name) as $name
        ({}; .[$name] = ((.[$name] // 0) + 1))
    | to_entries
    | sort_by(-.value)
    | map("\(.key) \(.value)")
    | join(", ");

(if ($result | length) != 1 or ($result[0] | type) != "object" then
     error("result must contain one JSON object")
 else
     $result[0]
 end) as $turn
| ($turn.modelUsage // {} | to_entries) as $models
| tool_calls($transcript; $since) as $calls
| (["turn", $turn.total_cost_usd] | @tsv),
    ($models[]
        | .key as $name
        | .value as $model
        | [
            "model",
            $model.canonicalModel // $name,
            $model.inputTokens // 0,
            $model.outputTokens // 0,
            $model.thinkingTokens // 0,
            $model.cacheReadInputTokens // 0,
            $model.cacheCreationInputTokens // 0,
            $model.costUSD // 0
        ] | @tsv),
    (["models_end", ($models | length)] | @tsv),
    ([
        "session",
        $session_present,
        $session_turns,
        $session_cost,
        $turn.total_cost_usd
    ] | @tsv),
    (["seconds", "wall clock", $turn.duration_ms // 0] | @tsv),
    (["seconds", "api time", $turn.duration_api_ms // 0] | @tsv),
    (["count", "assistant turns", $turn.num_turns // 0] | @tsv),
    (["text", "tool calls", if $calls == "" then "none" else $calls end]
        | @tsv),
    ([
        "subagents",
        $turn.subagent_stats.spawned // 0,
        $turn.subagent_stats.completed // 0
    ] | @tsv),
    (["count", "permission denials", ($turn.permission_denials // [] | length)]
        | @tsv),
    (["text", "session", $turn.session_id // ""] | @tsv)
