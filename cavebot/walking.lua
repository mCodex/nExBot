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

-- Main walking function - DASH mode with autoWalk fallback
CaveBot.walkTo = function(dest, maxDist, params)
  local precision = params and params.precision or 1
  
  -- DASH MODE: Use direct walking for maximum speed (works for adjacent tiles)
  if DashWalk and DashWalk.walkTo then
    if DashWalk.walkTo(dest, precision) then
      isWalking = true
      CaveBot.delay(walkDelay + player:getStepDuration(false, 0))
      return true
    end
  end
  
  -- FALLBACK: Use autoWalk for longer distances or when DASH fails
  if autoWalk(dest, maxDist or 20, {
    ignoreNonPathable = params and params.ignoreNonPathable or true,
    precision = precision
  }) then
    isWalking = true
    CaveBot.delay(walkDelay + player:getStepDuration(false, 0))
    return true
  end
  
  -- Try obstacle handler as last resort
  if CaveBot.Tools and CaveBot.Tools.handleObstacle(dest) then
    return true
  end
  
  return false
end
