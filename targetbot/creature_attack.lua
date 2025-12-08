local targetBotLure = false
local targetCount = 0 
local delayValue = 0
local lureMax = 0
local anchorPosition = nil
local lastCall = now
local delayFrom = nil
local dynamicLureDelay = false

-- Pre-computed direction offsets (reused across functions - DRY)
local DIRECTIONS = {
  {x = 0, y = -1},   -- North
  {x = 1, y = 0},    -- East  
  {x = 0, y = 1},    -- South
  {x = -1, y = 0},   -- West
  {x = 1, y = -1},   -- NorthEast
  {x = 1, y = 1},    -- SouthEast
  {x = -1, y = 1},   -- SouthWest
  {x = -1, y = -1}   -- NorthWest
}

-- Direction index to vector (monster facing)
local DIR_VECTORS = {
  [0] = {x = 0, y = -1},  -- North
  [1] = {x = 1, y = 0},   -- East
  [2] = {x = 0, y = 1},   -- South
  [3] = {x = -1, y = 0},  -- West
  [4] = {x = 1, y = -1},  -- NorthEast
  [5] = {x = 1, y = 1},   -- SouthEast
  [6] = {x = -1, y = 1},  -- SouthWest
  [7] = {x = -1, y = -1}  -- NorthWest
}

--------------------------------------------------------------------------------
-- SIMPLIFIED WAVE AVOIDANCE SYSTEM
-- 
-- Key insight: Monsters face the player when attacking. A wave attack hits
-- tiles in FRONT of the monster. We only need to check if we're in front.
--
-- Simple algorithm:
-- 1. Check if any monster is facing us (within 1-2 tiles of their front arc)
-- 2. If yes, find an adjacent tile that is NOT in front of any monster
-- 3. Move there. That's it.
--------------------------------------------------------------------------------

-- Avoidance state (prevents oscillation)
local avoidanceState = {
  lastMove = 0,
  cooldown = 300,      -- Don't move more than once per 300ms
  lastSafePos = nil,
  stickiness = 500     -- Stay at safe position for 500ms
}

-- Pure function: Check if position is in front of a monster (in its attack arc)
-- @param pos: position to check {x, y, z}
-- @param monsterPos: monster position {x, y, z}
-- @param monsterDir: monster direction (0-7)
-- @param range: how far the attack reaches (default 5)
-- @return boolean
local function isInFrontArc(pos, monsterPos, monsterDir, range)
  range = range or 5
  
  local dirVec = DIR_VECTORS[monsterDir]
  if not dirVec then return false end
  
  local dx = pos.x - monsterPos.x
  local dy = pos.y - monsterPos.y
  
  -- Must be within range
  local dist = math.max(math.abs(dx), math.abs(dy))
  if dist == 0 or dist > range then
    return false
  end
  
  -- Simple front arc check: player must be in the direction monster is facing
  -- For cardinal directions (N/E/S/W): must be directly in line
  -- For diagonal: must be in the quadrant
  
  if dirVec.x == 0 then
    -- North or South: check if player is in that direction and within 1 tile sideways
    local inDirection = (dy * dirVec.y) > 0
    local nearCenter = math.abs(dx) <= 1
    return inDirection and nearCenter
  elseif dirVec.y == 0 then
    -- East or West: check if player is in that direction and within 1 tile vertically
    local inDirection = (dx * dirVec.x) > 0
    local nearCenter = math.abs(dy) <= 1
    return inDirection and nearCenter
  else
    -- Diagonal: check if player is in that quadrant
    local inX = (dirVec.x > 0 and dx > 0) or (dirVec.x < 0 and dx < 0)
    local inY = (dirVec.y > 0 and dy > 0) or (dirVec.y < 0 and dy < 0)
    return inX and inY
  end
end

-- Pure function: Check if a position is dangerous (in front of any monster)
-- @param pos: position to check
-- @param monsters: array of monster creatures
-- @return boolean, number (isDangerous, dangerCount)
local function isDangerousPosition(pos, monsters)
  local dangerCount = 0
  
  for i = 1, #monsters do
    local monster = monsters[i]
    if monster and not monster:isDead() then
      local mpos = monster:getPosition()
      local mdir = monster:getDirection()
      
      -- Check if we're in front of this monster
      if isInFrontArc(pos, mpos, mdir, 5) then
        dangerCount = dangerCount + 1
      end
      
      -- Also dangerous if adjacent (melee range)
      local dist = math.max(math.abs(pos.x - mpos.x), math.abs(pos.y - mpos.y))
      if dist == 1 then
        dangerCount = dangerCount + 1
      end
    end
  end
  
  return dangerCount > 0, dangerCount
