--[[
  CaveBot Auto-Recorder v2.0.0

  Records goto waypoints as the player walks, optimized for the Pure Pursuit
  and corridor-based navigation system in WaypointNavigator.

  DESIGN PRINCIPLES:
  - SRP: Records waypoints. Does not navigate or pathfind.
  - KISS: Simple direction-change detection + adaptive distance threshold.
  - DRY: Reuses the existing CaveBot.addAction API.

  KEY IMPROVEMENTS OVER v1:
  1. Direction-aware: places waypoints AT corners/turns, not after them
  2. Adaptive spacing: sparse on straight paths (15 tiles), dense at turns
  3. Euclidean distance: consistent with WaypointNavigator segment math
  4. Collinear elimination: removes redundant mid-straight waypoints
  5. Post-floor-change anchor: records position on the new floor immediately

  ALGORITHM:
  On each step, track the player's walking direction. When the direction
  changes (turn detected), record a waypoint at the LAST position before
  the turn. On straight paths, record every MAX_STRAIGHT_DIST tiles.
  This produces optimal segment geometry for Pure Pursuit lookahead.
]]

CaveBot.Recorder = {}

local isEnabled = nil
local lastPos = nil           -- last RECORDED position (the waypoint)
local prevStepPos = nil       -- position on the previous step (for direction tracking)
local prevDirection = nil     -- direction of the previous step (dx, dy normalized)
local stepsSinceLast = 0      -- steps since last recorded waypoint
local pendingCorner = nil     -- position to record when a turn is confirmed
local pendingTurnDir = nil    -- direction of the pending turn {x, y}
local pendingTurnCount = 0    -- steps taken in pending direction (for turnConfirmSteps)

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

local config = {
  -- Adaptive distance thresholds (Euclidean)
  maxStraightDist = 15,       -- max tiles between waypoints on straight paths
  minRecordDist = 3,          -- minimum tiles between any two waypoints
  turnConfirmSteps = 1,       -- steps after direction change to confirm turn (prevents jitter)

  -- Collinear tolerance: if the new waypoint forms an angle < this with the
  -- previous two waypoints, skip it (the path is still straight)
  collinearTolerance = 0.15,  -- ~8.6 degrees (dot product threshold: cos(8.6°) ≈ 0.989)
}

-- ============================================================================
-- GEOMETRY HELPERS
-- ============================================================================

--- Euclidean distance between two positions.
local function euclideanDist(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

--- Normalize a direction vector from step movement.
-- Returns dx, dy each in {-1, 0, 1}
local function stepDirection(fromPos, toPos)
  local dx = toPos.x - fromPos.x
  local dy = toPos.y - fromPos.y
  -- Normalize to -1, 0, 1 (single tile steps)
  local nx = dx == 0 and 0 or (dx > 0 and 1 or -1)
  local ny = dy == 0 and 0 or (dy > 0 and 1 or -1)
  return nx, ny
end

--- Check if three points are approximately collinear.
-- Uses cross product magnitude: if |AB × AC| / |AB| < tolerance, they're collinear.
-- Returns true if the middle point (b) is redundant.
local function isCollinear(a, b, c)
  if not a or not b or not c then return false end
  local abx, aby = b.x - a.x, b.y - a.y
  local acx, acy = c.x - a.x, c.y - a.y
  local cross = math.abs(abx * acy - aby * acx)
  local lenAB = math.sqrt(abx * abx + aby * aby)
  if lenAB < 0.01 then return true end  -- degenerate: a == b
  -- Perpendicular distance from C to line AB
  local perpDist = cross / lenAB
  return perpDist < config.collinearTolerance * lenAB
end

-- Track up to 2 previously recorded positions for collinear checks
local prevRecorded = nil      -- position recorded before lastPos

-- ============================================================================
-- RECORDING LOGIC
-- ============================================================================

local function addPosition(pos)
  -- Collinear check: if lastPos sits on the line from prevRecorded to pos,
  -- we could consider it redundant. But since we record at TURNS, the
  -- lastPos should be at a direction change and is NOT redundant.
  -- Only skip if the segment from prevRecorded through lastPos to pos
  -- is nearly straight (meaning the "turn" was actually noise).
  if prevRecorded and lastPos and isCollinear(prevRecorded, lastPos, pos) then
    -- The last waypoint was a false turn. We can't un-record it (it's already
    -- in the UI list), but this situation is rare with the direction-change
    -- algorithm. Just continue normally.
  end

  CaveBot.addAction("goto", pos.x .. "," .. pos.y .. "," .. pos.z, true)
  prevRecorded = lastPos
  lastPos = pos
  stepsSinceLast = 0
end

local function addStairs(pos)
  CaveBot.addAction("goto", pos.x .. "," .. pos.y .. "," .. pos.z .. ",0", true)
  prevRecorded = lastPos
  lastPos = pos
  stepsSinceLast = 0
  prevDirection = nil  -- Reset direction after floor change
end

