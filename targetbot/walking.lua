--[[
  TargetBot Walking Module - Optimized Pathfinding v5.0.0
  
  Uses path caching and progressive pathfinding for better performance.
  Integrates with TargetBot's creature cache for efficient walking.
  
  v5.0.0: Integrated PathUtils for DRY, added anti-zigzag, native API optimization
]]

-- ClientService helper for cross-client compatibility (OTCv8 / OpenTibiaBR)
local function getClient()
  return ClientService
end

local function getClientVersion()
  local Client = getClient()
  return (Client and Client.getClientVersion) and Client.getClientVersion() or (g_game and g_game.getClientVersion and g_game.getClientVersion()) or 1200
end

-- Load PathUtils if available (shared module for DRY)
local PathUtils = nil
local function ensurePathUtils()
  if PathUtils then return PathUtils end
  -- OTClient compatible - just try dofile
  local success = pcall(function()
    dofile("nExBot/utils/path_utils.lua")
  end)
  -- After dofile, PathUtils should be global
  if success then
    PathUtils = PathUtils  -- Re-check global
  end
  return PathUtils
end
ensurePathUtils()

local dest = nil
local maxDist = nil
local params = nil

-- Use PathUtils for direction offsets if available, else fallback
local DIR_TO_OFFSET = (PathUtils and PathUtils.DIR_TO_OFFSET) or {
  [North] = {x = 0, y = -1},
  [East] = {x = 1, y = 0},
  [South] = {x = 0, y = 1},
  [West] = {x = -1, y = 0},
  [NorthEast] = {x = 1, y = -1},
  [SouthEast] = {x = 1, y = 1},
  [SouthWest] = {x = -1, y = 1},
  [NorthWest] = {x = -1, y = -1}
}

-- Use PathUtils for floor-change colors if available
local FLOOR_CHANGE_COLORS = (PathUtils and PathUtils.FLOOR_CHANGE_COLORS) or {
  [210] = true, [211] = true, [212] = true, [213] = true,
}

-- Use PathUtils for floor-change items if available
local FLOOR_CHANGE_ITEMS = (PathUtils and PathUtils.FLOOR_CHANGE_ITEMS) or {
  -- Minimal fallback set
  [414]=true,[415]=true,[416]=true,[417]=true,
  [1956]=true,[1957]=true,[1958]=true,[1959]=true,
  [1219]=true,[384]=true,[386]=true,[418]=true,
}

-- Use PathUtils for floor-change detection (DRY)
local function isFloorChangeTile(pos)
  if PathUtils and PathUtils.isFloorChangeTile then
    return PathUtils.isFloorChangeTile(pos)
  end
  if TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.isFloorChangeTile then
    return TargetCore.PathSafety.isFloorChangeTile(pos)
  end
  -- Fallback implementation
  if not pos then return false end
  local Client = getClient()
  local color = (Client and Client.getMinimapColor) and Client.getMinimapColor(pos) or (g_map and g_map.getMinimapColor and g_map.getMinimapColor(pos)) or 0
  if FLOOR_CHANGE_COLORS[color] then return true end
  local tile = (Client and Client.getTile) and Client.getTile(pos) or (g_map and g_map.getTile and g_map.getTile(pos))
  if not tile then return false end
  local ground = tile:getGround()
  if ground and FLOOR_CHANGE_ITEMS[ground:getId()] then return true end
  local topUse = tile:getTopUseThing()
  if topUse and topUse:isItem() and FLOOR_CHANGE_ITEMS[topUse:getId()] then return true end
  local top = tile:getTopThing()
  if top and top:isItem() and FLOOR_CHANGE_ITEMS[top:getId()] then return true end
  return false
end

-- Use PathUtils for path validation (DRY)
local function pathCrossesFloorChange(path, startPos)
  if PathUtils and PathUtils.pathCrossesFloorChange then
    return PathUtils.pathCrossesFloorChange(path, startPos)
  end
  if TargetCore and TargetCore.PathSafety and TargetCore.PathSafety.pathCrossesFloorChange then
    return TargetCore.PathSafety.pathCrossesFloorChange(path, startPos)
  end
  -- Fallback implementation
  if not path or #path == 0 or not startPos then return false end
  local probe = {x = startPos.x, y = startPos.y, z = startPos.z}
  for i = 1, #path do
    local off = DIR_TO_OFFSET[path[i]]
    if off then
      probe.x = probe.x + off.x
      probe.y = probe.y + off.y
      if isFloorChangeTile(probe) then
        return true
      end
    end
  end
  return false
end

-- ============================================================================
-- ANTI-ZIGZAG SYSTEM
-- ============================================================================