end

-- Pure function: Find the safest adjacent tile
-- @param playerPos: current player position
-- @param monsters: array of monsters
-- @param currentTarget: current attack target (to maintain range)
-- @return position or nil
local function findSafeAdjacentTile(playerPos, monsters, currentTarget)
  local candidates = {}
  local currentDanger, _ = isDangerousPosition(playerPos, monsters)
  
  -- If we're not in danger, don't move
  if not currentDanger then
    return nil
  end
  
  -- Check all adjacent tiles
  for i = 1, 8 do
    local dir = DIRECTIONS[i]
    local checkPos = {
      x = playerPos.x + dir.x,
      y = playerPos.y + dir.y,
      z = playerPos.z
    }
    
    local tile = g_map.getTile(checkPos)
    if tile and tile:isWalkable() and not tile:hasCreature() then
      local isDangerous, dangerCount = isDangerousPosition(checkPos, monsters)
      
      -- Calculate distance to target (if any)
      local targetDist = 99
      if currentTarget then
        local tpos = currentTarget:getPosition()
        targetDist = math.max(math.abs(checkPos.x - tpos.x), math.abs(checkPos.y - tpos.y))
      end
      
      candidates[#candidates + 1] = {
        pos = checkPos,
        danger = dangerCount,
        targetDist = targetDist
      }
    end
  end
  
  if #candidates == 0 then
    return nil
  end
  
  -- Sort by: 1) lowest danger, 2) closest to target
  table.sort(candidates, function(a, b)
    if a.danger ~= b.danger then
      return a.danger < b.danger
    end
    return a.targetDist < b.targetDist
  end)
  
  -- Return best candidate if it's safer than current position
  local best = candidates[1]
  if best.danger == 0 or best.danger < (#monsters) then
    return best.pos
  end
  
  return nil
end

-- Main avoidance function (called from walk logic)
-- Uses state to prevent oscillation
-- @return boolean: true if avoidance move was initiated
local function avoidWaveAttacks()
  local currentTime = now
  
  -- Cooldown check to prevent oscillation
  if currentTime - avoidanceState.lastMove < avoidanceState.cooldown then
    return false
  end
  
  -- If we recently moved to a safe position, stay there
  if avoidanceState.lastSafePos then
    local playerPos = player:getPosition()
    local atSafePos = playerPos.x == avoidanceState.lastSafePos.x and 
                      playerPos.y == avoidanceState.lastSafePos.y
    
    if atSafePos and currentTime - avoidanceState.lastMove < avoidanceState.stickiness then
      return false
    end
  end
  
  -- Get monsters in range
  local playerPos = player:getPosition()
  local creatures = g_map.getSpectatorsInRange(playerPos, false, 7, 7)
  local monsters = {}
  
  for i = 1, #creatures do
    local c = creatures[i]
    if c:isMonster() and not c:isDead() then
      monsters[#monsters + 1] = c
    end
  end
  
  if #monsters == 0 then
    return false
  end
  
  -- Find safe tile
  local currentTarget = target()
  local safePos = findSafeAdjacentTile(playerPos, monsters, currentTarget)
  
  if safePos then
    avoidanceState.lastMove = currentTime
    avoidanceState.lastSafePos = safePos
    TargetBot.walkTo(safePos, 2, {ignoreNonPathable = true, precision = 0})
    return true
  end
  
  return false
end

-- EventBus integration: Reset avoidance state when monsters change
if EventBus then
  EventBus.on("monster:disappear", function(creature)
    avoidanceState.lastSafePos = nil
  end, 20)
  
  EventBus.on("player:move", function(newPos, oldPos)
    -- Reset stickiness when player moves
    if avoidanceState.lastSafePos then
      local atSafe = newPos.x == avoidanceState.lastSafePos.x and
                     newPos.y == avoidanceState.lastSafePos.y
      if not atSafe then
        avoidanceState.lastSafePos = nil
      end
    end
  end, 20)
end

-- Export simplified functions
nExBot.avoidWaveAttacks = avoidWaveAttacks
nExBot.isInFrontArc = isInFrontArc
nExBot.isDangerousPosition = isDangerousPosition

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS (Simplified and reusable)
--------------------------------------------------------------------------------

-- Pure function: Count walkable tiles around a position
-- @param position: center position
-- @return number
local function countWalkableTiles(position)
  local count = 0
  local tiles = getNearTiles(position)
  
  for i = 1, #tiles do
    if tiles[i]:isWalkable() then
      count = count + 1
    end
  end
  
  return count
end

-- Pure function: Check if player is trapped (no walkable adjacent tiles)
-- @param playerPos: player position
-- @return boolean
local function isPlayerTrapped(playerPos)
  for i = 1, 8 do
    local dir = DIRECTIONS[i]
    local checkPos = {
      x = playerPos.x + dir.x,
      y = playerPos.y + dir.y,
      z = playerPos.z
    }
    
    local tile = g_map.getTile(checkPos)
    if tile and tile:isWalkable(false) then
      return false
    end
  end
  return true
end

-- Reposition to tile with more escape routes and better tactical position
-- Improved algorithm with monster awareness and multi-tile search
-- @param minTiles: minimum walkable tiles threshold
-- @param config: creature config for context (includes anchor settings)
local function rePosition(minTiles, config)
  minTiles = minTiles or 6
  
  -- Cooldown to prevent jitter
  if now - lastCall < 400 then return end
  
  local playerPos = player:getPosition()
  local currentWalkable = countWalkableTiles(playerPos)
  
  -- Don't reposition if we have enough space
  if currentWalkable >= minTiles then return end
  
  -- Get nearby monsters for scoring
  local creatures = g_map.getSpectatorsInRange(playerPos, false, 5, 5)
  local monsters = {}
  for i = 1, #creatures do
    local c = creatures[i]
    if c:isMonster() and not c:isDead() then
      monsters[#monsters + 1] = c
    end
  end
  
  local currentTarget = target()
  local bestPos = nil
  local bestScore = -9999
  
  -- Get anchor constraints
  local anchorPos = config and config.anchor and anchorPosition
  local anchorRange = config and config.anchorRange or 5
  
  -- Search in a 2-tile radius for better positions
  for dx = -2, 2 do
    for dy = -2, 2 do
      if dx ~= 0 or dy ~= 0 then
        local checkPos = {
          x = playerPos.x + dx,
          y = playerPos.y + dy,
          z = playerPos.z
        }
        
        local shouldSkip = false
        
        -- Check anchor constraint FIRST (skip if violates anchor)
        if anchorPos then
          local anchorDist = math.max(
            math.abs(checkPos.x - anchorPos.x),
            math.abs(checkPos.y - anchorPos.y)
          )
          if anchorDist > anchorRange then
            shouldSkip = true  -- Skip this position, violates anchor
          end
        end
        
        if not shouldSkip then
          local tile = g_map.getTile(checkPos)
          if tile and tile:isWalkable() and not tile:hasCreature() then
            -- Score this position
            local score = 0
            
            -- Factor 1: Walkable tiles (escape routes) - most important
            local walkable = countWalkableTiles(checkPos)
            score = score + walkable * 10
            
            -- Factor 2: Distance from monster front arcs (safety)
            local inDangerZones = 0
            for j = 1, #monsters do
              local m = monsters[j]
              local mpos = m:getPosition()
              local mdir = m:getDirection()
              if isInFrontArc(checkPos, mpos, mdir, 5) then
                inDangerZones = inDangerZones + 1
              end
            end
            score = score - inDangerZones * 15
            
            -- Factor 3: Distance to current target (stay in attack range)
            if currentTarget then
              local tpos = currentTarget:getPosition()
              local targetDist = math.max(math.abs(checkPos.x - tpos.x), math.abs(checkPos.y - tpos.y))
              if targetDist <= 1 then
                score = score + 20  -- Adjacent is ideal
              elseif targetDist <= 3 then
                score = score + 10  -- Close range is good
              else
                score = score - targetDist * 2  -- Penalize getting too far
              end
            end
            
            -- Factor 4: Movement cost (prefer closer positions)
            local moveDist = math.abs(dx) + math.abs(dy)
            score = score - moveDist * 3
            
            -- Factor 5: Prefer cardinal directions (easier pathing)
            if dx == 0 or dy == 0 then
              score = score + 5
            end
            
            if score > bestScore then
              bestScore = score
              bestPos = checkPos
            end
          end
        end
      end
    end
  end
  
  -- Only move if we found a significantly better position
  local currentScore = currentWalkable * 10
  if bestPos and bestScore > currentScore + 10 then
    lastCall = now
    return CaveBot.GoTo(bestPos, 0)
  end
end

TargetBot.Creature.attack = function(params, targets, isLooting)
  if player:isWalking() then
    lastWalk = now
  end

  local config = params.config
  local creature = params.creature
  
  -- Cache attacking creature check
  local currentTarget = g_game.getAttackingCreature()
  if currentTarget ~= creature then
    g_game.attack(creature)
  end

  if not isLooting then
    TargetBot.Creature.walk(creature, config, targets)
  end

  -- Cache mana check
  local mana = player:getMana()
  local playerPos = player:getPosition()
  
  -- Group attack spell check
  if config.useGroupAttack and config.groupAttackSpell:len() > 1 and mana > config.minManaGroup then
    local creatures = g_map.getSpectatorsInRange(playerPos, false, config.groupAttackRadius, config.groupAttackRadius)
    local playersAround = false
    local monsters = 0
    
    for i = 1, #creatures do
      local c = creatures[i]
      if c:isPlayer() and not c:isLocalPlayer() then
        if not config.groupAttackIgnoreParty or c:getShield() <= 2 then
          playersAround = true
        end
      elseif c:isMonster() then
        monsters = monsters + 1
      end
    end
    
    if monsters >= config.groupAttackTargets and (not playersAround or config.groupAttackIgnorePlayers) then
      if TargetBot.sayAttackSpell(config.groupAttackSpell, config.groupAttackDelay) then
        return
      end
    end
  end

  -- Group attack rune check
  if config.useGroupAttackRune and config.groupAttackRune > 100 then
    local creaturePos = creature:getPosition()
    local creatures = g_map.getSpectatorsInRange(creaturePos, false, config.groupRuneAttackRadius, config.groupRuneAttackRadius)
    local playersAround = false
    local monsters = 0
    
    for i = 1, #creatures do
      local c = creatures[i]
      if c:isPlayer() and not c:isLocalPlayer() then
        if not config.groupAttackIgnoreParty or c:getShield() <= 2 then
          playersAround = true
        end
      elseif c:isMonster() then
        monsters = monsters + 1
      end
    end
    
    if monsters >= config.groupRuneAttackTargets and (not playersAround or config.groupAttackIgnorePlayers) then
      if TargetBot.useAttackItem(config.groupAttackRune, 0, creature, config.groupRuneAttackDelay) then
        return
      end
    end
  end
  
  -- Single target spell attack
  if config.useSpellAttack and config.attackSpell:len() > 1 and mana > config.minMana then
    if TargetBot.sayAttackSpell(config.attackSpell, config.attackSpellDelay) then
      return
    end
  end
  
  -- Single target rune attack
  if config.useRuneAttack and config.attackRune > 100 then
    if TargetBot.useAttackItem(config.attackRune, 0, creature, config.attackRuneDelay) then
      return
    end
  end
end

TargetBot.Creature.walk = function(creature, config, targets)
  local cpos = creature:getPosition()
  local pos = player:getPosition()
  
  --[[
    ═══════════════════════════════════════════════════════════════════════════
    TARGETBOT UNIFIED MOVEMENT SYSTEM v3
    ═══════════════════════════════════════════════════════════════════════════
    
    All features work together with clear priority and mutual awareness.
    
    PHASE 1: CONTEXT GATHERING
    - Collect all relevant state: health, distance, monsters, traps, etc.
    
    PHASE 2: LURE DECISIONS (CaveBot delegation)
    - smartPull, dynamicLure, closeLure
    - Only if target is NOT low health
    - Only if NOT trapped
    
    PHASE 3: MOVEMENT PRIORITY
    1. SAFETY: avoidAttacks (wave avoidance)
    2. SURVIVAL: Chase low-health targets (ignore other settings)
    3. DISTANCE: keepDistance (ranged positioning)
    4. TACTICAL: rePosition (better tile when cornered)
    5. MELEE: chase (close the gap)
    6. FACING: faceMonster (diagonal correction)
    
    INTEGRATIONS:
    - anchor is respected by keepDistance AND rePosition
    - avoidAttacks considers target distance
    - rePosition considers danger zones from monsters
    - All lure features respect killUnder threshold
  ]]
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- PHASE 1: CONTEXT GATHERING
  -- ═══════════════════════════════════════════════════════════════════════════
  
  local creatureHealth = creature:getHealthPercent()
  local killUnder = storage.extras.killUnder or 30
  local targetIsLowHealth = creatureHealth < killUnder
  local isTrapped = isPlayerTrapped(pos)
  
  -- Calculate path distance to creature
  local path = findPath(pos, cpos, 10, {ignoreCreatures = true, ignoreNonPathable = true, ignoreCost = true})
  local pathLen = path and #path or 0
  
  -- Count nearby monsters for lure decisions
  local nearbyMonsterCount = targets  -- Use passed target count
  
  -- Anchor position management (used by keepDistance and rePosition)
  if config.anchor then
    if not anchorPosition or distanceFromPlayer(anchorPosition) > (config.anchorRange or 5) * 2 then
      anchorPosition = pos  -- Set new anchor
    end
  else
    anchorPosition = nil  -- Clear anchor if disabled
  end
  
  -- External data for dynamic lure delay system
  if config.lureMin and config.lureMax and config.dynamicLure then
    targetBotLure = config.lureMin >= targets
    if targets >= config.lureMax then
      targetBotLure = false
    end
  end
  targetCount = targets
  delayValue = config.lureDelay
  lureMax = config.lureMax or 0
  dynamicLureDelay = config.dynamicLureDelay
  delayFrom = config.delayFrom

  -- ═══════════════════════════════════════════════════════════════════════════
  -- PHASE 2: LURE DECISIONS (CaveBot delegation)
  -- These all delegate to CaveBot and return early
  -- CRITICAL: Never trigger if target has low health!
  -- ═══════════════════════════════════════════════════════════════════════════
  
  if not targetIsLowHealth and not isTrapped then
    -- Smart Pull: Pause CaveBot when monster pack is too small but we have targets
    -- This prevents running to next waypoint and losing the respawn
    if config.smartPull then
      local pullRange = config.smartPullRange or 2
      local pullMin = config.smartPullMin or 3
      local pullShape = config.smartPullShape or (nExBot.SHAPE and nExBot.SHAPE.CIRCLE) or 2
      
      local nearbyMonsters
      if getMonstersAdvanced then
        nearbyMonsters = getMonstersAdvanced(pullRange, pullShape)
      else
        nearbyMonsters = getMonsters(pullRange)
      end
      
      -- If we have fewer monsters than minimum, PAUSE waypoint movement
      -- but keep attacking current targets (don't walk to next waypoint!)
      if nearbyMonsters < pullMin then
        -- Signal to CaveBot that smartPull is active (pause waypoints)
        -- But DON'T call allowCaveBot - we want to FIGHT, not walk away
        TargetBot.smartPullActive = true
        
        -- Stay here and fight - don't walk to waypoint
        -- Return nil to continue with normal attack/positioning below
      else
        -- Enough monsters - clear the pause
        TargetBot.smartPullActive = false
      end
    else
      TargetBot.smartPullActive = false
    end
    
    -- Dynamic lure: Pull more monsters when target count is low
    -- Only trigger if smartPull is not pausing us
    if not TargetBot.smartPullActive and TargetBot.canLure() and config.dynamicLure then
      if targetBotLure then
        return TargetBot.allowCaveBot(150)
      end
    end
    
    -- Legacy closeLure support
    if config.closeLure and config.closeLureAmount then
      if getMonsters(1) >= config.closeLureAmount then
        return TargetBot.allowCaveBot(150)
      end
    end
  else
    TargetBot.smartPullActive = false
  end

  -- ═══════════════════════════════════════════════════════════════════════════
  -- PHASE 3: MOVEMENT PRIORITY SYSTEM
  -- ═══════════════════════════════════════════════════════════════════════════
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- PRIORITY 1: SAFETY - Wave attack avoidance
  -- Highest priority - avoid taking damage
  -- ─────────────────────────────────────────────────────────────────────────
  if config.avoidAttacks then
    if avoidWaveAttacks() then
      return true
    end
  end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- PRIORITY 2: SURVIVAL - Kill low-health targets immediately
  -- Override all positioning to finish the kill and get exp
  -- ─────────────────────────────────────────────────────────────────────────
  if targetIsLowHealth and pathLen > 1 then
    -- Ignore keepDistance when target is almost dead
    return TargetBot.walkTo(cpos, 10, {ignoreNonPathable = true, precision = 1})
  end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- PRIORITY 3: DISTANCE - Keep distance mode (ranged combat)
  -- For ranged characters - maintain safe distance from target
  -- Respects anchor if enabled
  -- ─────────────────────────────────────────────────────────────────────────
  if config.keepDistance then
    local keepRange = config.keepDistanceRange or 4
    local currentDist = pathLen
    
    -- Only move if not at correct distance
    if currentDist ~= keepRange and currentDist ~= keepRange + 1 then
      local walkParams = {
        ignoreNonPathable = true,
        marginMin = keepRange,
        marginMax = keepRange + 1
      }
      
      -- Respect anchor constraint
      if config.anchor and anchorPosition then
        walkParams.maxDistanceFrom = {anchorPosition, config.anchorRange or 5}
      end
      
      return TargetBot.walkTo(cpos, 10, walkParams)
    end
    -- At correct distance - fall through to allow rePosition/faceMonster
  end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- PRIORITY 4: TACTICAL - Reposition for better tile
  -- Move to tiles with more escape routes when cornered
  -- Considers: walkable tiles, monster danger zones, target distance, anchor
  -- ─────────────────────────────────────────────────────────────────────────
  if config.rePosition and not isTrapped then
    local currentWalkable = countWalkableTiles(pos)
    local threshold = config.rePositionAmount or 5
    
    if currentWalkable < threshold then
      local result = rePosition(threshold, config)
      if result then return result end
    end
  end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- PRIORITY 5: MELEE - Chase mode
  -- Close the gap to target for melee attacks
  -- Does NOT trigger if keepDistance is enabled (handled above)
  -- ─────────────────────────────────────────────────────────────────────────
  if config.chase and not config.keepDistance and pathLen > 1 then
    local walkParams = {ignoreNonPathable = true, precision = 1}
    
    -- Respect anchor constraint even while chasing
    if config.anchor and anchorPosition then
      walkParams.maxDistanceFrom = {anchorPosition, config.anchorRange or 5}
    end
    
    return TargetBot.walkTo(cpos, 10, walkParams)
  end
  
  -- ─────────────────────────────────────────────────────────────────────────
  -- PRIORITY 6: FACING - Face monster for diagonal correction
  -- Only when adjacent and diagonal - move to cardinal position
  -- Lowest movement priority - only if nothing else needs to move
  -- ─────────────────────────────────────────────────────────────────────────
  if config.faceMonster then
    local dx = cpos.x - pos.x
    local dy = cpos.y - pos.y
    local dist = math.max(math.abs(dx), math.abs(dy))
    
    -- Only handle adjacent diagonal cases
    if dist == 1 and math.abs(dx) == 1 and math.abs(dy) == 1 then
      -- Try to move to cardinal direction from monster
      local candidates = {
        {x = pos.x + dx, y = pos.y, z = pos.z},  -- Move horizontally
        {x = pos.x, y = pos.y + dy, z = pos.z}   -- Move vertically
      }
      
      for i = 1, 2 do
        local tile = g_map.getTile(candidates[i])
        local shouldSkip = false
        
        if tile and tile:isWalkable() and not tile:hasCreature() then
          -- Check anchor constraint
          if config.anchor and anchorPosition then
            local anchorDist = math.max(
              math.abs(candidates[i].x - anchorPosition.x),
              math.abs(candidates[i].y - anchorPosition.y)
            )
            if anchorDist > (config.anchorRange or 5) then
              shouldSkip = true  -- Skip this candidate, violates anchor
            end
          end
          
          if not shouldSkip then
            return TargetBot.walkTo(candidates[i], 2, {ignoreNonPathable = true})
          end
        end
      end
    elseif dist <= 1 then
      -- Just face the monster (no movement needed)
      local dir = player:getDirection()
      if dx == 1 and dir ~= 1 then turn(1)
      elseif dx == -1 and dir ~= 3 then turn(3)
      elseif dy == 1 and dir ~= 2 then turn(2)
      elseif dy == -1 and dir ~= 0 then turn(0)
      end
    end
  end
end

onPlayerPositionChange(function(newPos, oldPos)
  if CaveBot.isOff() then return end
  if TargetBot.isOff() then return end
  if not lureMax then return end
  if storage.TargetBotDelayWhenPlayer then return end
  if not dynamicLureDelay then return end

  local targetThreshold = delayFrom or lureMax * 0.5
  if targetCount < targetThreshold or not target() then return end
  CaveBot.delay(delayValue or 0)
end)