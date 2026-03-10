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
local holdTargetEnabled = false
if UnifiedTick and UnifiedTick.register then
    -- Register with UnifiedTick for consolidated tick management
    UnifiedTick.register("hold_target", {
        interval = 100,
        priority = UnifiedTick.Priority.HIGH,
        handler = holdTargetHandler,
        group = "targeting"
    })
    -- Start disabled; state restored below
    UnifiedTick.setEnabled("hold_target", false)
else
    -- Fallback: nameless macro guarded by enabled flag
    macro(100, function()
        if not holdTargetEnabled then return end
        holdTargetHandler()
    end)
end

local holdTargetUI = setupUI([[
Panel
  height: 20

  NxSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    margin-top: 0
    !text: tr('Hold Target')
]])

holdTargetUI.title.onClick = function(widget)
    holdTargetEnabled = not holdTargetEnabled
    widget:setOn(holdTargetEnabled)
    if UnifiedTick then
        UnifiedTick.setEnabled("hold_target", holdTargetEnabled)
    end
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
        CharacterDB.set("macros.holdTarget", holdTargetEnabled)
    else
        BotDB.set("macros.holdTarget", holdTargetEnabled)
    end
end

local savedHoldTargetState = (function()
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
        return CharacterDB.get("macros.holdTarget") == true
    end
    return BotDB.get("macros.holdTarget") == true
end)()
if savedHoldTargetState then
    holdTargetEnabled = true
    holdTargetUI.title:setOn(true)
    if UnifiedTick then
        UnifiedTick.setEnabled("hold_target", true)
    end
end 