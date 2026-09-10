{nftables:[.nftables[] | select(has("metainfo") | not) |
    walk(if type == "object" then del(.handle) else . end)]}
