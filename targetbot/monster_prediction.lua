--[[
  Monster Prediction Module - Extracted from monster_ai.lua
  
  Single Responsibility: Predict monster behavior and attack timing.
  
  This module handles:
  - Wave/beam attack prediction
  - Position danger assessment
  - Direction-based threat detection
  - Attack arc calculations
  
  Depends on: monster_tracking.lua, directions.lua
  Used by: creature_position.lua, target.lua
]]

-- ============================================================================
-- MODULE NAMESPACE
-- ============================================================================

local MonsterPrediction = {}
MonsterPrediction.VERSION = "1.0"

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

MonsterPrediction.CONFIG = {
  -- Prediction confidence thresholds
  CONFIDENCE = {
    VERY_HIGH = 0.85,
    HIGH = 0.70,
    MEDIUM = 0.50,
    LOW = 0.30,
    VERY_LOW = 0.15
  },
  
  -- Timing thresholds
  IMMEDIATE_THREAT_WINDOW = 800,    -- ms before predicted attack
  ATTACK_PREDICTION_HORIZON = 2000, -- ms ahead to predict
  FACING_PLAYER_THRESHOLD = 0.6,    -- Confidence for "facing player"
  DIRECTION_CHANGE_COOLDOWN = 150,  -- ms between direction processing
  CONSECUTIVE_TURNS_ALERT = 2,      -- Quick turns to trigger alert
}

-- ============================================================================
-- TIME HELPER (use ClientHelper for DRY)
-- ============================================================================

local nowMs = ClientHelper and ClientHelper.nowMs or function()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

-- ============================================================================
-- DIRECTION VECTORS
-- ============================================================================

local DIR_VECTORS = {
  [0] = {x = 0, y = -1},   -- North
  [1] = {x = 1, y = -1},   -- NorthEast
  [2] = {x = 1, y = 0},    -- East
  [3] = {x = 1, y = 1},    -- SouthEast
  [4] = {x = 0, y = 1},    -- South
  [5] = {x = -1, y = 1},   -- SouthWest
  [6] = {x = -1, y = 0},   -- West
  [7] = {x = -1, y = -1}   -- NorthWest
}

-- ============================================================================
-- CORE PREDICTION FUNCTIONS
-- ============================================================================

--[[
  Check if a monster is facing a target position
  @param monsterPos Position of the monster
  @param direction Direction the monster is facing (0-7)
  @param targetPos Position to check
  @param tolerance Angular tolerance (default 1 = 45 degrees)
  @return boolean, number (isFacing, angle)
]]
function MonsterPrediction.isFacingPosition(monsterPos, direction, targetPos, tolerance)
  if not monsterPos or not targetPos then return false, 0 end
  tolerance = tolerance or 1
  
  local dx = targetPos.x - monsterPos.x
  local dy = targetPos.y - monsterPos.y
  
  if dx == 0 and dy == 0 then
    return true, 0  -- Same position
  end
  
  -- Calculate angle to target (0-7 direction scale)
  local angle = math.atan2(dy, dx)
  local targetDir = math.floor((angle + math.pi) / (math.pi / 4)) % 8
  
  -- Convert to match OTClient direction system
  -- OTClient: 0=N, 1=E, 2=S, 3=W, 4=NE, 5=SE, 6=SW, 7=NW
  local dirMapping = {
    [0] = 2,   -- East -> 2
    [1] = 5,   -- SouthEast -> 5
    [2] = 4,   -- South -> 4
    [3] = 6,   -- SouthWest -> 6
    [4] = 6,   -- West -> 6
    [5] = 7,   -- NorthWest -> 7
    [6] = 0,   -- North -> 0
    [7] = 1    -- NorthEast -> 1
  }
  
  targetDir = dirMapping[targetDir] or 0
  
  -- Check if direction matches within tolerance
  local diff = math.abs(direction - targetDir)
  if diff > 4 then diff = 8 - diff end
  
  return diff <= tolerance, diff
end

--[[
  Check if a position is within a wave/beam attack path
  @param pos Position to check
  @param monsterPos Monster's position
  @param direction Monster's facing direction
  @param range Wave attack range
  @param width Wave width (0 = single tile, 1 = 3 tiles wide, etc.)
  @return boolean
]]
function MonsterPrediction.isPositionInWavePath(pos, monsterPos, direction, range, width)
  if not pos or not monsterPos then return false end
  
  range = range or 5
  width = width or 1
  
  local dirVec = DIR_VECTORS[direction]
  if not dirVec then return false end
  
  -- Check if position is in front of monster
  local dx = pos.x - monsterPos.x
  local dy = pos.y - monsterPos.y
  
  -- Distance along attack direction
  local alongDist = dx * dirVec.x + dy * dirVec.y
  if alongDist <= 0 or alongDist > range then
    return false  -- Behind or too far
  end
  
  -- Perpendicular distance (how far off the center line)
  local perpDist = math.abs(dx * (-dirVec.y) + dy * dirVec.x)
  
  return perpDist <= width
