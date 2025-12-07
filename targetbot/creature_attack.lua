local targetBotLure = false
local targetCount = 0 
local delayValue = 0
local lureMax = 0
local anchorPosition = nil
local lastCall = now
local delayFrom = nil
local dynamicLureDelay = false

-- Pre-computed direction offsets
local WALK_DIRS = {{-1,1}, {0,1}, {1,1}, {-1, 0}, {1, 0}, {-1, -1}, {0, -1}, {1, -1}}
local WALK_DIRS_COUNT = 8

-- Reusable position table for walkable tile checks (PERFORMANCE: avoid table allocation)
local walkCheckPos = { x = 0, y = 0, z = 0 }
local dangerCheckPos = { x = 0, y = 0, z = 0 }

--------------------------------------------------------------------------------
-- Advanced Wave/Area Attack Avoidance System
-- Analyzes monster positions and predicts dangerous tiles based on:
-- 1. Wave attacks (length + spread) - cone/beam shaped
-- 2. Area attacks (radius) - circular AoE
-- 3. Multiple monster threat zones
--------------------------------------------------------------------------------

-- Direction vectors for 8-directional monster facing
local DIRECTION_VECTORS = {
  [0] = {x = 0, y = -1},  -- North
  [1] = {x = 1, y = 0},   -- East
  [2] = {x = 0, y = 1},   -- South
  [3] = {x = -1, y = 0},  -- West
  [4] = {x = 1, y = -1},  -- NorthEast
  [5] = {x = 1, y = 1},   -- SouthEast
  [6] = {x = -1, y = 1},  -- SouthWest
  [7] = {x = -1, y = -1}  -- NorthWest
}

-- Common wave attack parameters (derived from monster data analysis)
-- Most monsters use: length 4-8, spread 0-4
local DEFAULT_WAVE_LENGTH = 8
local DEFAULT_WAVE_SPREAD = 3
local DEFAULT_AREA_RADIUS = 4

-- Cache for danger calculations (reset each tick)
local dangerCache = {}
local dangerCacheTime = 0
local DANGER_CACHE_TTL = 100  -- 100ms cache

-- Check if a position is in a wave attack path
-- Wave attacks form a cone from monster position in its facing direction
-- @param playerPos: player position
-- @param monsterPos: monster position  
-- @param monsterDir: monster facing direction (0-7)
-- @param waveLength: how far the wave extends
-- @param waveSpread: how wide the cone spreads (0 = beam, 1-4 = cone)
-- @return boolean: true if position is in danger zone
local function isInWavePath(playerPos, monsterPos, monsterDir, waveLength, waveSpread)
  waveLength = waveLength or DEFAULT_WAVE_LENGTH
  waveSpread = waveSpread or DEFAULT_WAVE_SPREAD
  
  local dirVec = DIRECTION_VECTORS[monsterDir]
  if not dirVec then return false end
  
  -- Calculate relative position from monster to player
  local dx = playerPos.x - monsterPos.x
  local dy = playerPos.y - monsterPos.y
  
  -- Distance check (must be within wave length)
  local distance = math.max(math.abs(dx), math.abs(dy))
  if distance > waveLength or distance == 0 then
    return false
  end
  
  -- For straight beams (spread = 0)
  if waveSpread == 0 then
    -- Check if player is directly in line with monster's facing
    if dirVec.x ~= 0 and dirVec.y == 0 then
      -- East/West facing
      return dy == 0 and (dx * dirVec.x > 0)
    elseif dirVec.y ~= 0 and dirVec.x == 0 then
      -- North/South facing
      return dx == 0 and (dy * dirVec.y > 0)
    else
      -- Diagonal facing
      return (dx * dirVec.x > 0 and dy * dirVec.y > 0 and math.abs(dx) == math.abs(dy))
    end
  end
  
  -- For cone attacks (spread > 0)
  -- Calculate if player is within the cone angle
  local inCorrectDirection = false
  
  if dirVec.x == 0 then
    -- North or South
    inCorrectDirection = (dy * dirVec.y > 0)
  elseif dirVec.y == 0 then
    -- East or West
    inCorrectDirection = (dx * dirVec.x > 0)
  else
    -- Diagonal
    inCorrectDirection = (dx * dirVec.x >= 0 and dy * dirVec.y >= 0)
  end
  
  if not inCorrectDirection then
    return false
  end
  
  -- Check spread width at the player's distance
  -- Spread expands proportionally with distance
  local spreadAtDistance = math.floor(waveSpread * distance / waveLength) + 1
  
  -- Calculate perpendicular distance from the center line
  local perpDistance
  if dirVec.x == 0 then
    perpDistance = math.abs(dx)
  elseif dirVec.y == 0 then
    perpDistance = math.abs(dy)
  else
    -- For diagonal, use the minimum deviation
    perpDistance = math.min(math.abs(math.abs(dx) - math.abs(dy)), 
                           math.max(math.abs(dx), math.abs(dy)) - math.min(math.abs(dx), math.abs(dy)))
  end
  
  return perpDistance <= spreadAtDistance
