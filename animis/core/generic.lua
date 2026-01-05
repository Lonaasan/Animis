-- Animis V2 Animation System
-- Priority-based system: input triggers > random > state-based
-- Supports chaining, interrupt/resume, and various trigger modes

require("/animis/utils/config.lua")
require("/animis/utils/client.lua")

-- Priority levels
local PRIORITY_INPUT = 3      -- input triggers (highest)
local PRIORITY_RANDOM = 2     -- random animations
local PRIORITY_STATE = 1      -- state-based (lowest)

-- state
local data = {}
local config = {}
local idleNum = 1
local directiveFuncs = {}
local typeFuncs = {}
local groupFuncs = {}
local animationLookup = {}

---apply defaults to animation
---@param anim table
---@return table
local function applyDefaults(anim)
    if anim.loop == nil then
        anim.loop = false
        if anim.states then
            for _, s in ipairs(anim.states) do
                if s == "walk" or s == "run" or s == "swim" then
                    anim.loop = true
                    break
                end
            end
        end
    end

    anim.speed = anim.speed or config.ANIMATION_SPEED or 10
    anim.maxFrames = anim.maxFrames or (#(anim.frames or {}))

    if anim.triggers then
        for _, t in ipairs(anim.triggers) do
            if t.type == "random" then
                t.chance = t.chance or 0.01
                t.checkInterval = t.checkInterval or 1.0
                t.cooldown = t.cooldown or 0
                anim.interruptible = (anim.interruptible == nil) and true or anim.interruptible
                if anim.duration == nil and anim.loop then
                    anim.duration = 5.0
                end
            end
        end
    end

    anim.persist = (anim.persist == nil) and false or anim.persist
    anim.interruptible = (anim.interruptible == nil) and false or anim.interruptible

    -- If no states and no triggers, assume it's a simple looping default (body etc.)
    -- Only apply if loop is not explicitly set
    if anim.loop == nil and (not anim.states or #anim.states == 0) and (not anim.triggers or #anim.triggers == 0) then
        anim.loop = true
    end

    return anim
end

---validate animation (check frames exist, fix incompatible settings)
---@param name string
---@param anim table
---@return boolean
local function validateAnimation(name, anim)
    if not anim.frames or #anim.frames == 0 then
        return false
    end
    -- chainTo with random triggers is weird, just remove it
    if anim.chainTo and anim.triggers then
        for _, t in ipairs(anim.triggers) do
            if t.type == "random" then
                anim.chainTo = nil
                break
            end
        end
    end
    return true
end

---build lookup tables for faster queries (byState, byInput, randoms, defaults)
---@param animations table
---@return table
local function buildLookups(animations)
    local byState, byInput, randoms, defaults = {}, {}, {}, {}
    for name, anim in pairs(animations) do
        -- skip internal animations (only used in chains)
        if not anim.internal then
            if anim.states and #anim.states > 0 then
                for _, s in ipairs(anim.states) do
                    byState[s] = byState[s] or {}
                    table.insert(byState[s], {
                        name = name,
                        data = anim
                    })
                end
            else
                table.insert(defaults, {
                    name = name,
                    data = anim
                })
            end

            if anim.triggers then
                for _, t in ipairs(anim.triggers) do
                    if t.type == "input" then
                        byInput[t.bind] = byInput[t.bind] or {}
                        table.insert(byInput[t.bind], {
                            name = name,
                            data = anim
                        })
                    elseif t.type == "random" then
                        table.insert(randoms, {
                            name = name,
                            data = anim,
                            trigger = t
                        })
                    end
                end
            end
        end
    end
    return {
        byState = byState,
        byInput = byInput,
        randoms = randoms,
        defaults = defaults
    }
end

---check if input trigger is currently active
---@param trigger table
---@return boolean
local function isInputActive(trigger)
    if trigger.mode == "toggle" or trigger.mode == "switch" then
        return input.bindDown("animis", trigger.bind)
    elseif trigger.mode == "hold" then
        return input.bind("animis", trigger.bind)
    else
        return input.bindDown("animis", trigger.bind)
    end
end

---check if random animation should trigger (chance + interval + cooldown)
---@param name string
---@param trigger table
---@param layer table
---@param now number
---@return boolean
local function shouldTriggerRandom(name, trigger, layer, now)
    layer.randomCooldowns = layer.randomCooldowns or {}
    layer.randomChecks = layer.randomChecks or {}
    
    -- check cooldown
    local lastTrigger = layer.randomCooldowns[name] or 0
    local cooldown = trigger.cooldown or 0
    if now - lastTrigger < cooldown then
        return false
    end
    
    -- check interval and roll
    local lastCheck = layer.randomChecks[name] or 0
    if now - lastCheck >= (trigger.checkInterval or 1.0) then
        layer.randomChecks[name] = now
        if math.random() < (trigger.chance or 0.01) then
            layer.randomCooldowns[name] = now
            return true
        end
    end
    return false
end

---apply prefix/suffix from os table if set
---@param directive string
---@return string
local function applyDirectiveModifiers(directive)
    local result = directive
    local prefix = player.getProperty("animisPrefix", "")
    if prefix ~= "" then
        result = prefix .. result
    end
    local suffix = player.getProperty("animisSuffix", "")
    if suffix ~= "" then
        result = result .. suffix
    end
    return result
end

---check if prefix/suffix changed since last application
---@param layer table
---@return boolean
local function hasModifiersChanged(layer)
    local currentPrefix = player.getProperty("animisPrefix", "")
    local currentSuffix = player.getProperty("animisSuffix", "")
    local previousPrefix = layer.previousPrefix or ""
    local previousSuffix = layer.previousSuffix or ""
    return currentPrefix ~= previousPrefix or currentSuffix ~= previousSuffix
end

---update stored prefix/suffix values
---@param layer table
local function updateModifiersTracking(layer)
    layer.previousPrefix = player.getProperty("animisPrefix", "")
    layer.previousSuffix = player.getProperty("animisSuffix", "")
end

---start playing animation (handles interrupt/resume setup)
---@param dt number
---@param layer table
---@param name string
---@param anim table
---@param layerName string
---@param state string
---@param priority number
local function playAnimation(dt, layer, name, anim, layerName, state, priority)
    if layer.currentAnimName ~= name then
        -- save current input animation for resume later
        local hasInputTrigger = false
        if anim.triggers then
            for _, t in ipairs(anim.triggers) do
                if t.type == "input" then
                    hasInputTrigger = true
                    break
                end
            end
        end
        if hasInputTrigger and layer.triggerBind and layer.currentAnimName then
            -- save so we can return to it
            layer.interruptedAnim = layer.currentAnimName
            layer.interruptedBind = layer.triggerBind
        end

        layer.currentAnimName = name
        layer.currentAnimData = anim
        layer.startState = player.currentState()
        layer.animStartTime = os.time()
        layer.animPriority = anim.priority or priority or 2
        layer.time = 1
        layer.previousTime = 0
        layer.animationFinished = false  -- Flag for non-looping animation completion
        -- store trigger info for chains
        if anim.triggers then
            for _, t in ipairs(anim.triggers) do
                if t.type == "input" then
                    layer.triggerBind = t.bind
                    layer.triggerMode = t.mode  -- Store mode (toggle/hold/down) for chained animations
                    break
                end
            end
        end
        -- clear trigger stuff for non-input animations
        -- chain animations keep their parent trigger
        if not hasInputTrigger and not anim.internal then
            -- state-based always overrides
            layer.triggerBind = nil
            layer.triggerMode = nil
            layer.interruptedAnim = nil
            layer.interruptedBind = nil
        end
        -- idle variants (idle.1, idle.2, etc)
        if not anim.loop and anim.states and state then
            for _, s in ipairs(anim.states) do
                if s == state and state == "idle" then
                    layer.time = idleNum
                    layer.animationFinished = true
                    break
                end
            end
        end
    end
    if config.DEBUG then
        sb.logInfo("[Animis] playAnimation: " .. layerName .. " -> " .. tostring(name) .. " loop=" ..
                       tostring(anim.loop) .. " state=" .. tostring(state) .. " priority=" ..
                       tostring(layer.animPriority))
    end
    
    -- advance time
    if not layer.animationFinished then
        layer.time = layer.time + dt * anim.speed
        if anim.loop then
            if math.floor(layer.time) > #anim.frames then
                layer.time = 1
            end
        else
            -- stop at last frame
            if math.floor(layer.time) > #anim.frames then
                layer.time = #anim.frames
                layer.animationFinished = true
            end
        end
    end
    
    -- apply frame if changed or if modifiers changed
    local rt = math.floor(layer.time)
    local modifiersChanged = hasModifiersChanged(layer)
    if (rt ~= layer.previousTime or modifiersChanged) and anim.frames[rt] then
        directiveFuncs[layerName](applyDirectiveModifiers(anim.frames[rt]))
        layer.previousTime = rt
        updateModifiersTracking(layer)
    end
end

---continue current animation, advance time and update frame
---@param dt number
---@param layer table
---@param layerName string
---@return boolean
local function continueAnimation(dt, layer, layerName)
    if not layer.currentAnimData then
        return false
    end
    local anim = layer.currentAnimData
    layer.time = layer.time + dt * anim.speed

    -- track if finished
    local finished = false
    if anim.loop then
        if math.floor(layer.time) > #anim.frames then
            layer.time = 1
        end
    else
        if math.floor(layer.time) > #anim.frames then
            layer.time = #anim.frames
            finished = true
        end
    end

    local rt = math.floor(layer.time)
    local modifiersChanged = hasModifiersChanged(layer)
    if (rt ~= layer.previousTime or modifiersChanged) and anim.frames[rt] then
        directiveFuncs[layerName](applyDirectiveModifiers(anim.frames[rt]))
        layer.previousTime = rt
        updateModifiersTracking(layer)
    end
    if config.DEBUG then
        sb.logInfo("[Animis] continueAnimation: " .. layerName .. " -> " .. tostring(layer.currentAnimName) .. " rt=" ..
                       tostring(rt) .. " loop=" .. tostring(anim.loop))
    end

    -- mark for chaining if finished
    if finished and anim.chainTo and layer.animations and layer.animations[anim.chainTo] then
        if config.DEBUG then
            sb.logInfo("[Animis] non-loop finished chainTo: " .. layerName .. " -> " .. tostring(anim.chainTo))
        end
        layer.animationFinished = true
    end

    -- always keep active
    -- input animations stay until released/toggled
    -- non-looping stays on last frame
    return true
end

local function updateLayer(dt, layer, layerName, state, now, lookup)
    layer.inputToggles = layer.inputToggles or {}
    layer.randomCooldowns = layer.randomCooldowns or {}
    layer.randomChecks = layer.randomChecks or {}

    -- SECTION 1: input triggers (priority 3)
    local deferToggleToSection2 = false  -- track if toggle continues in section 2
    for bind, list in pairs(lookup.byInput or {}) do
        for _, entry in ipairs(list) do
            local anim = entry.data
            if anim.triggers and anim.triggers[1] and anim.states and (#anim.states == 0 or not anim.states[1] or true) then
            end
            local allowed = true
            if anim.states and #anim.states > 0 then
                allowed = false;
                for _, s in ipairs(anim.states) do
                    if s == state then
                        allowed = true;
                        break
                    end
                end
            end
            if not allowed then
                goto continue_input
            end
            if config.DEBUG then
                sb.logInfo("[Animis] input candidate: " .. layerName .. " -> " .. entry.name .. " allowed=" ..
                               tostring(allowed))
            end
            for _, t in ipairs(anim.triggers or {}) do
                if t.type == "input" and t.bind == bind then
                    if t.mode == "toggle" or t.mode == "switch" then
                        if input.bindDown("animis", t.bind) then
                        -- defer to section 2 if already playing
                            if layer.currentAnimName == entry.name then
                                layer.inputToggles[t.bind] = not layer.inputToggles[t.bind]
                                deferToggleToSection2 = true
                                goto continue_input
                            end
                            layer.inputToggles[t.bind] = not layer.inputToggles[t.bind]
                        end
                        if layer.inputToggles[t.bind] then
                            if layer.currentAnimName ~= entry.name then
                                -- only start if no other input is active
                                local currentIsInputTriggered = layer.triggerBind ~= nil
                                if not currentIsInputTriggered then
                                    playAnimation(dt, layer, entry.name, anim, layerName, state, PRIORITY_INPUT)
                                    return
                                else
                                    -- different input active, defer
                                    deferToggleToSection2 = true
                                end
                            else
                                -- already playing, keep going
                                deferToggleToSection2 = true
                            end
                        end
                    elseif t.mode == "hold" then
                        if input.bind("animis", t.bind) or input.bindDown("animis", t.bind) then
                            -- check if part of same trigger chain
                            local isSameTrigger = (layer.triggerBind == t.bind)

                            -- don't restart if already playing or in chain
                            if layer.currentAnimName ~= entry.name and not isSameTrigger then
                                playAnimation(dt, layer, entry.name, anim, layerName, state, PRIORITY_INPUT)
                                return
                            end
                            -- section 2 handles continuation
                        end
                    else
                        -- down mode
                        if input.bindDown("animis", t.bind) then
                            playAnimation(dt, layer, entry.name, anim, layerName, state, PRIORITY_INPUT)
                            return
                        end
                    end
                end
            end
            ::continue_input::
        end
    end

    -- defer to section 2 if needed
    -- (hold would have returned already)
    if deferToggleToSection2 then
        goto section2
    end

    ::section2::
    -- SECTION 2: current animation (continuation, chaining, state changes)
    if layer.currentAnimName and layer.currentAnimData then
        local anim = layer.currentAnimData
        local inheritedPriority = layer.animPriority or PRIORITY_STATE

        -- check if finished and needs chain
        if layer.animationFinished and anim.chainTo and layer.animations and layer.animations[anim.chainTo] then
            layer.animationFinished = false
            playAnimation(dt, layer, anim.chainTo, layer.animations[anim.chainTo], layerName, state, inheritedPriority)
            return
        end

        -- persist keeps running across state changes
        if anim.persist and state ~= layer.startState then
            continueAnimation(dt, layer, layerName);
            return
        end
        -- chain on state change
        if not anim.persist and state ~= layer.startState and anim.chainTo and layer.animations and
            layer.animations[anim.chainTo] then
            if config.DEBUG then
                sb.logInfo("[Animis] state-change chainTo firing: " .. layerName .. " from " ..
                               tostring(layer.currentAnimName) .. " to " .. tostring(anim.chainTo))
            end
            playAnimation(dt, layer, anim.chainTo, layer.animations[anim.chainTo], layerName, state, inheritedPriority)
            return
        end
        -- duration enforcement
        if anim.duration then
            local elapsed = now - (layer.animStartTime or 0)
            if config.DEBUG then
                sb.logInfo("[Animis] duration check: " .. layerName .. " -> " .. tostring(layer.currentAnimName) ..
                               " elapsed=" .. tostring(elapsed) .. " duration=" .. tostring(anim.duration))
            end
            if elapsed >= anim.duration then
                -- expired, chain if possible
                if anim.chainTo and layer.animations and layer.animations[anim.chainTo] then
                    if config.DEBUG then
                        sb.logInfo("[Animis] duration-expired chainTo: " .. layerName .. " -> " ..
                                       tostring(anim.chainTo))
                    end
                    playAnimation(dt, layer, anim.chainTo, layer.animations[anim.chainTo], layerName, state, inheritedPriority)
                    return
                end
                -- no chain, fallthrough
                if config.DEBUG then
                    sb.logInfo("[Animis] duration expired, allowing fallthrough: " .. layerName .. " -> " .. tostring(layer.currentAnimName))
                end
                -- fallthrough to section 3/4
                goto skipContinuation
            else
                -- not expired, keep going
                -- (persist blocks interrupts, duration enforces continuation)
                if config.DEBUG then
                    sb.logInfo("[Animis] duration enforcing continuation: " .. layerName .. " -> " .. tostring(layer.currentAnimName))
                end
                continueAnimation(dt, layer, layerName)
                return
            end
        end
        -- input chain (release/toggle off)
        -- check both anim triggers and stored trigger
        if anim.chainTo and (anim.triggers or layer.triggerBind) then
            -- use anim triggers if present, else stored
            local triggersToCheck = anim.triggers
            if not triggersToCheck and layer.triggerBind then
                -- chained anim, check stored trigger
                local shouldChain = false
                if layer.triggerMode == "toggle" or layer.triggerMode == "switch" then
                    -- chain when toggled off
                    if not layer.inputToggles[layer.triggerBind] then
                        shouldChain = true
                    end
                elseif layer.triggerMode == "hold" then
                    -- chain when released
                    if not input.bind("animis", layer.triggerBind) then
                        shouldChain = true
                    end
                end
                
                if shouldChain then
                    if layer.animations and layer.animations[anim.chainTo] then
                        if config.DEBUG then
                            sb.logInfo("[Animis] input-" .. tostring(layer.triggerMode) .. " released chainTo (stored): " .. layerName .. " -> " ..
                                           tostring(anim.chainTo))
                        end
                        playAnimation(dt, layer, anim.chainTo, layer.animations[anim.chainTo], layerName, state, inheritedPriority)
                        return
                    end
                elseif layer.triggerMode == "toggle" or layer.triggerMode == "switch" or (layer.triggerMode == "hold" and input.bind("animis", layer.triggerBind)) then
                    -- keep going if still on/held
                    continueAnimation(dt, layer, layerName)
                    return
                end
            elseif triggersToCheck then
                -- check current anim triggers
                for _, t in ipairs(triggersToCheck) do
                    if t.type == "input" then
                        if t.mode == "toggle" or t.mode == "switch" then
                            -- chain when toggled off
                            if not layer.inputToggles[t.bind] then
                                if layer.animations and layer.animations[anim.chainTo] then
                                    if config.DEBUG then
                                        sb.logInfo("[Animis] input-toggle chainTo: " .. layerName .. " -> " ..
                                                       tostring(anim.chainTo))
                                    end
                                    playAnimation(dt, layer, anim.chainTo, layer.animations[anim.chainTo], layerName,
                                        state, inheritedPriority)
                                    return
                                end
                            else
                                -- still on, keep going
                                continueAnimation(dt, layer, layerName)
                                return
                            end
                        elseif t.mode == "hold" then
                            if not input.bind("animis", t.bind) then
                                if layer.animations and layer.animations[anim.chainTo] then
                                    if config.DEBUG then
                                        sb.logInfo("[Animis] input-hold released chainTo: " .. layerName .. " -> " ..
                                                       tostring(anim.chainTo))
                                    end
                                    playAnimation(dt, layer, anim.chainTo, layer.animations[anim.chainTo], layerName,
                                        state, inheritedPriority)
                                    return
                                end
                            else
                                continueAnimation(dt, layer, layerName)
                                return
                            end
                        end
                    end
                end
            end
        end
        -- check if should continue
        if not layer.animationFinished then
            local stateMatches = true
            if anim.states and #anim.states > 0 then
                stateMatches = false;
                for _, s in ipairs(anim.states) do
                    if s == state then
                        stateMatches = true;
                        break
                    end
                end
            end
            -- validate input triggers
            if anim.triggers then
                for _, t in ipairs(anim.triggers) do
                    if t.type == "input" then
                        if t.mode == "hold" and not input.bind("animis", t.bind) then
                            stateMatches = false;
                            break
                        end
                        if (t.mode == "toggle" or t.mode == "switch") and not layer.inputToggles[t.bind] then
                            stateMatches = false;
                            break
                        end
                    elseif t.type == "random" then
                        -- don't loop forever without duration
                        if not anim.duration then
                            stateMatches = false
                            break
                        end
                        -- duration handled above
                    end
                end
            end
            -- check stored trigger for chains
            if not anim.triggers and layer.triggerBind then
                if layer.triggerMode == "toggle" or layer.triggerMode == "switch" then
                    -- only continue if still on
                    if not layer.inputToggles[layer.triggerBind] then
                        stateMatches = false
                    end
                elseif layer.triggerMode == "hold" then
                    -- only continue if still held
                    if not input.bind("animis", layer.triggerBind) then
                        stateMatches = false
                    end
                end
            end
            if (stateMatches or anim.persist) then
                if config.DEBUG then
                    sb.logInfo("[Animis] continuing anim: " .. layerName .. " -> " .. tostring(layer.currentAnimName) ..
                                   " stateMatches=" .. tostring(stateMatches) .. " persist=" .. tostring(anim.persist))
                end
                continueAnimation(dt, layer, layerName)
                return
            end
            -- check if we should resume interrupted anim
            if layer.interruptedAnim and layer.interruptedBind then
                -- check if trigger still active
                local shouldResume = false
                if layer.inputToggles[layer.interruptedBind] then
                    -- still toggled on
                    shouldResume = true
                elseif input.bind("animis", layer.interruptedBind) then
                    -- still held
                    shouldResume = true
                end
                if shouldResume and layer.animations and layer.animations[layer.interruptedAnim] then
                    if config.DEBUG then
                        sb.logInfo("[Animis] resuming interrupted: " .. layerName .. " -> " ..
                                       tostring(layer.interruptedAnim))
                    end
                    local resumeAnim = layer.animations[layer.interruptedAnim]
                    layer.interruptedAnim = nil
                    layer.interruptedBind = nil
                    playAnimation(dt, layer, layer.animations[layer.interruptedAnim] and layer.interruptedAnim or
                        layer.currentAnimName, resumeAnim, layerName, state, PRIORITY_INPUT)
                    return
                else
                    -- Interrupted trigger no longer active - clear it
                    layer.interruptedAnim = nil
                    layer.interruptedBind = nil
                end
            end
        end
    end

    ::skipContinuation::
    -- SECTION 3: random triggers (priority 2)
    local curPriority = layer.animPriority or 0
    if curPriority < PRIORITY_RANDOM then
        for _, r in ipairs(lookup.randoms or {}) do
            local a = r.data
            local stateMatches = false
            if a.states and #a.states > 0 then
                for _, s in ipairs(a.states) do
                    if s == state then
                        stateMatches = true;
                        break
                    end
                end
            else
                -- no states = any state
                stateMatches = true
            end
            if stateMatches and shouldTriggerRandom(r.name, r.trigger, layer, now) then
                playAnimation(dt, layer, r.name, a, layerName, state, PRIORITY_RANDOM)
                return
            end
        end
    end

    -- SECTION 4: state-based animations (priority 1)
    local candidates = {}
    for _, c in ipairs(lookup.byState[state] or {}) do
        table.insert(candidates, c)
    end
    for _, c in ipairs(lookup.defaults or {}) do
        table.insert(candidates, c)
    end
    for _, cand in ipairs(candidates) do
        if not cand.data.triggers or #cand.data.triggers == 0 then
            -- play it
            playAnimation(dt, layer, cand.name, cand.data, layerName, state, 1)
            return
        end
    end
end

-- Init / load
function init()
    config = animis_config.loadConfig()
    data = animis_config.loadData(player.uniqueId())
    idleNum = tonumber(player.personality().idle:match("idle.(%d+)")) or 1
    if not data then
        sb.logError("[Animis] Failed to load animation data!")
        data = {}
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

    local animisLayers = {}

    for layerName, layer in pairs(data) do
        if not layer.animations then
            goto continue
        end
        animisLayers[layerName] = true
        local val = {}
        for name, anim in pairs(layer.animations) do
            if anim.triggers and type(anim.triggers) ~= "table" then
                anim.triggers = {anim.triggers}
            end
            anim = applyDefaults(anim)
            if validateAnimation(name, anim) then
                val[name] = anim
            end
        end
        layer.animations = val
        animationLookup[layerName] = buildLookups(layer.animations)
        layer.currentAnimName = nil;
        layer.currentAnimData = nil;
        layer.previousAnimName = nil;
        layer.startState = nil
        layer.animStartTime = 0;
        layer.time = 1;
        layer.previousTime = 0;
        layer.oneTime = false
        layer.randomCooldowns = {};
        layer.randomChecks = {};
        layer.inputToggles = {}
        layer.previousPrefix = ""
        layer.previousSuffix = ""
        if groupFuncs[layerName] and layer.group then
            groupFuncs[layerName](layer.group)
        end
        if typeFuncs[layerName] and layer.type then
            typeFuncs[layerName](layer.type)
        end

        ::continue::
    end

    player.setProperty("animisLayers", animisLayers)
end

function update(dt)
    if not data then
        return
    end
    local state = player.currentState()
    local now = os.time()
    if state == "idle" then
        idleNum = tonumber(player.personality().idle:match("idle.(%d+)")) or idleNum
    end
    for layerName, layer in pairs(data) do
        if layer.enabled ~= false and animationLookup[layerName] then
            updateLayer(dt, layer, layerName, state, now, animationLookup[layerName])
        end
    end
end

function uninit()
end
