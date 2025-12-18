local voc = player:getVocation()
if voc == 1 or voc == 11 then
    setDefaultTab("Cave")
    UI.Separator()
    local exetaLowHpMacro = macro(100000, "Exeta when low hp", function() end)
    BotDB.registerMacro(exetaLowHpMacro, "exetaLowHp")
    
    local lastCast = now
    onCreatureHealthPercentChange(function(creature, healthPercent)
        if not exetaLowHpMacro:isOn() then return end
        if healthPercent > 15 then return end 
        if not CaveBot or not CaveBot.isOff or CaveBot.isOff() then return end
        if not TargetBot or not TargetBot.isOff or TargetBot.isOff() then return end
        if modules.game_cooldown.isGroupCooldownIconActive(3) then return end
        if creature:getPosition() and getDistanceBetween(pos(),creature:getPosition()) > 1 then return end
        if canCast("exeta res") and now - lastCast > 6000 then
            say("exeta res")
            lastCast = now
        end
    end)

    -- Non-blocking cooldown for exeta if player nearby
    local lastExetaPlayer = 0
    local exetaIfPlayerMacro = macro(500, "ExetaIfPlayer", function()
        if not CaveBot or not CaveBot.isOff or CaveBot.isOff() then return end
        -- Non-blocking cooldown check
        if (now - lastExetaPlayer) < 6000 then return end
    	if getMonsters(1) >= 1 and getPlayers(6) > 0 then
    		say("exeta res")
    		lastExetaPlayer = now
    	end
    end)
    BotDB.registerMacro(exetaIfPlayerMacro, "exetaIfPlayer")
    UI.Separator()
end