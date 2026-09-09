# Convert Codex events to the result interface consumed by mail-agent-usage.
# Standard rates per million tokens, reviewed 2026-09-08:
# https://developers.openai.com/api/docs/models/compare
# https://developers.openai.com/api/docs/models/gpt-5.5
# https://developers.openai.com/api/docs/models/gpt-5.4-mini

def canonical_model($model):
    if $model == "" or $model == "-" or $model == "gpt-5.6" then
        "gpt-5.6-sol"
    else
        $model
    end;

def validate_usage($usage):
    if ([$usage.input_tokens, $usage.cached_input_tokens,
            $usage.output_tokens, $usage.reasoning_output_tokens]
        | all(type == "number" and . >= 0))
        and $usage.cached_input_tokens <= $usage.input_tokens then
        $usage
    else
        error("invalid Codex token usage")
    end;

def prices($model):
    if $model | test("^gpt-6-astra(-[0-9]{4}-[0-9]{2}-[0-9]{2})?$") then
        {input: 10, cached: 1, output: 50}
    elif $model | test("^gpt-5\\.6-sol(-[0-9]{4}-[0-9]{2}-[0-9]{2})?$") then
        {input: 4, cached: 0.4, output: 20}
    elif $model | test("^gpt-5\\.6-terra(-[0-9]{4}-[0-9]{2}-[0-9]{2})?$") then
        {input: 2, cached: 0.2, output: 12}
    elif $model | test("^gpt-5\\.6-luna(-[0-9]{4}-[0-9]{2}-[0-9]{2})?$") then
        {input: 0.2, cached: 0.02, output: 1.2}
    elif $model | test("^gpt-5\\.5(-[0-9]{4}-[0-9]{2}-[0-9]{2})?$") then
        {input: 5, cached: 0.5, output: 30}
    elif $model | test("^gpt-5\\.4-mini(-[0-9]{4}-[0-9]{2}-[0-9]{2})?$") then
        {input: 0.75, cached: 0.075, output: 4.5}
    else
        error("no Codex price configured for \($model)")
    end;

def estimate_cost($model; $usage):
    prices($model) as $prices
    | (($usage.input_tokens - $usage.cached_input_tokens) * $prices.input
        + $usage.cached_input_tokens * $prices.cached
        + $usage.output_tokens * $prices.output) / 1000000;

canonical_model($model) as $model
| (map(select(.type == "turn.completed")) | last.usage
    | validate_usage(.)) as $usage
| estimate_cost($model; $usage) as $cost
| {
    session_id: (map(select(.type == "thread.started")) | last.thread_id),
    total_cost_usd: $cost,
    duration_ms: 0,
    duration_api_ms: 0,
    num_turns: (map(select(
        .type == "item.completed" and .item.type == "agent_message"
    )) | length),
    modelUsage: {
        ($model): {
            canonicalModel: $model,
            inputTokens: ($usage.input_tokens - $usage.cached_input_tokens),
            outputTokens: $usage.output_tokens,
            thinkingTokens: $usage.reasoning_output_tokens,
            cacheReadInputTokens: $usage.cached_input_tokens,
            cacheCreationInputTokens: 0,
            costUSD: $cost
        }
    }
}
