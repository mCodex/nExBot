--[[
  CaveBot Recorder
  
  Advanced waypoint recording with action detection.
  
  Author: nExBot Team
  Version: 1.0.0
]]

-- Recorder state
local recorderState = {
  enabled = false,
  lastPos = nil,
  lastZ = nil,
  detectedActions = {}
}

-- Action detection patterns
local actionPatterns = {
  -- Rope spots detection
  ropeSpots = {385, 392, 469, 470, 482, 484, 485, 539, 543, 924, 579, 3135, 8932, 3174},
  -- Shovel spots
  shovelSpots = {593, 606, 608, 867, 1066, 3324},
  -- Ladder IDs
  ladders = {1386, 1387, 1388, 1389, 1390, 1472, 1948, 1957, 1968},
  -- Stairs IDs  
  stairs = {1385, 1396, 1399, 1402, 1405, 1474, 1477, 1480, 1490, 1493},
  -- Sewer grates
  sewers = {435, 594, 598}
}

-- Check if tile has specific action
local function detectTileAction(tile)
  if not tile then return nil end
  
  for _, item in ipairs(tile:getItems()) do
    local itemId = item:getId()
    
    -- Check rope spots
    for _, id in ipairs(actionPatterns.ropeSpots) do
      if itemId == id then
        return CaveBot.WaypointTypes.ROPE, item
      end
    end
    
    -- Check shovel spots
    for _, id in ipairs(actionPatterns.shovelSpots) do
      if itemId == id then
        return CaveBot.WaypointTypes.SHOVEL, item
      end
    end
    
    -- Check ladders
    for _, id in ipairs(actionPatterns.ladders) do
      if itemId == id then
        return CaveBot.WaypointTypes.LADDER, item
      end
    end
    
    -- Check stairs
    for _, id in ipairs(actionPatterns.stairs) do
      if itemId == id then
        return CaveBot.WaypointTypes.STAIRS, item
      end
    end
    
    -- Check sewers
    for _, id in ipairs(actionPatterns.sewers) do
      if itemId == id then
        return CaveBot.WaypointTypes.SEWER, item
      end
    end
    
    -- Check doors
    if item:isDoor() then
      return CaveBot.WaypointTypes.DOOR, item
    end
  end
  
  return nil
end

-- Smart recording macro
macro(100, function()
  if not recorderState.enabled then return end
  
  local currentPos = player:getPosition()
  
  -- Check for floor change
  if recorderState.lastZ and currentPos.z ~= recorderState.lastZ then
    -- Floor changed, detect what caused it
    local belowPos = {x = currentPos.x, y = currentPos.y, z = currentPos.z + 1}
    local abovePos = {x = currentPos.x, y = currentPos.y, z = currentPos.z - 1}
    
    local tile = g_map.getTile(recorderState.lastPos)
    local actionType, item = detectTileAction(tile)
    
    if actionType then
      CaveBot.addWaypoint(actionType, {
        pos = recorderState.lastPos
      })
    else
      -- Generic walk for floor change
      CaveBot.addWaypoint(CaveBot.WaypointTypes.WALK, {
        pos = recorderState.lastPos
      })
    end
  elseif recorderState.lastPos and 
         (currentPos.x ~= recorderState.lastPos.x or 
          currentPos.y ~= recorderState.lastPos.y) then
    -- Regular movement
    CaveBot.addWaypoint(CaveBot.WaypointTypes.WALK, {
      pos = currentPos
    })
  end
  
  recorderState.lastPos = currentPos
  recorderState.lastZ = currentPos.z
end)

-- Recorder API
CaveBot.Recorder = {
  start = function()
    recorderState.enabled = true
    recorderState.lastPos = player:getPosition()
    recorderState.lastZ = player:getPosition().z
    logInfo("[CaveBot Recorder] Smart recording started")
  end,
  
  stop = function()
    recorderState.enabled = false
    logInfo("[CaveBot Recorder] Smart recording stopped")
  end,
  
  isRecording = function()
    return recorderState.enabled
  end,
  
  addActionPattern = function(category, ids)
    if actionPatterns[category] then
      for _, id in ipairs(ids) do
        table.insert(actionPatterns[category], id)
      end
    end
  end
}
