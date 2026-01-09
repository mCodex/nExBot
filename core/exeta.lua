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

    -- Non-blocking cooldowns and telemetry (player / amp)
    local lastExetaPlayer = 0

    -- extend telemetry
    exetaStats.playerTriggeredCasts = exetaStats.playerTriggeredCasts or 0
    exetaStats.ampCasts = exetaStats.ampCasts or 0

    local exetaIfPlayerMacro = macro(100000, "Exeta If Player", function() end)
    BotDB.registerMacro(exetaIfPlayerMacro, "exetaIfPlayer")

    -- "Amp" (ranged attacker) macro: cast when a distant creature is attacking you
    local exetaAmpMacro = macro(100000, "Exeta Amp Res", function() end)
    BotDB.registerMacro(exetaAmpMacro, "exetaAmpRes")

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

      -- Exeta Amp: trigger when a distant creature damages the player
      EventBus.on("player:damage", function(damage, source)
        if not exetaAmpMacro:isOn() then return end
        if (now - lastExetaAmp) < 6000 then return end
        if not CaveBot or CaveBot.isOff() then return end
        if modules.game_cooldown.isGroupCooldownIconActive(3) then return end
        if not canCast("exeta res") then return end
        if not source then return end
        local ok, spos = pcall(function() return source and source:getPosition() end)
        if not ok or not spos then return end
        if getDistanceBetween(pos(), spos) <= 1 then return end -- only distant
        say("exeta res")
        lastExetaAmp = now
        exetaStats.ampCasts = (exetaStats.ampCasts or 0) + 1
      end, 20)

    end

    -- Fallback: native health change detection for environments without EventBus
    if not EventBus and onHealthChange then
      onHealthChange(function(localPlayer, health, maxHealth, oldHealth, oldMax)
        if not exetaAmpMacro:isOn() then return end
        if not oldHealth or not health then return end
        local dmg = oldHealth - health
        if dmg <= 0 then return end
        if (now - lastExetaAmp) < 6000 then return end
        if not CaveBot or CaveBot.isOff() then return end
        if modules.game_cooldown.isGroupCooldownIconActive(3) then return end
        if not canCast("exeta res") then return end

        -- Best-effort attribution: find a distant monster near player
        local playerPos = player and player:getPosition()
        if not playerPos then return end
        local radius = 7
        local creatures = (MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby)
          and MovementCoordinator.MonsterCache.getNearby(radius)
          or g_map.getSpectatorsInRange(playerPos, false, radius, radius)
        local best = nil
        for i = 1, #creatures do
          local m = creatures[i]
          if m and m:isMonster() and not m:isDead() and m:getPosition() then
            local mpos = m:getPosition()
            local dist = math.max(math.abs(playerPos.x - mpos.x), math.abs(playerPos.y - mpos.y))
            if dist > 1 then best = m; break end
          end
        end

        if best and canCast("exeta res") then
          say("exeta res")
          lastExetaAmp = now
          exetaStats.ampCasts = (exetaStats.ampCasts or 0) + 1
        end
      end)
    end

    UI.Separator()
end