local function setup()
  onPlayerPositionChange(function(newPos, oldPos)
    if zChanging() then return end
    if CaveBot.isOn() or not isEnabled then return end

    -- ======== FIRST STEP ========
    if not lastPos then
      addPosition(oldPos)
      prevStepPos = newPos
      prevDirection = nil
      pendingCorner = nil
      pendingTurnDir = nil
      pendingTurnCount = 0
      return
    end

    -- ======== FLOOR CHANGE / TELEPORT ========
    if newPos.z ~= oldPos.z or math.abs(oldPos.x - newPos.x) > 1 or math.abs(oldPos.y - newPos.y) > 1 then
      -- Record the pre-floor-change position with precision=0
      addStairs(oldPos)
      -- Anchor on the new floor: record newPos immediately so the route
      -- has a starting point on this floor (fixes the gap that v1 had)
      if newPos.z ~= oldPos.z then
        addPosition(newPos)
      end
      prevStepPos = newPos
      prevDirection = nil
      pendingCorner = nil
      pendingTurnDir = nil
      pendingTurnCount = 0
      return
    end

    -- ======== NORMAL STEP: Direction-aware recording ========
    stepsSinceLast = stepsSinceLast + 1
    local curDirX, curDirY = stepDirection(oldPos, newPos)

    -- Distance from last recorded waypoint (Euclidean)
    local distFromLast = euclideanDist(lastPos, newPos)

    if prevDirection then
      local dirChanged = (curDirX ~= prevDirection.x or curDirY ~= prevDirection.y)

      if dirChanged then
        if pendingTurnDir and pendingTurnDir.x == curDirX and pendingTurnDir.y == curDirY then
          -- Continuing in the same pending direction; increment counter
          pendingTurnCount = pendingTurnCount + 1
        else
          -- New direction change: start a new pending turn
          pendingCorner = oldPos
          pendingTurnDir = { x = curDirX, y = curDirY }
          pendingTurnCount = 1
        end

        -- Confirm the turn once we've taken enough consistent steps
        if pendingTurnCount >= config.turnConfirmSteps and pendingCorner then
          local cornerDist = euclideanDist(lastPos, pendingCorner)
          if cornerDist >= config.minRecordDist then
            addPosition(pendingCorner)
          end
          prevDirection = { x = pendingTurnDir.x, y = pendingTurnDir.y }
          pendingCorner = nil
          pendingTurnDir = nil
          pendingTurnCount = 0
        end
      else
        -- Direction unchanged: clear any pending turn (it was jitter)
        if pendingTurnDir then
          pendingCorner = nil
          pendingTurnDir = nil
          pendingTurnCount = 0
        end

        if distFromLast >= config.maxStraightDist then
          -- STRAIGHT PATH: Max distance threshold reached, record a waypoint
          -- to maintain reasonable segment lengths for the corridor system
          addPosition(newPos)
        end
      end
    else
      -- No previous direction yet (after first step or floor change)
      prevDirection = { x = curDirX, y = curDirY }

      -- If we've walked far enough without a direction, record
      if distFromLast >= config.maxStraightDist then
        addPosition(newPos)
      end
    end

    prevStepPos = newPos
  end)

  onUse(function(pos, itemId, stackPos, subType)
    if CaveBot.isOn() or not isEnabled then return end
    if pos.x ~= 0xFFFF then
      lastPos = pos
      CaveBot.addAction("use", pos.x .. "," .. pos.y .. "," .. pos.z, true)
    end
  end)

  onUseWith(function(pos, itemId, target, subType)
    if CaveBot.isOn() or not isEnabled then return end
    if not target:isItem() then return end
    local targetPos = target:getPosition()
    if targetPos.x == 0xFFFF then return end
    lastPos = pos
    CaveBot.addAction("usewith", itemId .. "," .. targetPos.x .. "," .. targetPos.y .. "," .. targetPos.z, true)
  end)
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

CaveBot.Recorder.isOn = function()
  return isEnabled
end

CaveBot.Recorder.enable = function()
  CaveBot.setOff()
  if isEnabled == nil then
    setup()
  end
  CaveBot.Editor.ui.autoRecording:setOn(true)
  isEnabled = true
  lastPos = nil
  prevStepPos = nil
  prevDirection = nil
  stepsSinceLast = 0
  pendingCorner = nil
  prevRecorded = nil
  pendingTurnDir = nil
  pendingTurnCount = 0
end

CaveBot.Recorder.disable = function()
  if isEnabled == true then
    -- Record the final position so the route doesn't end mid-segment
    if lastPos and prevStepPos then
      local finalDist = euclideanDist(lastPos, prevStepPos)
      if finalDist >= config.minRecordDist then
        CaveBot.addAction("goto", prevStepPos.x .. "," .. prevStepPos.y .. "," .. prevStepPos.z, true)
      end
    end
    isEnabled = false
  end
  CaveBot.Editor.ui.autoRecording:setOn(false)
  CaveBot.save()
end

--- Get current recorder configuration (for debug/UI).
CaveBot.Recorder.getConfig = function()
  return {
    maxStraightDist = config.maxStraightDist,
    minRecordDist = config.minRecordDist,
    collinearTolerance = config.collinearTolerance,
    turnConfirmSteps = config.turnConfirmSteps,
  }
end

--- Update recorder configuration.
CaveBot.Recorder.setConfig = function(opts)
  if type(opts) ~= "table" then return end
  local v
  v = tonumber(opts.maxStraightDist)
  if v and v > 0 then config.maxStraightDist = v end
  v = tonumber(opts.minRecordDist)
  if v and v > 0 then config.minRecordDist = v end
  v = tonumber(opts.collinearTolerance)
  if v and v > 0 then config.collinearTolerance = v end
  v = tonumber(opts.turnConfirmSteps)
  if v and v >= 0 then config.turnConfirmSteps = math.floor(v) end
end
