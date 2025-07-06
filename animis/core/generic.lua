require("/animis/utils/config.lua");

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

    config = animis_config.loadConfig()

    data = animis_config.loadData(player.uniqueId())

    if not config or not data then
        sb.logInfo("\n--------------- [ANIMIS] ---------------\nNo config or datafile found!\nPlease check if you have set up Animis for this player.\nAnimis shutting down\n")
        _init()
        return
    end

    for _, layer in pairs(data) do
        layer.state = ""
        layer.oneTime = false
        layer.timer = {}
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

    for layerName, layer in pairs(data) do
        if layer.enabled then

            if layer.state:sub(1, 6) == "switch" then
                newState = layer.state -- continue
            end

            if layer.state == "random" then
                if math.floor(layer.timer) < #layer[layer.state] then
                    newState = layer.state
                end
            end

            if input.bindDown("animis", "switch1") and layer.switch1 then
                if layer.state ~= "switch1" then
                    newState = "switch1"
                else
                    newState = currentState
                end
            elseif input.bindDown("animis", "switch2") and layer.switch2 then
                if layer.state ~= "switch2" then
                    newState = "switch2"
                else
                    newState = currentState
                end
            elseif input.bind("animis", "loop1") and layer.loop1 then
                newState = "loop1"
            elseif input.bind("animis", "loop2") and layer.loop2 then
                newState = "loop2"
            elseif input.bind("animis", "once1") and layer.once1 then
                newState = "once1"
            elseif input.bind("animis", "once2") and layer.once2 then
                newState = "once2"
            elseif input.bind("animis", "looponce1") and layer.looponce1 then
                newState = "looponce1"
            elseif input.bind("animis", "looponce2") and layer.looponce2 then
                newState = "looponce2"
            elseif layer.state ~= "random" and layer.state:sub(1, 6) ~= "switch" then
                newState = currentState -- Preserve original state in case of missing frames
            end

            if layer.state ~= newState then
                idleNum = tonumber(player.personality().idle:match("idle.(%d+)"))
                layer.timer = 1
                layer.oneTime = false
                layer.state = newState

            end

            if layer.oneTime == false then

                if layer[layer.state] then
                    layer.timer = math.min(config.MAX_FRAMES, layer.timer + dt * layer.speed)

                    if layer.state == "crouch" and layer.oneTime == false or layer.state == "swimIdle" and layer.oneTime ==
                        false or layer.state == "lounge" and layer.oneTime == false or layer.state:sub(1, 4) == "once" then
                        if layer.state == "crouch" and not layer.crouchIdleLoop or layer.state == "swimIdle" and
                            not layer.swimIdleLoop or layer.state == "lounge" and not layer.loungeIdleLoop then
                            layer.oneTime = true
                            layer.timer = 1
                        else
                            if math.floor(layer.timer) > #layer[layer.state] then
                                layer.timer = 1
                            end
                        end
                    elseif layer.state == "idle" and layer.oneTime == false then
                        if not layer.idleLoop then
                            layer.oneTime = true
                            layer.timer = idleNum
                        else
                            if math.floor(layer.timer) > #layer[layer.state] then
                                layer.timer = 1
                            end
                        end
                    elseif layer.state == "jump" or layer.state == "fall" or layer.state:sub(1, 8) == "looponce" or
                        layer.state:sub(1, 6) == "switch" then
                        if math.floor(layer.timer) > #layer[layer.state] then
                            layer.timer = #layer[layer.state]
                        end
                    elseif layer.state == "walk" or layer.state == "run" or layer.state == "swim" or
                        layer.state:sub(1, 4) == "loop" then
                        if math.floor(layer.timer) > #layer[layer.state] then
                            layer.timer = 1
                        end
                    end

                    -- Apply animation directive
                    directiveFuncs[layerName](layer[layer.state][math.floor(layer.timer)])
                end
            end

            if math.random(1, layer.maxRandomValue) <= layer.maxRandomTrigger and layer.random and layer.state ~=
                "random" and layer.state:sub(1, 4) ~= "loop" and layer.state:sub(1, 4) ~= "once" and
                layer.state:sub(1, 6) ~= "switch" then
                layer.state = "random"
                layer.timer = 1
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
