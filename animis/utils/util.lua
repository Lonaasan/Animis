function getKeys(table)
    local keyset = {}
    local n = 0

    for k, v in pairs(table) do
        n = n + 1
        keyset[n] = k
    end
    return keyset
end

function getValues(table)
    local keyset = {}
    local n = 0

    for k, v in pairs(table) do
        n = n + 1
        keyset[n] = v
    end
    return keyset
end
