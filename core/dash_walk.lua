--[[
  DASH Walking Module - Arrow Key Simulation for Maximum Speed
  
  This module provides ultra-fast walking using direct arrow key simulation
  instead of pathfinding. Works best with DASH client optimization enabled.
  
  Benefits:
  - Instant direction changes (no pathfinding delay)
  - Works with DASH speed boost
  - Minimal CPU overhead
  - Direct control without server round-trip delays
  
  Usage:
  - DashWalk.walkTo(pos) - Walk towards position using arrow keys
  - DashWalk.chase(creature) - Chase a creature with arrow keys
  - DashWalk.step(direction) - Take single step in direction
]]

DashWalk = DashWalk or {}

-- Direction constants
local DIR_NORTH = 0
local DIR_EAST = 1
local DIR_SOUTH = 2
local DIR_WEST = 3
local DIR_NORTHEAST = 4
local DIR_SOUTHEAST = 5
local DIR_SOUTHWEST = 6
local DIR_NORTHWEST = 7

-- Arrow key codes (Windows virtual key codes used by OTClient)
local KEY_UP = 38     -- VK_UP
local KEY_DOWN = 40   -- VK_DOWN
local KEY_LEFT = 37   -- VK_LEFT
local KEY_RIGHT = 39  -- VK_RIGHT

-- State
local lastStepTime = 0
local isEnabled = true
local stepCooldown = 50 -- ms between steps (lower = faster, but may cause issues)
local lastDirection = nil -- Track last direction to alternate when needed

-- Get direction from current position to target position
-- Returns the best direction to walk (supports 8 directions)
-- Improved to prefer cardinal directions and avoid diagonal bias
local function getDirectionTo(from, to)
    local dx = to.x - from.x
    local dy = to.y - from.y
    
    -- Calculate raw offsets for priority
    local rawDx = dx
    local rawDy = dy
    
    -- Clamp to -1, 0, 1
    dx = dx > 0 and 1 or (dx < 0 and -1 or 0)
    dy = dy > 0 and 1 or (dy < 0 and -1 or 0)
    
    -- If only one axis needs movement, use cardinal direction
    if dx == 0 and dy == -1 then return DIR_NORTH end
    if dx == 1 and dy == 0 then return DIR_EAST end
    if dx == 0 and dy == 1 then return DIR_SOUTH end
    if dx == -1 and dy == 0 then return DIR_WEST end
    
    -- For diagonal movement, prefer the axis with the larger offset
    -- This prevents getting stuck walking diagonally when we should go straight
    local absDx = math.abs(rawDx)
    local absDy = math.abs(rawDy)
    
    -- If one axis has significantly more distance, prioritize it
    if absDx > absDy * 2 then
        -- Prefer horizontal movement
        return dx > 0 and DIR_EAST or DIR_WEST, true -- second return indicates preference
    elseif absDy > absDx * 2 then
        -- Prefer vertical movement
        return dy > 0 and DIR_SOUTH or DIR_NORTH, true
    end
    
    -- 8-directional mapping for diagonal (only when both offsets are similar)
    if dx == 1 and dy == -1 then return DIR_NORTHEAST end
    if dx == 1 and dy == 1 then return DIR_SOUTHEAST end
    if dx == -1 and dy == 1 then return DIR_SOUTHWEST end
    if dx == -1 and dy == -1 then return DIR_NORTHWEST end
    
    return nil -- Same position
end

-- Get offset for a direction
local function getDirectionOffset(dir)
    if dir == DIR_NORTH then return 0, -1 end
    if dir == DIR_NORTHEAST then return 1, -1 end
    if dir == DIR_EAST then return 1, 0 end
    if dir == DIR_SOUTHEAST then return 1, 1 end
    if dir == DIR_SOUTH then return 0, 1 end
    if dir == DIR_SOUTHWEST then return -1, 1 end
    if dir == DIR_WEST then return -1, 0 end
    if dir == DIR_NORTHWEST then return -1, -1 end
    return 0, 0
end

-- Check if a tile is walkable at offset from player
local function canWalkTo(dir)
    local pos = player:getPosition()
    local dx, dy = getDirectionOffset(dir)
    local targetPos = {x = pos.x + dx, y = pos.y + dy, z = pos.z}
    local tile = g_map.getTile(targetPos)
    return tile and tile:isWalkable(false) and not tile:hasCreature()
end

-- Check if we can walk through (has creature but is walkable otherwise)
local function canWalkThrough(dir)
    local pos = player:getPosition()
    local dx, dy = getDirectionOffset(dir)
    local targetPos = {x = pos.x + dx, y = pos.y + dy, z = pos.z}
    local tile = g_map.getTile(targetPos)
    return tile and tile:isWalkable(false)
end