end

-- Check if a position is in an area attack radius
-- @param playerPos: position to check
-- @param centerPos: center of the area attack
-- @param radius: attack radius
-- @return boolean: true if position is in danger zone
local function isInAreaRadius(playerPos, centerPos, radius)
  radius = radius or DEFAULT_AREA_RADIUS
  local dx = math.abs(playerPos.x - centerPos.x)
  local dy = math.abs(playerPos.y - centerPos.y)
  return dx <= radius and dy <= radius
end

-- Calculate danger score for a position based on all nearby monsters
-- Higher score = more dangerous
-- @param pos: position to evaluate
-- @param monsters: table of monster creatures
-- @return number: danger score (0 = safe)
local function calculateDangerScore(pos, monsters)
  local score = 0
  local posX, posY = pos.x, pos.y
  
  for i = 1, #monsters do
    local monster = monsters[i]
    if monster and not monster:isDead() then
      local mpos = monster:getPosition()
      
      -- PERFORMANCE: Early exit for distant monsters
      local dx = math.abs(posX - mpos.x)
      local dy = math.abs(posY - mpos.y)
      local distance = math.max(dx, dy)
      
      if distance <= DEFAULT_WAVE_LENGTH + 1 then
        local mdir = monster:getDirection()
        
        -- Wave attack danger (highest priority)
        if isInWavePath(pos, mpos, mdir, DEFAULT_WAVE_LENGTH, DEFAULT_WAVE_SPREAD) then
          -- Closer = more dangerous, facing directly = most dangerous
          score = score + 100 + (DEFAULT_WAVE_LENGTH - distance) * 10
        end
        
        -- Area attack danger around monster
        if distance <= DEFAULT_AREA_RADIUS then
          score = score + 50 + (DEFAULT_AREA_RADIUS - distance) * 5
        end
        
        -- Adjacent tiles are most dangerous (melee + immediate wave)
        if distance == 1 then
          score = score + 75
        end
      end
    end
  end
  
  return score
end

-- Get all monsters in range
-- @param range: search range
-- @return table: list of monster creatures
local function getMonstersInRange(range)
  range = range or 10
  local pos = player:getPosition()
  local creatures = g_map.getSpectatorsInRange(pos, false, range, range)
  local monsters = {}
  local count = 0
  
  for i = 1, #creatures do
    local c = creatures[i]
    if c:isMonster() and not c:isDead() then
      count = count + 1
      monsters[count] = c
    end
  end
  
  return monsters
end