end

--[[
  Get tiles in a wave attack path
  @param monsterPos Monster's position
  @param direction Monster's facing direction
  @param range Wave attack range
  @param width Wave width
  @return array of positions
]]
function MonsterPrediction.getWavePathTiles(monsterPos, direction, range, width)
  if not monsterPos then return {} end
  
  range = range or 5
  width = width or 1
  
  local dirVec = DIR_VECTORS[direction]
  if not dirVec then return {} end
  
  local tiles = {}
  
  -- Get perpendicular vector
  local perpX, perpY = -dirVec.y, dirVec.x
  
  -- Generate all tiles in the wave path
  for dist = 1, range do
    local centerX = monsterPos.x + dirVec.x * dist
    local centerY = monsterPos.y + dirVec.y * dist
    
    for offset = -width, width do
      tiles[#tiles + 1] = {
        x = centerX + perpX * offset,
        y = centerY + perpY * offset,
        z = monsterPos.z
      }
    end
  end
  
  return tiles
end

--[[
  Calculate time until next predicted wave attack
  @param trackingData Monster tracking data (from monster_tracking.lua)
  @param patternData Monster pattern data (known behavior)
  @return number (ms until attack, 0 if imminent, -1 if unknown)
]]
function MonsterPrediction.getTimeToNextWave(trackingData, patternData)
  if not trackingData then return -1 end
  
  local nowt = nowMs()
  local cooldown = trackingData.ewmaCooldown or (patternData and patternData.waveCooldown) or 2000
  local lastWave = trackingData.lastWaveTime or 0
  
  if lastWave == 0 then
    return -1  -- Never observed a wave
  end
  
  local elapsed = nowt - lastWave
  local remaining = cooldown - elapsed
  
  return math.max(0, remaining)
end

--[[
  Get threat level from a monster
  @param trackingData Monster tracking data
  @param patternData Monster pattern data
  @param playerPos Player's current position
  @return number (0-1 threat level), table (threat details)
]]
function MonsterPrediction.getThreatLevel(trackingData, patternData, playerPos)
  if not trackingData or not playerPos then
    return 0, nil
  end
  
  local threat = 0
  local details = {
    isFacing = false,
    timeToAttack = -1,
    distance = 99,
    confidence = 0
  }
  
  local monsterPos = trackingData.lastPosition
  if not monsterPos or monsterPos.z ~= playerPos.z then
    return 0, details
  end
  
  -- Distance factor
  local dist = math.max(
    math.abs(monsterPos.x - playerPos.x),
    math.abs(monsterPos.y - playerPos.y)
  )
  details.distance = dist
  
  if dist > 7 then
    return 0, details  -- Too far
  end
  
  -- Facing factor
  local isFacing, angleDiff = MonsterPrediction.isFacingPosition(
    monsterPos, 
    trackingData.lastDirection, 
    playerPos
  )
  details.isFacing = isFacing
  
  if isFacing then
    threat = threat + 0.4
    
    -- Time to attack factor
    local timeToAttack = MonsterPrediction.getTimeToNextWave(trackingData, patternData)
    details.timeToAttack = timeToAttack
    
    if timeToAttack >= 0 and timeToAttack < MonsterPrediction.CONFIG.IMMEDIATE_THREAT_WINDOW then
      threat = threat + 0.4 * (1 - timeToAttack / MonsterPrediction.CONFIG.IMMEDIATE_THREAT_WINDOW)
    end
    
    -- In wave path factor
    local range = patternData and patternData.waveRange or 5
    local width = patternData and patternData.waveWidth or 1
    
    if MonsterPrediction.isPositionInWavePath(playerPos, monsterPos, trackingData.lastDirection, range, width) then
      threat = threat + 0.2
    end
  end
  
  -- Distance factor (closer = more dangerous)
  threat = threat + (0.2 * (1 - dist / 7))
  
  -- Confidence from tracking data
  details.confidence = trackingData.confidence or 0.1
  
  return math.min(1, threat), details
end

