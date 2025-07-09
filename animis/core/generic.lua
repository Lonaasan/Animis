require("/animis/utils/config.lua");
require("/animis/utils/client.lua");

local _init = init or function()
end;
local _update = update or function()
end;
local _uninit = uninit or function()
end;

local data = {}
local config = {}
local idleNum = 1

local directiveFuncs = {}
local typeFuncs = {}
local groupFuncs = {}

function init()

    local client = animis_client.getClient()

    if client ~= "OpenStarbound" and client ~= "XStarbound" then
        sb.logInfo("\n--------------- [ANIMIS] ---------------\nAnimis is not supported.\n" ..
                       "Please use OpenStarbound or one of its derivatives.\nAnimis shutting down\n")
        _init()
        return
    end

    config = animis_config.loadConfig()

    data = animis_config.loadData(player.uniqueId())

    if not config or not data then
        sb.logInfo("\n--------------- [ANIMIS] ---------------\nNo config or datafile found!\n" ..
                       "Please check if you have set up Animis for this player.\nAnimis shutting down\n")
        _init()
        return
    end

    for _, layer in pairs(data) do
        layer.state = ""
        layer.previousState = ""
        layer.overwrittenState = ""
        layer.oneTime = false
        layer.time = 0
        layer.previousTime = 0
        layer.maxFrames = layer.maxFrames or config.MAX_FRAMES
        layer.speed = layer.speed or config.ANIMATION_SPEED
        layer.maxRandomValue = layer.maxRandomValue or config.MAX_RAND_VALUE
        layer.maxRandomTrigger = layer.maxRandomTrigger or config.MAX_RAND_TRIGGER
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

    for layerName, layer in pairs(data) do
        if groupFuncs[layerName] then
            groupFuncs[layerName](layer.group)
        end
        if typeFuncs[layerName] then
            typeFuncs[layerName](layer.type)
        end
    end

    _init()
end

function update(dt)
    if not config or not data then
        _update(dt)
        return
    end

    local currentState = player.currentState()
    local newState = currentState

    -- Input bindings
    local switch1Down = input.bindDown("animis", "switch1")
    local switch2Down = input.bindDown("animis", "switch2")
    local loop1Active = input.bind("animis", "loop1")
    local loop2Active = input.bind("animis", "loop2")
    local once1Active = input.bind("animis", "once1")
    local once2Active = input.bind("animis", "once2")
    local looponce1Active = input.bind("animis", "looponce1")
    local looponce2Active = input.bind("animis", "looponce2")

    for layerName, layer in pairs(data) do
        if layer.enabled then

            if layer.state:sub(1, 6) == "switch" then
                newState = layer.state -- continue
            end

            if layer.state == "random" and layer.overwrittenState == newState then
                if math.floor(layer.time) < #layer[layer.state] then
                    newState = layer.state
                end
            end

            if (layer.state == "afterJump" or layer.state == "afterFall") and layer.overwrittenState == newState then
                newState = layer.state
            end

            if switch1Down and layer.switch1 then
                if layer.state ~= "switch1" then
                    newState = "switch1"
                else
                    newState = currentState
                end
            elseif switch2Down and layer.switch2 then
                if layer.state ~= "switch2" then
                    newState = "switch2"
                else
                    newState = currentState
                end
            elseif loop1Active and layer.loop1 then
                newState = "loop1"
            elseif loop2Active and layer.loop2 then
                newState = "loop2"
            elseif once1Active and layer.once1 then
                newState = "once1"
            elseif once2Active and layer.once2 then
                newState = "once2"
            elseif looponce1Active and layer.looponce1 then
                newState = "looponce1"
            elseif looponce2Active and layer.looponce2 then
                newState = "looponce2"
            elseif layer.state ~= "random" and layer.state:sub(1, 6) ~= "switch" and layer.state:sub(1, 5) ~= "after" then
                newState = currentState -- Preserve original state in case of missing frames
            end

            if layer.state ~= newState then
                idleNum = tonumber(player.personality().idle:match("idle.(%d+)")) or 1
                layer.time = 1
                layer.oneTime = false
                layer.state = newState
            end

            local statePrefix4 = layer.state:sub(1, 4)
            local statePrefix6 = layer.state:sub(1, 6)
            local statePrefix8 = layer.state:sub(1, 8)

            if layer.oneTime == false then

                if layer[layer.state] then
                    layer.time = math.min(layer.maxFrames, layer.time + dt * layer.speed)

                    if layer.state == "crouch" and layer.oneTime == false or layer.state == "swimIdle" and layer.oneTime ==
                        false or layer.state == "lounge" and layer.oneTime == false or statePrefix4 == "once" then
                        if layer.state == "crouch" and not layer.crouchIdleLoop or layer.state == "swimIdle" and
                            not layer.swimIdleLoop or layer.state == "lounge" and not layer.loungeIdleLoop then
                            layer.oneTime = true
                            layer.time = 1
                        else
                            if math.floor(layer.time) > #layer[layer.state] then
                                layer.time = 1
                            end
                        end
                    elseif layer.state == "idle" and layer.oneTime == false then
                        if not layer.idleLoop then
                            layer.oneTime = true
                            layer.time = idleNum
                        else
                            if math.floor(layer.time) > #layer[layer.state] then
                                layer.time = 1
                            end
                        end
                    elseif layer.state == "jump" or layer.state == "fall" or statePrefix8 == "looponce" or statePrefix6 ==
                        "switch" then
                        if math.floor(layer.time) > #layer[layer.state] then
                            if layer.state == "jump" and layer.afterJump then
                                layer.overwrittenState = layer.state
                                layer.state = "afterJump"
                                layer.time = 1
                                layer.oneTime = false
                            elseif layer.state == "fall" and layer.afterFall then
                                layer.overwrittenState = layer.state
                                layer.state = "afterFall"
                                layer.time = 1
                                layer.oneTime = false
                            else
                                layer.time = #layer[layer.state]
                            end
                        end
                    elseif layer.state == "walk" or layer.state == "run" or layer.state == "swim" or layer.state ==
                        "afterJump" or layer.state == "afterFall" or statePrefix4 == "loop" then
                        if math.floor(layer.time) > #layer[layer.state] then
                            layer.time = 1
                        end
                    end

                    -- Apply animation directive only when frame changes or the state changed
                    local roundedTime = math.floor(layer.time)
                    if roundedTime ~= layer.previousTime or layer.state ~= layer.previousState then
                        directiveFuncs[layerName](layer[layer.state][roundedTime])
                        layer.previousState = layer.state
                        layer.previousTime = roundedTime
                    end
                end
            end

            if layer.random and layer.state ~= "random" and statePrefix4 ~= "loop" and statePrefix4 ~= "once" and
                statePrefix6 ~= "switch" and math.random(1, layer.maxRandomValue) <= layer.maxRandomTrigger then
                layer.overwrittenState = layer.state
                layer.state = "random"
                layer.time = 1
                layer.oneTime = false
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