-- Find the safest adjacent tile to move to
-- @param monsters: optional pre-fetched monster list
-- @return position or nil: safest tile position, or nil if current is safest
local function findSafestTile(monsters)
  monsters = monsters or getMonstersInRange(10)
  
  if #monsters == 0 then
    return nil
  end
  
  local pos = player:getPosition()
  local currentDanger = calculateDangerScore(pos, monsters)
  
  -- If we're safe, don't move
  if currentDanger == 0 then
    return nil
  end
  
  local bestPos = nil
  local bestScore = currentDanger
  local candidates = {}
  local candidateCount = 0
  
  -- PERFORMANCE: Reuse position table instead of creating new ones
  -- Check all adjacent tiles
  for i = 1, WALK_DIRS_COUNT do
    local dir = WALK_DIRS[i]
    dangerCheckPos.x = pos.x - dir[1]
    dangerCheckPos.y = pos.y - dir[2]
    dangerCheckPos.z = pos.z
    
    local tile = g_map.getTile(dangerCheckPos)
    if tile and tile:isWalkable() and not tile:hasCreature() then
      local score = calculateDangerScore(dangerCheckPos, monsters)
      
      -- Prefer tiles that are safer
      if score < bestScore then
        bestScore = score
        -- Need to copy position since we're reusing dangerCheckPos
        bestPos = {x = dangerCheckPos.x, y = dangerCheckPos.y, z = dangerCheckPos.z}
      end
      
      -- Collect all safe candidates for secondary sorting
      if score == 0 then
        candidateCount = candidateCount + 1
        candidates[candidateCount] = {
          pos = {x = dangerCheckPos.x, y = dangerCheckPos.y, z = dangerCheckPos.z}, 
          score = score
        }
      end
    end
  end
  
  -- If we have multiple safe tiles, prefer ones that maintain attack range
  if candidateCount > 1 and target() then
    local targetPos = target():getPosition()
    local currentTargetDist = getDistanceBetween(pos, targetPos)
    
    for i = 1, candidateCount do
      local c = candidates[i]
      local newDist = getDistanceBetween(c.pos, targetPos)
      -- Prefer tiles that keep us at similar range to target
      if math.abs(newDist - currentTargetDist) < math.abs(getDistanceBetween(bestPos, targetPos) - currentTargetDist) then
        bestPos = c.pos
      end
    end
  end
  
  return bestPos
end

-- Main function to avoid wave attacks
-- Called from creature walk function
-- @return boolean: true if an avoidance move was made
local function avoidWaveAttacks()
  -- Use cached result if available
  if now - dangerCacheTime < DANGER_CACHE_TTL then
    if dangerCache.safePos then
      return TargetBot.walkTo(dangerCache.safePos, 2, {ignoreNonPathable=true})
    end
    return false
  end
  
  local monsters = getMonstersInRange(10)
  local safePos = findSafestTile(monsters)
  
  -- Update cache
  dangerCacheTime = now
  dangerCache.safePos = safePos
  
  if safePos then
    return TargetBot.walkTo(safePos, 2, {ignoreNonPathable=true})
  end
  
  return false
end

-- Export for external use
nExBot.avoidWaveAttacks = avoidWaveAttacks
nExBot.findSafestTile = findSafestTile
nExBot.calculateDangerScore = calculateDangerScore
nExBot.isInWavePath = isInWavePath
nExBot.isInAreaRadius = isInAreaRadius

function getWalkableTilesCount(position)
  local count = 0
  local tiles = getNearTiles(position)
  
  for i = 1, #tiles do
    local tile = tiles[i]
    if tile:isWalkable() or tile:hasCreature() then
      count = count + 1
    end
  end

  return count
end

