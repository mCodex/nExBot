setDefaultTab("Tools")

local targetID = nil

local UNREACHABLE_TEXT_PATTERNS = {
    "sorry, not possible",
    "there is no way",
    "creature is not reachable",
}

local function isUnreachableMessage(text)
    if type(text) ~= "string" then return false end
    local t = text:lower()
    for i = 1, #UNREACHABLE_TEXT_PATTERNS do
        if t:find(UNREACHABLE_TEXT_PATTERNS[i], 1, true) then
            return true
        end
    end
    return false
end

-- escape when attacking will reset hold target
onKeyPress(function(keys)
    if keys == "Escape" and targetID then
        targetID = nil
    end
end)

-- If the client reports unreachable while Hold Target is active, clear the
-- remembered target so this module doesn't keep forcing the same stale target.
onTextMessage(function(mode, text)
    if not targetID then return end
    if not isUnreachableMessage(text) then return end

    if MonsterAI and MonsterAI.Reachability and MonsterAI.Reachability.markBlocked then
        pcall(function() MonsterAI.Reachability.markBlocked(targetID, "not_possible") end)
    end

    if AttackStateMachine and AttackStateMachine.skipCreature then
        pcall(function() AttackStateMachine.skipCreature(targetID, 15000) end)
    end

    targetID = nil
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
                    -- Respect ASM skip-list: do not re-force recently blocked targets.
                    if AttackStateMachine and AttackStateMachine.isSkipped and AttackStateMachine.isSkipped(targetID) then
                        targetID = nil
                        return
                    end

                    -- Respect reachability: if blocked/unreachable, clear hold lock.
                    if MonsterAI and MonsterAI.Reachability and MonsterAI.Reachability.isReachable then
                        local reachable = false
                        local okReach, rr = pcall(function() return MonsterAI.Reachability.isReachable(spec) end)
                        if okReach and rr == true then reachable = true end
                        if not reachable then
                            targetID = nil
                            if AttackStateMachine and AttackStateMachine.skipCreature then
                                pcall(function() AttackStateMachine.skipCreature(spec:getId(), 15000) end)
                            end
                            return
                        end
                    end

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
NxBotSection
  height: 30

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