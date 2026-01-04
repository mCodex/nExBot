local voc = player:getVocation()
if voc == 1 or voc == 11 then
    setDefaultTab("Cave")
    UI.Separator()
    local exetaLowHpMacro = macro(100000, "Exeta when low hp", function() end)
    BotDB.registerMacro(exetaLowHpMacro, "exetaLowHp")
    
    local lastCast = now

    -- Telemetry for Exeta
    local exetaStats = { lowHpCasts = 0, playerTriggeredCasts = 0 }
    nExBot = nExBot or {}
    nExBot.Exeta = nExBot.Exeta or {}
    nExBot.Exeta.getStats = function() return exetaStats end

    -- Use EventBus health event to trigger exeta on nearby low-HP creatures
    if EventBus then
      EventBus.on("creature:health", function(creature, healthPercent)
        if not exetaLowHpMacro:isOn() then return end
        if healthPercent > 15 then return end 
        if not CaveBot or CaveBot.isOff() then return end
        if not TargetBot or TargetBot.isOff() then return end
        if modules.game_cooldown.isGroupCooldownIconActive(3) then return end
        local cpos = creature and creature.getPosition and creature:getPosition()
        if not cpos then return end
        if getDistanceBetween(pos(), cpos) > 1 then return end
        if canCast("exeta res") and now - lastCast > 6000 then
          say("exeta res")
          lastCast = now
          exetaStats.lowHpCasts = (exetaStats.lowHpCasts or 0) + 1
        end
      end, 30)
    else
      -- Fallback: native callback (existing behavior)
      onCreatureHealthPercentChange(function(creature, healthPercent)
        if not exetaLowHpMacro:isOn() then return end
        if healthPercent > 15 then return end 
        if not CaveBot or CaveBot.isOff() then return end
        if not TargetBot or TargetBot.isOff() then return end
        if modules.game_cooldown.isGroupCooldownIconActive(3) then return end
        if creature:getPosition() and getDistanceBetween(pos(),creature:getPosition()) > 1 then return end
        if canCast("exeta res") and now - lastCast > 6000 then
          say("exeta res")
          lastCast = now
          exetaStats.lowHpCasts = (exetaStats.lowHpCasts or 0) + 1
        end
      end)
    end

    -- Non-blocking cooldown for exeta if player nearby
    local lastExetaPlayer = 0
    local exetaStats = { lowHpCasts = 0, playerTriggeredCasts = 0 }
    nExBot = nExBot or {}
    nExBot.Exeta = nExBot.Exeta or {}
    nExBot.Exeta.getStats = function() return exetaStats end

    local exetaIfPlayerMacro = macro(100000, "ExetaIfPlayer", function() end)
    BotDB.registerMacro(exetaIfPlayerMacro, "exetaIfPlayer")

    -- Robust safe_unpack helper (handles missing table.unpack/unpack)
    local function safe_unpack(tbl)
      if not tbl then return end
      if table and table.unpack then return table.unpack(tbl) end
      if unpack then return unpack(tbl) end
      local n = #tbl
      if n == 0 then return end
      return tbl[1], tbl[2], tbl[3], tbl[4], tbl[5], tbl[6], tbl[7], tbl[8], tbl[9], tbl[10], tbl[11], tbl[12]
    end

    -- Safe debounce factory
    local function makeDebounce(ms, fn)
      if nExBot and nExBot.EventUtil and nExBot.EventUtil.debounce then
        return nExBot.EventUtil.debounce(ms, fn)
      end
      local scheduled = false
      return function(...)
        if scheduled then return end
        scheduled = true
        local args = {...}
        schedule(ms, function()
          scheduled = false
          pcall(fn, safe_unpack(args))
        end)
      end
    end

    local function checkAndCastExeta()
      if not exetaIfPlayerMacro:isOn() then return end
      if not CaveBot or CaveBot.isOff() then return end
      if (now - lastExetaPlayer) < 6000 then return end
      if modules.game_cooldown.isGroupCooldownIconActive(3) then return end
      if not canCast("exeta res") then return end

      -- Check for nearby monsters (radius 1)
      local monstersNearby = 0
      if MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby then
        monstersNearby = #MovementCoordinator.MonsterCache.getNearby(1)
      else
        local p = pos()
        local creatures = g_map.getSpectatorsInRange(p, false, 1, 1)
        for i = 1, #creatures do
          local c = creatures[i]
          if c and c:isMonster() and not c:isDead() then
            monstersNearby = monstersNearby + 1
          end
        end
      end

      if monstersNearby < 1 then return end

      -- Check for nearby players (radius 6)
      local playersNearby = 0
      local ppos = pos()
      local spects = g_map.getSpectatorsInRange(ppos, false, 6, 6)
      for i = 1, #spects do
        local c = spects[i]
        if c and c:isPlayer() and not c:isLocalPlayer() then
          playersNearby = playersNearby + 1
        end
      end

      if playersNearby > 0 then
        say("exeta res")
        lastExetaPlayer = now
        exetaStats.playerTriggeredCasts = (exetaStats.playerTriggeredCasts or 0) + 1
      end
    end

    local debouncedCheck = makeDebounce(120, checkAndCastExeta)

    if EventBus then
      EventBus.on("monster:appear", function(creature)
        if creature and creature:isMonster() then
          debouncedCheck()
        end
      end, 20)

      EventBus.on("creature:move", function(creature, oldPos)
        if creature and creature:isMonster() then
          debouncedCheck()
        end
      end, 20)

      EventBus.on("creature:appear", function(creature)
        if creature and creature:isPlayer() then
          debouncedCheck()
        end
      end, 10)

      EventBus.on("player:move", function(newPos, oldPos)
        debouncedCheck()
      end, 10)

    end

    UI.Separator()
end