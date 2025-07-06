---animis config utilities
---Author: Lonaasan
string.animis = string.animis or {};
string.animis.config = string.animis.config or {};

animis_config = {}

---Load Animis config
---@return table
function animis_config.loadConfig()
    local config = root.assetJson("/animis/config.json")
    if not config or #config == 0 then return false end
    return config
end

---Load Animis player data
---@param playerId uuid
---@return table
function animis_config.loadData(playerId)

    local playerPath = "/animis/" .. playerId .. "/"

    local playerConfig = root.assetJson("/animis/playerconfig.json")

    if not playerConfig or #playerConfig == 0 or not playerConfig[playerId] then return false end

    local data = {}

    for key, value in pairs(playerConfig[playerId]) do
        local frames = root.assetJson(playerPath .. key ..".json")

        if not frames then return false end

        for k, v in pairs(frames) do
            value[k] = v
        end

        data[key] = value
    end

    return data
end

--- Export the functions for 3rd parties to use without the possibility of changing the original code
string.animis.config = animis_config;