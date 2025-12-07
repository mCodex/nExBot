--[[
  CaveBot Walking Module - DASH Speed Optimized
  
  Uses direct arrow key simulation for maximum walking speed.
  Falls back to pathfinding only when DASH fails (blocked tiles).
]]

local isWalking = false
local walkDelay = 10

-- Pre-computed direction lookup table for faster direction calculation
local DIR_LOOKUP = {
  [-1] = { [-1] = NorthWest, [0] = North, [1] = NorthEast },
  [0]  = { [-1] = West, [0] = 8, [1] = East },
  [1]  = { [-1] = SouthWest, [0] = South, [1] = SouthEast }
}

CaveBot.resetWalking = function()
  isWalking = false
end

-- Check if cavebot is currently in walking state
-- Returns true if walking (prevents action execution), false otherwise
CaveBot.doWalking = function()
  return isWalking
end

-- Called when player position changes (step confirmed by server)
onPlayerPositionChange(function(newPos, oldPos)
  if not oldPos or not newPos then return end
  if not isWalking then return end
  
  local dy = newPos.y - oldPos.y
  local dx = newPos.x - oldPos.x
  
  local dir = 8
  if dy >= -1 and dy <= 1 and dx >= -1 and dx <= 1 then
    local row = DIR_LOOKUP[dy]
    if row then
      dir = row[dx] or 8
    end
  end

  local stepDuration = player:getStepDuration(false, dir)
  CaveBot.delay(walkDelay + stepDuration)
end)

-- Main walking function using DASH mode
CaveBot.walkTo = function(dest, maxDist, params)
  local playerPos = player:getPosition()
  
  -- DASH MODE: Use direct walking for maximum speed
  if DashWalk and DashWalk.walkTo then
    local precision = params and params.precision or 0
    if DashWalk.walkTo(dest, precision) then
      isWalking = true
      local stepDuration = player:getStepDuration(false, 0)
      CaveBot.delay(walkDelay + stepDuration)
      return true
    end
  end
  
  -- Fallback: Use pathfinding when DASH fails (blocked, complex routes)
  local path = getPath(playerPos, dest, maxDist, params)
  
  if not path or not path[1] then
    if CaveBot.Tools and CaveBot.Tools.handleObstacle(dest) then
      return true
    end
    return false
  end
  
  local dir = path[1]
  local stepDuration = player:getStepDuration(false, dir)
  
  g_game.walk(dir, false)
  isWalking = true
  CaveBot.delay(walkDelay + stepDuration)
  return true
end