local AntiZigzag = {
  lastDirection = nil,
  lastDirectionTime = 0,
  minChangeDelay = 100,  -- Minimum ms between direction changes
  directionHistory = {},  -- Ring buffer for last N directions
  historySize = 3,
}

-- Check if two directions are similar (same or adjacent)
local function areSimilarDirections(dir1, dir2)
  if PathUtils and PathUtils.areSimilarDirections then
    return PathUtils.areSimilarDirections(dir1, dir2)
  end
  if dir1 == dir2 then return true end
  -- Adjacent check using offsets
  local off1 = DIR_TO_OFFSET[dir1]
  local off2 = DIR_TO_OFFSET[dir2]
  if not off1 or not off2 then return false end
  return math.abs(off1.x - off2.x) <= 1 and math.abs(off1.y - off2.y) <= 1
end

-- Check if two directions are opposite
local function areOppositeDirections(dir1, dir2)
  if PathUtils and PathUtils.areOppositeDirections then
    return PathUtils.areOppositeDirections(dir1, dir2)
  end
  local off1 = DIR_TO_OFFSET[dir1]
  local off2 = DIR_TO_OFFSET[dir2]
  if not off1 or not off2 then return false end
  return off1.x == -off2.x and off1.y == -off2.y
end

-- Validate direction change to prevent zigzag
local function validateDirectionChange(newDir)
  local currentTime = now
  local timeSinceChange = currentTime - AntiZigzag.lastDirectionTime
  
  -- Allow any direction if enough time passed
  if timeSinceChange >= AntiZigzag.minChangeDelay then
    -- Check for oscillation pattern
    if #AntiZigzag.directionHistory >= 2 then
      local prevDir = AntiZigzag.directionHistory[#AntiZigzag.directionHistory]
      local prevPrevDir = AntiZigzag.directionHistory[#AntiZigzag.directionHistory - 1]
      
      -- Detect A-B-A pattern (zigzag)
      if prevPrevDir == newDir and areOppositeDirections(prevDir, newDir) then
        -- Zigzag detected, dampen the change
        return false
      end
    end
    
    -- Record direction
    table.insert(AntiZigzag.directionHistory, newDir)
    if #AntiZigzag.directionHistory > AntiZigzag.historySize then
      table.remove(AntiZigzag.directionHistory, 1)
    end
    AntiZigzag.lastDirection = newDir
    AntiZigzag.lastDirectionTime = currentTime
    return true
  end
  
  -- Too soon, only allow similar direction
  return areSimilarDirections(AntiZigzag.lastDirection, newDir)
end

-- Path cache for TargetBot walking
local WalkCache = {
  path = nil,
  destKey = nil,
  timestamp = 0,
  idx = 1,
  TTL = 200  -- Short TTL for combat responsiveness
}

-- Generate cache key
local function getCacheKey(destination)
  if not destination then return nil end
  return destination.x .. "," .. destination.y .. "," .. destination.z
end

TargetBot.walkTo = function(_dest, _maxDist, _params)
  dest = _dest
  maxDist = _maxDist
  params = _params or {}
  
  -- ═══════════════════════════════════════════════════════════════════════════
  -- NATIVE CHASE MODE CHECK
  -- When OTClient native chase mode is active (setChaseMode(1) + attacking),
  -- skip custom pathfinding - let the client handle walking automatically.
  -- This prevents interference with the native chase behavior.
  -- ═══════════════════════════════════════════════════════════════════════════
  if TargetBot.usingNativeChase then
    -- Check if we're actually attacking (native chase only works when attacking)
    local Client = getClient()
    local isAttacking = (Client and Client.isAttacking) and Client.isAttacking() or (g_game and g_game.isAttacking and g_game.isAttacking())
    if isAttacking then
      -- Verify chase mode is still set correctly
      local chaseMode = (Client and Client.getChaseMode) and Client.getChaseMode() or (g_game and g_game.getChaseMode and g_game.getChaseMode()) or 0
      if chaseMode == 1 then
        -- Native chase is active and working, skip custom walking
        dest = nil
        return true  -- Return true to indicate chase is handling movement
      end
    end
  end
  
  -- Check if following a player (for "Follow While Attacking" feature)
  -- We don't skip pathfinding for monsters anymore since we use custom pathfinding for chase
  local Client = getClient()
  local currentFollow = (Client and Client.getFollowingCreature) and Client.getFollowingCreature() or (g_game and g_game.getFollowingCreature and g_game.getFollowingCreature())
  if currentFollow then
    if currentFollow:isPlayer() and not currentFollow:isLocalPlayer() then
      -- Check if following a player with "Follow While Attacking" enabled
      local shouldKeepFollow = false
      if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
        local followConfig = CharacterDB.get("tools.followPlayer")
        if followConfig and followConfig.enabled and followConfig.followWhileAttacking then
          local targetName = followConfig.playerName and followConfig.playerName:trim():lower() or ""
          local followName = currentFollow:getName():lower()
          if targetName ~= "" and (followName == targetName or followName:find(targetName, 1, true)) then
            shouldKeepFollow = true
          end
        end
      end
      
      if shouldKeepFollow then
        -- Following a player, skip custom pathfinding
        dest = nil
        return
      else
        -- Not a configured follow target, cancel and use custom pathfinding
        if Client and Client.cancelFollow then
          Client.cancelFollow()
        elseif g_game and g_game.cancelFollow then
          g_game.cancelFollow()
        end
      end
    end
  end
  
  -- Invalidate cache if destination changed
  local newKey = getCacheKey(_dest)
  if newKey ~= WalkCache.destKey then
    WalkCache.path = nil
    WalkCache.destKey = newKey
    WalkCache.timestamp = 0
    WalkCache.idx = 1
  end
  
  -- IMMEDIATE WALK: Execute first step right away instead of waiting for next tick
  -- This fixes the timing issue where TargetBot.walk() was called before walkTo()
  if dest and not player:isWalking() then
    TargetBot.walk()
  end
end

-- Called every 100ms if targeting or looting is active
TargetBot.walk = function()
  if not dest then return end
  if player:isWalking() then return end
  
  local playerPos = player:getPosition()
  if not playerPos then return end
  if playerPos.z ~= dest.z then 
    dest = nil
    return 
  end

  -- Abort if player unexpectedly changed floor mid-chase (path likely invalid)
  if WalkCache.lastZ and WalkCache.lastZ ~= playerPos.z then
    dest = nil
    WalkCache.path = nil
    WalkCache.idx = 1
    WalkCache.timestamp = 0
    WalkCache.destKey = nil
    return
  end
  WalkCache.lastZ = playerPos.z
  
  -- Calculate distance
  local distX = math.abs(playerPos.x - dest.x)
  local distY = math.abs(playerPos.y - dest.y)
  local dist = math.max(distX, distY)
  
  -- Check precision
  if params.precision and params.precision >= dist then 
    dest = nil
    return 
  end
  
  -- Check margin range
  if params.marginMin and params.marginMax then
    if dist >= params.marginMin and dist <= params.marginMax then 
      dest = nil
      return
    end
  end
  
  -- Check cache
  if WalkCache.path and WalkCache.idx <= #WalkCache.path and (now - WalkCache.timestamp) < WalkCache.TTL then
    -- Safety: abort if next step leads to floor change
    local nextPos = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
    local nextDir = WalkCache.path[WalkCache.idx]
    local off = DIR_TO_OFFSET[nextDir]
    if off then
      nextPos.x = nextPos.x + off.x
      nextPos.y = nextPos.y + off.y
      if isFloorChangeTile(nextPos) then
        dest = nil
        WalkCache.path = nil
        WalkCache.idx = 1
        return
      end
    end
    
    -- ANTI-ZIGZAG: Validate direction change
    if not validateDirectionChange(nextDir) then
      -- Direction change too rapid, wait for next tick
      return
    end
    
    -- Use cached path - take first step
    walk(nextDir)
    WalkCache.idx = WalkCache.idx + 1
    return
  end
  
  -- Calculate new path
  -- Safety: if destination itself is a floor-change tile, abort chase/avoid move
  if isFloorChangeTile(dest) then
    dest = nil
    WalkCache.path = nil
    WalkCache.idx = 1
    WalkCache.timestamp = 0
    WalkCache.destKey = nil
    return
  end

  local path = getPath(playerPos, dest, maxDist or 10, params)
  
  if path and #path > 0 then
    -- Abort if path crosses floor-change tiles (prevents unintended Z changes)
    if pathCrossesFloorChange(path, playerPos) then
      dest = nil
      WalkCache.path = nil
      WalkCache.idx = 1
      return
    end
    -- Cache the path
    WalkCache.path = path
    WalkCache.timestamp = now
    WalkCache.idx = 1
    
    -- ANTI-ZIGZAG: Validate first step direction
    local firstDir = path[WalkCache.idx]
    if not validateDirectionChange(firstDir) then
      -- Direction change too rapid, wait for next tick
      return
    end
    
    -- Take first step
    walk(firstDir)
    WalkCache.idx = WalkCache.idx + 1
  end
  
  -- Clear destination after attempting walk
  dest = nil
end

-- Clear walking state
TargetBot.clearWalk = function()
  dest = nil
  WalkCache.path = nil
  WalkCache.timestamp = 0
  -- Reset anti-zigzag state
  AntiZigzag.lastDirection = nil
  AntiZigzag.lastDirectionTime = 0
  AntiZigzag.directionHistory = {}
end
