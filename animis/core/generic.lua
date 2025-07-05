require("/animis/utils/config.lua");

local _init = init or function()
end;
local _update = update or function()
end;
local _uninit = uninit or function()
end;

-- Layer variables

local layerStates = {}
local layerOneTimes = {}
local layerTimers = {}
local layerConfig = {}

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

    for key, value in pairs(data) do
        layerStates[key] = ""
        layerOneTimes[key] = false
        layerTimers[key] = {}
        layerConfig[key] = {
            speed = value.speed or config.ANIMATION_SPEED,
            maxRandomValue = value.maxRandomValue or config.MAX_RAND_VALUE,
            maxRandomTrigger = value.maxRandomTrigger or config.MAX_RAND_TRIGGER
        }
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

    local originalState = player.currentState()
    local newState = originalState

    for key, value in pairs(data) do
        if value.enabled then

            if layerStates[key]:sub(1, 6) == "switch" then
                newState = layerStates[key] -- continue
            end

            if layerStates[key] == "random" then
                if math.floor(layerTimers[key]) < #value[layerStates[key]] then
                    newState = layerStates[key]
                end
            end

            if input.bindDown("animis", "switch1") and value.switch1 then
                if layerStates[key] ~= "switch1" then
                    newState = "switch1"
                else
                    newState = originalState
                end
            elseif input.bindDown("animis", "switch2") and value.switch2 then
                if layerStates[key] ~= "switch2" then
                    newState = "switch2"
                else
                    newState = originalState
                end
            elseif input.bind("animis", "loop1") and value.loop1 then
                newState = "loop1"
            elseif input.bind("animis", "loop2") and value.loop2 then
                newState = "loop2"
            elseif input.bind("animis", "once1") and value.once1 then
                newState = "once1"
            elseif input.bind("animis", "once2") and value.once2 then
                newState = "once2"
            elseif input.bind("animis", "looponce1") and value.looponce1 then
                newState = "looponce1"
            elseif input.bind("animis", "looponce2") and value.looponce2 then
                newState = "looponce2"
            elseif layerStates[key] ~= "random" and layerStates[key]:sub(1, 6) ~= "switch" then
                newState = originalState -- Preserve original state in case of missing frames
            end

            if layerStates[key] ~= newState then
                idleNum = tonumber(player.personality().idle:match("idle.(%d+)"))
                layerTimers[key] = 1
                layerOneTimes[key] = false
                layerStates[key] = newState

            end

            if layerOneTimes[key] == false then

                if value[layerStates[key]] then
                    layerTimers[key] = math.min(config.MAX_FRAMES, layerTimers[key] + dt * layerConfig[key].speed)

                    if layerStates[key] == "crouch" and layerOneTimes[key] == false or layerStates[key] == "swimIdle" and
                        layerOneTimes[key] == false or layerStates[key] == "lounge" and layerOneTimes[key] == false or
                        layerStates[key]:sub(1, 4) == "once" then
                        if layerStates[key] == "crouch" and not value.crouchIdleLoop or layerStates[key] == "swimIdle" and
                            not value.swimIdleLoop or layerStates[key] == "lounge" and not value.loungeIdleLoop then
                            layerOneTimes[key] = true
                            layerTimers[key] = 1
                        else
                            if math.floor(layerTimers[key]) > #value[layerStates[key]] then
                                layerTimers[key] = 1
                            end
                        end
                    elseif layerStates[key] == "idle" and layerOneTimes[key] == false then
                        if not value.idleLoop then
                            layerOneTimes[key] = true
                            layerTimers[key] = idleNum
                        else
                            if math.floor(layerTimers[key]) > #value[layerStates[key]] then
                                layerTimers[key] = 1
                            end
                        end
                    elseif layerStates[key] == "jump" or layerStates[key] == "fall" or layerStates[key]:sub(1, 8) ==
                        "looponce" or layerStates[key]:sub(1, 6) == "switch" then
                        if math.floor(layerTimers[key]) > #value[layerStates[key]] then
                            layerTimers[key] = #value[layerStates[key]]
                        end
                    elseif layerStates[key] == "walk" or layerStates[key] == "run" or layerStates[key] == "swim" or
                        layerStates[key]:sub(1, 4) == "loop" then
                        if math.floor(layerTimers[key]) > #value[layerStates[key]] then
                            layerTimers[key] = 1
                        end
                    end

                    -- Apply animation directive
                    directiveFuncs[key](value[layerStates[key]][math.floor(layerTimers[key])])
                end
            end

            if math.random(1, layerConfig[key].maxRandomValue) <= layerConfig[key].maxRandomTrigger and value.random and
                layerStates[key] ~= "random" and layerStates[key]:sub(1, 4) ~= "loop" and layerStates[key]:sub(1, 4) ~=
                "once" and layerStates[key]:sub(1, 6) ~= "switch" then
                layerStates[key] = "random"
                layerTimers[key] = 1
                layerOneTimes[key] = false
            end
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