function rePosition(minTiles)
  minTiles = minTiles or 8
  local currentTime = now
  if currentTime - lastCall < 500 then return end
  
  local pPos = player:getPosition()
  local playerTilesCount = getWalkableTilesCount(pPos)
  
  if playerTilesCount > minTiles then return end
  
  local tiles = getNearTiles(pPos)
  local best = playerTilesCount
  local target = nil
  
  for i = 1, #tiles do
    local tile = tiles[i]
    if not tile:hasCreature() and tile:isWalkable() then
      local tilePos = tile:getPosition()
      local tileCount = getWalkableTilesCount(tilePos)
      if tileCount > best then
        best = tileCount
        target = tilePos
      end
    end
  end

  if target then
    lastCall = currentTime
    return CaveBot.GoTo(target, 0)
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
  
  -- Optimized trapped check with early exit
  local isTrapped = true
  local posX, posY, posZ = pos.x, pos.y, pos.z
  
  for i = 1, WALK_DIRS_COUNT do
    local dir = WALK_DIRS[i]
    walkCheckPos.x = posX - dir[1]
    walkCheckPos.y = posY - dir[2]
    walkCheckPos.z = posZ
    
    local tile = g_map.getTile(walkCheckPos)
    if tile and tile:isWalkable(false) then
      isTrapped = false
      break  -- Early exit once we find one walkable tile
    end
  end

  -- data for external dynamic lure
  if config.lureMin and config.lureMax and config.dynamicLure then
    if config.lureMin >= targets then
      targetBotLure = true
    elseif targets >= config.lureMax then
      targetBotLure = false
    end
  end
  targetCount = targets
  delayValue = config.lureDelay

  if config.lureMax then
    lureMax = config.lureMax
  end

  dynamicLureDelay = config.dynamicLureDelay
  delayFrom = config.delayFrom

  -- Smart Pull system: Use CaveBot to pull more monsters when pack is below threshold
  -- This replaces the old closeLure system with a more intelligent algorithm
  if config.smartPull then
    local pullRange = config.smartPullRange or 2
    local pullMin = config.smartPullMin or 3
    local nearbyMonsters = getMonsters(pullRange)
    
    -- If we have fewer monsters in close range than the threshold, use CaveBot to pull more
    if nearbyMonsters < pullMin then
      return TargetBot.allowCaveBot(150)
    end
  end
  
  -- Legacy closeLure support (for backward compatibility with old configs)
  if config.closeLure and config.closeLureAmount and config.closeLureAmount <= getMonsters(1) then
    return TargetBot.allowCaveBot(150)
  end
  
  local creatureHealth = creature:getHealthPercent()
  local killUnder = storage.extras.killUnder or 30
  
  -- Dynamic lure: Use CaveBot when we need more monsters
  if TargetBot.canLure() and config.dynamicLure and creatureHealth >= killUnder and not isTrapped then
    if targetBotLure then
      anchorPosition = nil
      return TargetBot.allowCaveBot(150)
    end
  end

  local currentDistance = findPath(pos, cpos, 10, {ignoreCreatures=true, ignoreNonPathable=true, ignoreCost=true})
  local currentDistLen = currentDistance and #currentDistance or 0
  
  if (not config.chase or currentDistLen == 1) and not config.avoidAttacks and not config.keepDistance and config.rePosition and creatureHealth >= killUnder then
    return rePosition(config.rePositionAmount or 6)
  end
  
  if ((killUnder > 1 and creatureHealth < killUnder) or config.chase) and not config.keepDistance then
    if currentDistLen > 1 then
      return TargetBot.walkTo(cpos, 10, {ignoreNonPathable=true, precision=1})
    end
  elseif config.keepDistance then
    if not anchorPosition or distanceFromPlayer(anchorPosition) > config.anchorRange then
      anchorPosition = pos
    end
    
    local keepRange = config.keepDistanceRange
    if currentDistLen ~= keepRange and currentDistLen ~= keepRange + 1 then
      if config.anchor and anchorPosition and getDistanceBetween(pos, anchorPosition) <= config.anchorRange * 2 then
        return TargetBot.walkTo(cpos, 10, {ignoreNonPathable=true, marginMin=keepRange, marginMax=keepRange + 1, maxDistanceFrom={anchorPosition, config.anchorRange}})
      else
        return TargetBot.walkTo(cpos, 10, {ignoreNonPathable=true, marginMin=keepRange, marginMax=keepRange + 1})
      end
    end
  end

  -- Advanced wave/area attack avoidance
  if config.avoidAttacks then
    -- Use the new intelligent avoidance system
    local avoidResult = avoidWaveAttacks()
    if avoidResult then
      return avoidResult
    end
  elseif config.faceMonster then
    local diffx = cpos.x - pos.x
    local diffy = cpos.y - pos.y
    local candidates = {}
    
    if diffx == 1 and diffy == 1 then
      candidates = {{x=pos.x+1, y=pos.y, z=pos.z}, {x=pos.x, y=pos.y-1, z=pos.z}}
    elseif diffx == -1 and diffy == 1 then
      candidates = {{x=pos.x-1, y=pos.y, z=pos.z}, {x=pos.x, y=pos.y-1, z=pos.z}}
    elseif diffx == -1 and diffy == -1 then
      candidates = {{x=pos.x, y=pos.y-1, z=pos.z}, {x=pos.x-1, y=pos.y, z=pos.z}} 
    elseif diffx == 1 and diffy == -1 then
      candidates = {{x=pos.x, y=pos.y-1, z=pos.z}, {x=pos.x+1, y=pos.y, z=pos.z}}       
    else
      local dir = player:getDirection()
      if diffx == 1 and dir ~= 1 then turn(1)
      elseif diffx == -1 and dir ~= 3 then turn(3)
      elseif diffy == 1 and dir ~= 2 then turn(2)
      elseif diffy == -1 and dir ~= 0 then turn(0)
      end
    end
    
    for i = 1, #candidates do
      local candidate = candidates[i]
      local tile = g_map.getTile(candidate)
      if tile and tile:isWalkable() then
        return TargetBot.walkTo(candidate, 2, {ignoreNonPathable=true})
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