-- Walk in a specific direction using g_game.walk (fastest method)
function DashWalk.step(direction)
    if not isEnabled then return false end
    if player:isWalking() then return false end
    
    -- Cooldown check
    local currentTime = now
    if currentTime - lastStepTime < stepCooldown then
        return false
    end
    
    -- Validate direction
    if not direction or direction < 0 or direction > 7 then
        return false
    end
    
    -- Check if walkable
    if not canWalkThrough(direction) then
        return false
    end
    
    -- Execute the walk
    lastStepTime = currentTime
    g_game.walk(direction, false)
    return true
end

-- Walk towards a target position using the best direction
-- Returns true if a step was taken
function DashWalk.walkTo(targetPos, precision)
    if not isEnabled then return false end
    if not targetPos then return false end
    if player:isWalking() then return false end
    
    precision = precision or 0
    
    local pos = player:getPosition()
    
    -- Check if on different floor
    if pos.z ~= targetPos.z then
        return false -- Can't walk to different floors
    end
    
    -- Check if already at target (within precision)
    local dist = math.max(math.abs(pos.x - targetPos.x), math.abs(pos.y - targetPos.y))
    if dist <= precision then
        return false -- Already there
    end
    
    -- Calculate raw offsets for smart direction selection
    local dx = targetPos.x - pos.x
    local dy = targetPos.y - pos.y
    local absDx = math.abs(dx)
    local absDy = math.abs(dy)
    
    -- Get best direction (may have preference hint)
    local dir, isPreferred = getDirectionTo(pos, targetPos)
    if not dir then
        return false
    end
    
    -- Try primary direction first
    if canWalkTo(dir) then
        lastDirection = dir
        return DashWalk.step(dir)
    end
    
    -- Smart fallback logic - try cardinal directions based on offset
    if dir >= 4 then -- Was trying diagonal
        local horizDir = dx > 0 and DIR_EAST or DIR_WEST
        local vertDir = dy > 0 and DIR_SOUTH or DIR_NORTH
        
        -- Alternate based on which axis has more distance, or last direction
        local tryHorizFirst = absDx >= absDy
        
        -- If we went horizontal last time, try vertical first to avoid bias
        if lastDirection == DIR_EAST or lastDirection == DIR_WEST then
            tryHorizFirst = false
        elseif lastDirection == DIR_NORTH or lastDirection == DIR_SOUTH then
            tryHorizFirst = true
        end
        
        if tryHorizFirst then
            if dx ~= 0 and canWalkTo(horizDir) then
                lastDirection = horizDir
                return DashWalk.step(horizDir)
            end
            if dy ~= 0 and canWalkTo(vertDir) then
                lastDirection = vertDir
                return DashWalk.step(vertDir)
            end
        else
            if dy ~= 0 and canWalkTo(vertDir) then
                lastDirection = vertDir
                return DashWalk.step(vertDir)
            end
            if dx ~= 0 and canWalkTo(horizDir) then
                lastDirection = horizDir
                return DashWalk.step(horizDir)
            end
        end
    else
        -- Was trying cardinal, try adjacent cardinals
        local altDirs = {}
        if dir == DIR_NORTH or dir == DIR_SOUTH then
            if dx > 0 then table.insert(altDirs, DIR_EAST) end
            if dx < 0 then table.insert(altDirs, DIR_WEST) end
        else -- EAST or WEST
            if dy > 0 then table.insert(altDirs, DIR_SOUTH) end
            if dy < 0 then table.insert(altDirs, DIR_NORTH) end
        end
        
        for _, altDir in ipairs(altDirs) do
            if canWalkTo(altDir) then
                lastDirection = altDir
                return DashWalk.step(altDir)
            end
        end
    end
    
    return false
end

-- Chase a creature using arrow key movement
-- Maintains distance range if specified
function DashWalk.chase(creature, minDist, maxDist)
    if not isEnabled then return false end
    if not creature then return false end
    if creature:isDead() then return false end
    if player:isWalking() then return false end
    
    minDist = minDist or 1
    maxDist = maxDist or 1
    
    local pos = player:getPosition()
    local cpos = creature:getPosition()
    
    -- Check if on different floor
    if pos.z ~= cpos.z then
        return false
    end
    
    -- Calculate current distance
    local dist = math.max(math.abs(pos.x - cpos.x), math.abs(pos.y - cpos.y))
    
    -- Check if already in range
    if dist >= minDist and dist <= maxDist then
        return false -- Already in range
    end
    
    -- If too far, walk towards
    if dist > maxDist then
        return DashWalk.walkTo(cpos, maxDist)
    end
    
    -- If too close, walk away (find safe tile)
    if dist < minDist then
        local dx = pos.x - cpos.x
        local dy = pos.y - cpos.y
        
        -- Normalize to direction away from creature
        dx = dx > 0 and 1 or (dx < 0 and -1 or 0)
        dy = dy > 0 and 1 or (dy < 0 and -1 or 0)
        
        -- If we're on top of creature, pick a random direction
        if dx == 0 and dy == 0 then
            dx = math.random(-1, 1)
            dy = math.random(-1, 1)
        end
        
        local awayPos = {x = pos.x + dx, y = pos.y + dy, z = pos.z}
        return DashWalk.walkTo(awayPos, 0)
    end
    
    return false
