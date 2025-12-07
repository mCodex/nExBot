-- walking - optimized version with better path caching and reduced overhead
local expectedDirs = {}
local isWalking = false
local walkPath = {}
local walkPathIter = 0

-- Cache for config values to reduce function call overhead
local configCache = {
  mapClick = false,
  walkDelay = 10,
  mapClickDelay = 100,
  ping = 100,
  lastUpdate = 0
}

-- Update config cache every 500ms instead of every call
local function updateConfigCache()
  local currentTime = now
  if currentTime - configCache.lastUpdate > 500 then
    configCache.mapClick = CaveBot.Config.get("mapClick")
    configCache.walkDelay = CaveBot.Config.get("walkDelay")
    configCache.mapClickDelay = CaveBot.Config.get("mapClickDelay")
    configCache.ping = CaveBot.Config.get("ping")
    configCache.lastUpdate = currentTime
  end
end

-- Pre-computed direction lookup table for faster direction calculation
local DIR_LOOKUP = {
  [-1] = { [-1] = NorthWest, [0] = North, [1] = NorthEast },
  [0]  = { [-1] = West, [0] = 8, [1] = East },
  [1]  = { [-1] = SouthWest, [0] = South, [1] = SouthEast }
}

CaveBot.resetWalking = function()
  expectedDirs = {}
  walkPath = {}
  walkPathIter = 0
  isWalking = false
end

CaveBot.doWalking = function()
  updateConfigCache()
  
  if configCache.mapClick then
    return false
  end
  
  local expectedCount = #expectedDirs
  if expectedCount == 0 then
    return false
  end
  
  -- Reset if too many pending directions (stuck detection)
  if expectedCount >= 3 then
    CaveBot.resetWalking()
    return false
  end
  
  local dir = walkPath[walkPathIter]
  if dir then
    g_game.walk(dir, false)
    expectedDirs[expectedCount + 1] = dir  -- Direct index assignment is faster than table.insert
    walkPathIter = walkPathIter + 1
    CaveBot.delay(configCache.walkDelay + player:getStepDuration(false, dir))
    return true
  end
  return false  
end

-- called when player position has been changed (step has been confirmed by server)
onPlayerPositionChange(function(newPos, oldPos)
  if not oldPos or not newPos then return end
  
  -- Use lookup table instead of nested table access
  local dy = newPos.y - oldPos.y
  local dx = newPos.x - oldPos.x
  
  local dir = 8 -- Default invalid direction
  if dy >= -1 and dy <= 1 and dx >= -1 and dx <= 1 then
    local row = DIR_LOOKUP[dy]
    if row then
      dir = row[dx] or 8
    end
  end

  local stepDuration = player:getStepDuration(false, dir)
  
  if not isWalking or not expectedDirs[1] then
    -- some other walk action is taking place (for example use on ladder), wait
    walkPath = {}
    CaveBot.delay(configCache.ping + stepDuration + 150)
    return
  end
  
  if expectedDirs[1] ~= dir then
    local delayTime = configCache.mapClick and configCache.walkDelay or configCache.mapClickDelay
    CaveBot.delay(delayTime + stepDuration)
    return
  end
  
  -- Faster removal of first element using table manipulation
  local count = #expectedDirs
  if count > 1 then
    for i = 1, count - 1 do
      expectedDirs[i] = expectedDirs[i + 1]
    end
  end
  expectedDirs[count] = nil
  
  if configCache.mapClick and #expectedDirs > 0 then
    CaveBot.delay(configCache.mapClickDelay + stepDuration)
  end
end)

CaveBot.walkTo = function(dest, maxDist, params)
  updateConfigCache()
  
  local playerPos = player:getPosition()
  local path = getPath(playerPos, dest, maxDist, params)
  
  if not path or not path[1] then
    return false
  end
  
  local dir = path[1]
  local stepDuration = player:getStepDuration(false, dir)
  
  if configCache.mapClick then
    local ret = autoWalk(path)
    if ret then
      isWalking = true
      expectedDirs = path
      local delayTime = configCache.mapClickDelay + math.max(configCache.ping + stepDuration, stepDuration * 2)
      CaveBot.delay(delayTime)
    end
    return ret
  end
  
  g_game.walk(dir, false)
  isWalking = true    
  walkPath = path
  walkPathIter = 2
  expectedDirs = { dir }
  CaveBot.delay(configCache.walkDelay + stepDuration)
  return true
end
