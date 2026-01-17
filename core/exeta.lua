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
    local lastExetaAmp = 0  -- FIXED: Declare variable to prevent nil error

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

      -- ═══════════════════════════════════════════════════════════════════════
      -- EXETA AMP RES: Distant monster challenge for party protection
      -- Cast exeta res when there are distant monsters NOT attacking the local player
      -- This helps pull aggro from monsters attacking party members
      -- ═══════════════════════════════════════════════════════════════════════
      
      -- Direction vectors for facing check
      local DIR_VECTORS = {
        [0] = {x = 0, y = -1},  -- North
        [1] = {x = 1, y = 0},   -- East
        [2] = {x = 0, y = 1},   -- South
        [3] = {x = -1, y = 0},  -- West
        [4] = {x = 1, y = -1},  -- NE
        [5] = {x = 1, y = 1},   -- SE
        [6] = {x = -1, y = 1},  -- SW
        [7] = {x = -1, y = -1}, -- NW
      }
      
      -- Helper: Check if a monster is facing the local player (i.e., attacking us)
      local function isMonsterFacingPlayer(creature)
        if not creature then return false end
        local direction = creature.getDirection and creature:getDirection()
        if direction == nil then return false end
        
        local cpos = creature:getPosition()
        local ppos = pos()
        if not cpos or not ppos then return false end
        
        local dx = ppos.x - cpos.x
        local dy = ppos.y - cpos.y
        
        local vec = DIR_VECTORS[direction]
        if not vec then return false end
        
        -- Check if player is in the direction the monster is facing
        if vec.x == 0 then
          -- North or South
          return (dy * vec.y) > 0 and math.abs(dx) <= 1
        elseif vec.y == 0 then
          -- East or West
          return (dx * vec.x) > 0 and math.abs(dy) <= 1
        else
          -- Diagonal
          local inX = (vec.x > 0 and dx > 0) or (vec.x < 0 and dx < 0)
          local inY = (vec.y > 0 and dy > 0) or (vec.y < 0 and dy < 0)
          return inX and inY
        end
      end
      
      -- Helper: Check if a monster is distant (distance > 1, within screen range)
      local function isDistantMonster(creature)
        if not creature or not creature:isMonster() or creature:isDead() then return false end
        local cpos = creature:getPosition()
        local ppos = pos()
        if not cpos or not ppos then return false end
        local dist = math.max(math.abs(ppos.x - cpos.x), math.abs(ppos.y - cpos.y))
        return dist > 1 and dist <= 7
      end
      
      -- Helper: Try to cast exeta amp res
      local function tryExetaAmp(reason)
        if not exetaAmpMacro:isOn() then return false end
        if (now - lastExetaAmp) < 6000 then return false end
        if not CaveBot or CaveBot.isOff() then return false end
        if modules.game_cooldown.isGroupCooldownIconActive(3) then return false end
        if not canCast("exeta amp res") then return false end
        
        say("exeta amp res")
        lastExetaAmp = now
        exetaStats.ampCasts = (exetaStats.ampCasts or 0) + 1
        
        -- Emit event for debugging/telemetry
        if EventBus then
          EventBus.emit("exeta:amp_cast", reason)
        end
        return true
      end
      
      -- Main check: Find distant monsters NOT attacking/facing the local player
      local function checkDistantNotAttackingMe()
        if not exetaAmpMacro:isOn() then return end
        if (now - lastExetaAmp) < 6000 then return end
        
        -- Get nearby monsters from cache or fallback to map scan
        local monsters = nil
        if MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby then
          monsters = MovementCoordinator.MonsterCache.getNearby(7)
        else
          local ppos = pos()
          if ppos then
            monsters = g_map.getSpectatorsInRange(ppos, false, 7, 7)
          end
        end
        
        if not monsters then return end
        
        -- Count distant monsters that are NOT facing/attacking the local player
        local distantNotAttackingMe = 0
        for i = 1, #monsters do
          local m = monsters[i]
          if m and m:isMonster() and not m:isDead() then
            -- Check if monster is distant AND not facing the local player
            if isDistantMonster(m) and not isMonsterFacingPlayer(m) then
              distantNotAttackingMe = distantNotAttackingMe + 1
            end
          end
        end
        
        -- Cast if there's at least 1 distant monster not attacking us (likely attacking party)
        if distantNotAttackingMe >= 1 then
          tryExetaAmp("distant_not_attacking_me:" .. distantNotAttackingMe)
        end
      end
      
      local debouncedAmpCheck = makeDebounce(200, checkDistantNotAttackingMe)
      
      -- Trigger check when monsters appear
      EventBus.on("monster:appear", function(creature)
        if not exetaAmpMacro:isOn() then return end
        if isDistantMonster(creature) then
          debouncedAmpCheck()
        end
      end, 20)
      
      -- Trigger check when monsters move (may become distant)
      EventBus.on("creature:move", function(creature, oldPos)
        if not exetaAmpMacro:isOn() then return end
        if not creature or not creature:isMonster() then return end
        if isDistantMonster(creature) then
          debouncedAmpCheck()
        end
      end, 25)
      
      -- Trigger check when monster turns (may start attacking party member)
      EventBus.on("creature:turn", function(creature, newDir, oldDir)
        if not exetaAmpMacro:isOn() then return end
        if not creature or not creature:isMonster() then return end
        -- If monster turned AWAY from us while distant, it's attacking someone else
        if isDistantMonster(creature) and not isMonsterFacingPlayer(creature) then
          debouncedAmpCheck()
        end
      end, 20)
      
      -- Trigger check when player moves (distances change)
      EventBus.on("player:move", function(newPos, oldPos)
        if not exetaAmpMacro:isOn() then return end
        debouncedAmpCheck()
      end, 25)
      
      -- Trigger check when we change target (our target ID changes)
      EventBus.on("targetbot/target_acquired", function(creature)
        if not exetaAmpMacro:isOn() then return end
        -- Re-check since our target changed
        debouncedAmpCheck()
      end, 20)
      
      -- Trigger check when target dies (we may have untargeted distant monsters)
      EventBus.on("monster:disappear", function(creature)
        if not exetaAmpMacro:isOn() then return end
        debouncedAmpCheck()
      end, 25)

    end

    -- Fallback: polling-based check for environments without EventBus
    if not EventBus then
      -- Direction vectors for facing check (fallback)
      local FB_DIR_VECTORS = {
        [0] = {x = 0, y = -1},  -- North
        [1] = {x = 1, y = 0},   -- East
        [2] = {x = 0, y = 1},   -- South
        [3] = {x = -1, y = 0},  -- West
        [4] = {x = 1, y = -1},  -- NE
        [5] = {x = 1, y = 1},   -- SE
        [6] = {x = -1, y = 1},  -- SW
        [7] = {x = -1, y = -1}, -- NW
      }
      
      -- Helper: Check if monster is facing local player (fallback version)
      local function fbIsMonsterFacingPlayer(creature, playerPos)
        local direction = creature.getDirection and creature:getDirection()
        if direction == nil then return false end
        local cpos = creature:getPosition()
        if not cpos then return false end
        
        local dx = playerPos.x - cpos.x
        local dy = playerPos.y - cpos.y
        local vec = FB_DIR_VECTORS[direction]
        if not vec then return false end
        
        if vec.x == 0 then
          return (dy * vec.y) > 0 and math.abs(dx) <= 1
        elseif vec.y == 0 then
          return (dx * vec.x) > 0 and math.abs(dy) <= 1
        else
          local inX = (vec.x > 0 and dx > 0) or (vec.x < 0 and dx < 0)
          local inY = (vec.y > 0 and dy > 0) or (vec.y < 0 and dy < 0)
          return inX and inY
        end
      end
      
      -- Simple polling macro to check for distant monsters not attacking local player
      macro(500, "ExetaAmpFallback", function()
        if not exetaAmpMacro:isOn() then return end
        if (now - lastExetaAmp) < 6000 then return end
        if not CaveBot or CaveBot.isOff() then return end
        if modules.game_cooldown.isGroupCooldownIconActive(3) then return end
        if not canCast("exeta amp res") then return end

        -- Find distant monsters not facing/attacking local player
        local playerPos = player and player:getPosition()
        if not playerPos then return end
        
        local creatures = (MovementCoordinator and MovementCoordinator.MonsterCache and MovementCoordinator.MonsterCache.getNearby)
          and MovementCoordinator.MonsterCache.getNearby(7)
          or g_map.getSpectatorsInRange(playerPos, false, 7, 7)
        
        if not creatures then return end
        
        local distantNotAttackingMe = 0
        for i = 1, #creatures do
          local m = creatures[i]
          if m and m:isMonster() and not m:isDead() then
            local mpos = m:getPosition()
            if mpos then
              local dist = math.max(math.abs(playerPos.x - mpos.x), math.abs(playerPos.y - mpos.y))
              -- Check if distant AND not facing the local player
              if dist > 1 and dist <= 7 and not fbIsMonsterFacingPlayer(m, playerPos) then
                distantNotAttackingMe = distantNotAttackingMe + 1
              end
            end
          end
        end

        if distantNotAttackingMe >= 1 then
          say("exeta amp res")
          lastExetaAmp = now
          exetaStats.ampCasts = (exetaStats.ampCasts or 0) + 1
        end
      end)
    end

    UI.Separator()
end