end

-- Find and walk to the safest adjacent tile (for wave avoidance)
function DashWalk.evade(dangerPos)
    if not isEnabled then return false end
    if player:isWalking() then return false end
    
    local pos = player:getPosition()
    local bestDir = nil
    local bestDist = 0
    
    -- Check all 8 directions
    for dir = 0, 7 do
        if canWalkTo(dir) then
            local dx, dy = getDirectionOffset(dir)
            local newPos = {x = pos.x + dx, y = pos.y + dy, z = pos.z}
            local dist = math.max(math.abs(newPos.x - dangerPos.x), math.abs(newPos.y - dangerPos.y))
            
            if dist > bestDist then
                bestDist = dist
                bestDir = dir
            end
        end
    end
    
    if bestDir then
        return DashWalk.step(bestDir)
    end
    
    return false
end

-- Enable/disable DASH walking
function DashWalk.setEnabled(enabled)
    isEnabled = enabled
end

function DashWalk.isEnabled()
    return isEnabled
end

-- Set step cooldown (lower = faster)
function DashWalk.setCooldown(ms)
    stepCooldown = ms
end

-- Get distance between two positions (Chebyshev distance)
function DashWalk.getDistance(pos1, pos2)
    return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

--[[
  Map Click DASH Walking
  
  Hooks into map click events to use DASH walking instead of default pathfinding.
  This provides faster, more responsive movement when clicking on the minimap or game map.
]]

-- Map click walking state
local mapClickTarget = nil
local mapClickActive = false
local MAP_CLICK_PRECISION = 1 -- How close we need to get to the target

-- Process map click walking (called on each macro tick)
local function processMapClickWalk()
    if not mapClickActive or not mapClickTarget then
        return
    end
    
    local pos = player:getPosition()
    
    -- Check if we reached the target
    local dist = DashWalk.getDistance(pos, mapClickTarget)
    if dist <= MAP_CLICK_PRECISION then
        mapClickActive = false
        mapClickTarget = nil
        return
    end
    
    -- Check if target is on different floor (cancel)
    if pos.z ~= mapClickTarget.z then
        mapClickActive = false
        mapClickTarget = nil
        return
    end
    
    -- Try to walk towards target
    DashWalk.walkTo(mapClickTarget, MAP_CLICK_PRECISION)
end

-- Set a map click target for DASH walking
function DashWalk.setMapClickTarget(targetPos)
    if not targetPos then
        mapClickActive = false
        mapClickTarget = nil
        return
    end
    
    local pos = player:getPosition()
    
    -- Only handle same-floor clicks
    if pos.z ~= targetPos.z then
        return false
    end
    
    mapClickTarget = targetPos
    mapClickActive = true
    return true
end

-- Cancel ongoing map click walk
function DashWalk.cancelMapClick()
    mapClickActive = false
    mapClickTarget = nil
end

-- Check if map click walking is active
function DashWalk.isMapClickActive()
    return mapClickActive
end

-- Background loop for map click walking (always active, built-in feature)
local function startMapClickLoop()
    if mapClickActive then
        processMapClickWalk()
    end
    schedule(50, startMapClickLoop)
end
startMapClickLoop()

-- Hook into map widget click (if available)
-- This intercepts map clicks and uses DASH walking
if g_game and g_ui then
    local function hookMapClick()
        local mapWidget = modules.game_interface and modules.game_interface.getMapPanel and modules.game_interface.getMapPanel()
        if mapWidget then
            local originalOnMouseRelease = mapWidget.onMouseRelease
            mapWidget.onMouseRelease = function(widget, mousePos, mouseButton)
                -- Only intercept left clicks for walking
                if mouseButton == MouseLeftButton then
                    local pos = mapWidget:getPosition(mousePos)
                    if pos and pos.z == player:getPosition().z then
                        -- Use DASH walking
                        DashWalk.setMapClickTarget(pos)
                        return true -- Consume the event
                    end
                end
                -- Fall back to original handler
                if originalOnMouseRelease then
                    return originalOnMouseRelease(widget, mousePos, mouseButton)
                end
                return false
            end
        end
    end
    
    -- Try to hook immediately or after game start
    schedule(1000, hookMapClick)
end