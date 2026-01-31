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
    if target and target() and target():getPosition().z == posz() and not target():isNpc() then
        targetID = target():getId()
    elseif not (target and target()) then
        -- there is no saved data, do nothing
        if not targetID then return end

        -- look for target
        for i, spec in ipairs(SafeCall.global("getSpectators") or {}) do
            local sameFloor = spec:getPosition().z == posz()
            local oldTarget = spec:getId() == targetID
            
            if sameFloor and oldTarget then
                attack(spec)
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