--[[
  Find safe tile to escape from wave attack
  @param playerPos Player's current position
  @param monsterPos Monster's position
  @param direction Monster's facing direction
  @param patternData Monster pattern data
  @return Position (safe tile) or nil
]]
function MonsterPrediction.findSafeTile(playerPos, monsterPos, direction, patternData)
  if not playerPos or not monsterPos then return nil end
  
  local range = patternData and patternData.waveRange or 5
  local width = patternData and patternData.waveWidth or 1
  
  local dirVec = DIR_VECTORS[direction] or {x = 0, y = 0}
  
  -- Get perpendicular directions (safe directions)
  local perpX, perpY = -dirVec.y, dirVec.x
  
  local candidates = {}
  
  -- Check perpendicular tiles
  for dist = 1, 2 do
    for _, mult in ipairs({1, -1}) do
      local tile = {
        x = playerPos.x + perpX * dist * mult,
        y = playerPos.y + perpY * dist * mult,
        z = playerPos.z
      }
      
      if not MonsterPrediction.isPositionInWavePath(tile, monsterPos, direction, range, width) then
        -- Score by distance from monster (further = safer)
        local distFromMonster = math.abs(tile.x - monsterPos.x) + math.abs(tile.y - monsterPos.y)
        candidates[#candidates + 1] = { pos = tile, score = distFromMonster }
      end
    end
  end
  
  -- Also try diagonal escapes
  for dx = -1, 1 do
    for dy = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        local tile = { x = playerPos.x + dx, y = playerPos.y + dy, z = playerPos.z }
        
        if not MonsterPrediction.isPositionInWavePath(tile, monsterPos, direction, range, width) then
          local distFromMonster = math.abs(tile.x - monsterPos.x) + math.abs(tile.y - monsterPos.y)
          candidates[#candidates + 1] = { pos = tile, score = distFromMonster + 0.5 }
        end
      end
    end
  end
  
  -- Sort by score (higher = better)
  table.sort(candidates, function(a, b) return a.score > b.score end)
  
  return candidates[1] and candidates[1].pos or nil
end

--[[
  Predict monster's next position
  @param trackingData Monster tracking data
  @param horizonMs How far ahead to predict (ms)
  @return Position (predicted position) or nil
]]
function MonsterPrediction.predictPosition(trackingData, horizonMs)
  if not trackingData then return nil end
  
  horizonMs = horizonMs or 500
  
  local pos = trackingData.lastPosition
  if not pos then return nil end
  
  -- If monster is stationary, predict same position
  local stationaryRatio = trackingData.stationaryCount / math.max(1, trackingData.movementSamples)
  if stationaryRatio > 0.7 then
    return pos
  end
  
  -- Calculate movement vector from recent samples
  local samples = trackingData.samples
  if not samples or #samples < 2 then return pos end
  
  local oldest = samples[1]
  local newest = samples[#samples]
  
  if not oldest or not newest then return pos end
  
  local dt = (newest.time - oldest.time) / 1000  -- seconds
  if dt <= 0 then return pos end
  
  local dx = (newest.pos.x - oldest.pos.x) / dt
  local dy = (newest.pos.y - oldest.pos.y) / dt
  
  -- Predict future position
  local predictedX = pos.x + dx * (horizonMs / 1000)
  local predictedY = pos.y + dy * (horizonMs / 1000)
  
  return {
    x = math.floor(predictedX + 0.5),
    y = math.floor(predictedY + 0.5),
    z = pos.z
  }
end

--[[
  Get attack danger level for a position (considering all nearby monsters)
  @param position Position to check
  @param monsters Array of monster tracking data
  @param patterns Table of monster patterns
  @return number (0-10 danger level), array of threats
]]
function MonsterPrediction.getPositionDanger(position, monsters, patterns)
  if not position then return 0, {} end
  
  monsters = monsters or {}
  patterns = patterns or {}
  
  local totalDanger = 0
  local threats = {}
  
  for id, data in pairs(monsters) do
    local patternData = patterns[data.name and data.name:lower()] or {}
    local threat, details = MonsterPrediction.getThreatLevel(data, patternData, position)
    
    if threat > 0 then
      totalDanger = totalDanger + threat * 2  -- Scale to 0-10
      
      if threat > 0.3 then
        threats[#threats + 1] = {
          id = id,
          name = data.name,
          threat = threat,
          details = details
        }
      end
    end
  end
  
  return math.min(10, totalDanger), threats
end

--[[
  Check if immediate threat exists (any monster about to attack)
  @param monsters Table of monster tracking data
  @param patterns Table of monster patterns
  @param playerPos Player's position
  @return boolean, table (immediateThreat, details)
]]
function MonsterPrediction.hasImmediateThreat(monsters, patterns, playerPos)
  if not playerPos then return false, nil end
  
  monsters = monsters or {}
  patterns = patterns or {}
  
  for id, data in pairs(monsters) do
    local patternData = patterns[data.name and data.name:lower()] or {}
    local threat, details = MonsterPrediction.getThreatLevel(data, patternData, playerPos)
    
    if threat >= 0.6 then
      local timeToAttack = details and details.timeToAttack or -1
      
      if timeToAttack >= 0 and timeToAttack < MonsterPrediction.CONFIG.IMMEDIATE_THREAT_WINDOW then
        return true, {
          monster = data,
          timeToAttack = timeToAttack,
          threat = threat,
          details = details
        }
      end
    end
  end
  
  return false, nil
end

return MonsterPrediction
