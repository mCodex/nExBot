setDefaultTab("Tools")

local targetID = nil

-- escape when attacking will reset hold target
onKeyPress(function(keys)
    if keys == "Escape" and targetID then
        targetID = nil
    end
end)

-- Hold Target handler function (shared by UnifiedTick and fallback macro)
local function holdTargetHandler()
    -- if attacking then save it as target, but check pos z in case of marking by mistake on other floor
    local t = target and target()
    local tpos = t and t:getPosition()
    if tpos and tpos.z == posz() and not t:isNpc() then
        targetID = t:getId()
    else
        -- No valid target (nil, wrong floor, NPC, or missing position)
        if not targetID then return end

        -- look for target
        for i, spec in ipairs(SafeCall.global("getSpectators") or {}) do
            local specPos = spec:getPosition()
            if specPos then
                local sameFloor = specPos.z == posz()
                local oldTarget = spec:getId() == targetID

                if sameFloor and oldTarget then
                    -- Route through ASM to prevent competing attack commands
                    if AttackStateMachine and AttackStateMachine.forceAttack then
                        AttackStateMachine.forceAttack(spec)
                    else
                        attack(spec)  -- Fallback if ASM not loaded
                    end
                    return
                end
            end
        end
    end
end

-- Use UnifiedTick if available, fallback to standalone macro
local holdTargetMacro
if UnifiedTick and UnifiedTick.register then
    -- Register with UnifiedTick for consolidated tick management
    UnifiedTick.register("hold_target", {
        interval = 100,
        priority = UnifiedTick.Priority.HIGH,
        handler = holdTargetHandler,
        group = "targeting"
    })
    -- Create a dummy macro for UI toggle compatibility
    holdTargetMacro = macro(100, "Hold Target", function() end)
    holdTargetMacro:setOn(true)
    -- Sync macro toggle with UnifiedTick handler
    holdTargetMacro.onSwitch = function(m)
        UnifiedTick.setEnabled("hold_target", m:isOn())
    end
else
    -- Fallback to standalone macro if UnifiedTick not available
    holdTargetMacro = macro(100, "Hold Target", holdTargetHandler)
end
BotDB.registerMacro(holdTargetMacro, "holdTarget") 