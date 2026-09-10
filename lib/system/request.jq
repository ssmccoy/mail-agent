def identifier: type == "string" and test("^[A-Za-z0-9_-]{1,128}$");
select(keys == ["action","agent_session","base","branch","driver","effort","mode","model","request","schema","task"] and
    .schema == 1 and (.request | identifier) and (.task | identifier) and
    (.action | IN("prepare","branch","turn","history","inspect","import","snapshot")) and
    (.driver | IN("claude","codex","pi")) and
    (.mode | IN("investigate","plan","execute","research")) and
    (.model | type == "string" and (. == "" or . == "-" or test("^[A-Za-z0-9_][A-Za-z0-9_./:-]{0,127}$"))) and
    (.effort | IN("","low","medium","high","xhigh","max")) and
    (.branch | type == "string" and length <= 256 and (explode | all(.[]; . >= 32 and . != 127))) and
    (.base | . == "" or . == "-" or (type == "string" and test("^([0-9a-f]{40}|[0-9a-f]{64})$"))) and
    (.agent_session | . == "" or identifier))
