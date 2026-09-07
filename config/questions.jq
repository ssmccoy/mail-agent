# Render AskUserQuestion tool calls as a mail-answerable Questions section.
# The tool is interactive and reaches no one in a mail turn, so its
# questions are pulled from the event stream and mailed instead.
#
# Input: the stream-json event stream (slurped); output: GitHub markdown.

[ .[]
  | select(.type == "assistant")
  | .message.content[]?
  | select(.type == "tool_use" and .name == "AskUserQuestion")
  | .input.questions[] ] as $questions

| "## Questions",
  "",
  "Reply with each number and your choice.",
  "",
  ( $questions
    | to_entries[]
    | "### \(.key + 1). \(.value.question)",
      ( if .value.multiSelect then "_Choose any that apply._"
        else "_Choose one._" end ),
      "",
      ( .value.options[] | "- **\(.label)** — \(.description)" ),
      "" )
