require("/animis/utils/config.lua");

local _init = init or function()
end;
local _update = update or function()
end;
local _uninit = uninit or function()
end;

local onetime = false
local timers = {}
local state = ""
local data = {}
local config = {}
local idleNum = 1

local directiveFuncs = {}
local typeFuncs = {}
local groupFuncs = {}

function init()

    config = animis_config.loadConfig()

    data = animis_config.loadData(player.uniqueId())

    if not config or not data then
        _init()
        return
    end

    directiveFuncs = {
        body = player.setBodyDirectives,
        emote = player.setEmoteDirectives,
        hair = player.setHairDirectives,
        facial_hair = player.setFacialHairDirectives,
        facial_mask = player.setFacialMaskDirectives
    }

    typeFuncs = {
        hair = player.setHairType,
        facial_hair = player.setFacialHairType,
        facial_mask = player.setFacialMaskType
    }

    groupFuncs = {
        hair = player.setHairGroup,
        facial_hair = player.setFacialHairGroup,
        facial_mask = player.setFacialMaskGroup
    }

    for key, value in pairs(data) do
        if groupFuncs[key] then
            groupFuncs[key](value.group)
        end
        if typeFuncs[key] then
            typeFuncs[key](value.type)
        end
    end

    _init()
end

function update(dt)
    if not config or not data then
        _update(dt)
        return
    end

    local newState = player.currentState()

    if input.bind("animis", "loop1") then
        newState = "loop1"
    elseif input.bind("animis", "loop2") then
        newState = "loop2"
    elseif input.bind("animis", "once1") then
        newState = "once1"
    elseif input.bind("animis", "once2") then
        newState = "once2"
    elseif input.bind("animis", "looponce1") then
        newState = "looponce1"
    elseif input.bind("animis", "looponce2") then
        newState = "looponce2"
    end

    if state ~= newState then
        idleNum = tonumber(player.personality().idle:match("idle.(%d+)"))
        onetime = false
        for key, value in pairs(data) do
            if value.enabled then
                timers[key] = 1
            end
        end
        state = newState
    end

    if onetime == true then
        _update(dt)
        return
    end

    for key, value in pairs(data) do
        if value.enabled and value[state] then

            if value.speed then
                timers[key] = math.min(config.MAX_FRAMES, timers[key] + dt * value.speed)
            else
                timers[key] = math.min(config.MAX_FRAMES, timers[key] + dt * config.DEFAULT_ANIMATION_SPEED)
            end

            if state == "crouch" and onetime == false or state == "swimIdle" and onetime == false or state:sub(1, 4) ==
                "once" then
                if state == "crouch" and not value.crouchIdleLoop or state == "swimIdle" and not value.swimIdleLoop then
                    onetime = true
                    timers[key] = 1
                else
                    if math.floor(timers[key]) > #value[state] then
                        timers[key] = 1
                    end
                end
            elseif state == "idle" and onetime == false then
                if not value.idleLoop then
                    onetime = true
                    timers[key] = idleNum
                else
                    if math.floor(timers[key]) > #value[state] then
                        timers[key] = 1
                    end
                end
            elseif state == "jump" or state == "fall" or state:sub(1, 8) == "looponce" then
                if math.floor(timers[key]) > #value[state] then
                    timers[key] = #value[state]
                end
            elseif state == "walk" or state == "run" or state == "swim" or state:sub(1, 4) == "loop" then
                if math.floor(timers[key]) > #value[state] then
                    timers[key] = 1
                end
            end
            directiveFuncs[key](value[state][math.floor(timers[key])])
        end
    end

    _update(dt)
end

function uninit()
    if not config or not data then
        _uninit()
        return
    end

    _uninit()
end
