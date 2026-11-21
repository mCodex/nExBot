--[[
  navigation/path_planner.lua — strict pathfinding front-end.

  * NEVER authorizes movement through non-walkable / non-pathable tiles.
  * Bounded A* (maxSteps), cached by (start, goal, mapGeneration, policy).
  * Rejects floor-changing paths unless a transition owner explicitly asks.
  * Distinguishes: no-path (topology) vs creature-block vs field-block.

  Depends only on navigation.domain + navigation.ports (world/path ports).
]]

local domain = require("navigation.domain")
local D = domain
local StepValidator = require("navigation.step_validator")

local PathPlanner = {}

local DEFAULT_MAX_STEPS = 50
local CACHE_LIMIT = 128
local CACHE_TTL_MS = 5000

PathPlanner.cache = nil

local function newCache()
  return { items = {}, order = {} }
end

local MathNow = nil
function PathPlanner.setNowFn(fn)
  MathNow = fn
end

-- ponytail: 0 is truthy, so a plain `MathNow or os.time()*1000` would pin
-- nowMs to 0 (TTL never fires) or blow up when MathNow is a function.
local function nowMs()
  if type(MathNow) == "function" then return MathNow() end
  return os.time() * 1000
end

local function cacheGet(cache, key)
  local item = cache.items[key]
  if not item then return nil end
  if item.expires < nowMs() then
    cache.items[key] = nil
    return nil
  end
  return item.result
end

local function cacheSet(cache, key, result)
  local item = { result = result, expires = nowMs() + CACHE_TTL_MS }
  if cache.items[key] == nil then
    table.insert(cache.order, key)
  end
  cache.items[key] = item
  local n = #cache.order
  while n > CACHE_LIMIT do
    local evictKey = table.remove(cache.order, 1)
    cache.items[evictKey] = nil
    n = n - 1
  end
end

local function policyKey(policy)
  return (policy and (policy.ignoreCreatures and "C1" or "C0"))
    .. (policy and (policy.allowFields and "F1" or "F0"))
    .. (policy and (policy.allowFloorChange and "T1" or "T0"))
end

--- Strict path search.
-- @param ports mixed  (ports table with .path/.world)
-- @param startPos table
-- @param goalPos  table
-- @param opts { maxSteps, ignoreCreatures, allowFields, allowFloorChange,
--               useCache=false, cacheTtlMs }
-- @return StrictPathResult | nil
--   StrictPathResult = { status="FOUND"|"NO_PATH"|"MAP_UNKNOWN"|"DESTINATION_INVALID",
--                        directions={...}, positions={...}, cost=number,
--                        mapGeneration=number, connectedComponentId=string,
--                        failure=string }
function PathPlanner.find(ports, startPos, goalPos, opts)
  opts = opts or {}
  if not ports or not ports.path or not ports.path.findPath then
    return nil
  end
  if not startPos or not goalPos then return nil end
  if startPos.z ~= goalPos.z and not opts.allowFloorChange then
    return { status = "TRANSITION_REQUIRED", failure = D.FAILURE.WRONG_FLOOR }
  end

  local world = ports.world
  local mapGen = (world and world.getMapGeneration and world.getMapGeneration()) or nil

  -- Already at the destination: nothing to walk (a zero-length path is a
  -- success, not a NO_PATH).
  if D.posEquals(startPos, goalPos) then
    local out0 = {
      status = "FOUND", directions = {}, positions = { D.copyPos(startPos) },
      endPos = D.copyPos(startPos), cost = 0, mapGeneration = mapGen,
    }
    if opts.useCache then
      if not PathPlanner.cache then PathPlanner.cache = newCache() end
      local key0 = startPos.x .. "," .. startPos.y .. "," .. startPos.z .. "|"
        .. goalPos.x .. "," .. goalPos.y .. "," .. goalPos.z .. "|"
        .. tostring(mapGen) .. "|0|" .. policyKey(opts)
      cacheSet(PathPlanner.cache, key0, out0)
    end
    return out0
  end

  -- Validate the goal tile itself (never path to an invalid destination).
  if world and world.getTile then
    local tile = world.getTile(goalPos)
    if tile == nil or tile.unknown then
      return { status = "MAP_UNKNOWN", failure = D.FAILURE.NO_PATH_CURRENT_MAP, mapGeneration = mapGen }
    end
    if not tile.walkable or (tile.creature and not opts.ignoreCreatures) then
      return { status = "DESTINATION_INVALID", failure = D.FAILURE.NO_PATH_CURRENT_MAP, mapGeneration = mapGen }
    end
  end

  local maxSteps = math.min(opts.maxSteps or DEFAULT_MAX_STEPS, 254)
  local key
  if opts.useCache then
    key = startPos.x .. "," .. startPos.y .. "," .. startPos.z .. "|"
      .. goalPos.x .. "," .. goalPos.y .. "," .. goalPos.z .. "|"
      .. tostring(mapGen) .. "|" .. tostring(maxSteps) .. "|" .. policyKey(opts)
    if not PathPlanner.cache then PathPlanner.cache = newCache() end
    local hit = cacheGet(PathPlanner.cache, key)
    if hit then return hit end
  end

  local ok, result = pcall(ports.path.findPath, startPos, goalPos, {
    maxSteps = maxSteps,
    ignoreCreatures = opts.ignoreCreatures or false,
    allowFields = opts.allowFields or false,
    allowFloorChange = opts.allowFloorChange or false,
  })

  local out
  if not ok or not result or not result.directions or #result.directions == 0 then
    out = { status = "NO_PATH", failure = D.FAILURE.NO_PATH_CURRENT_MAP, mapGeneration = mapGen }
  else
    -- Re-validate every step strictly through StepValidator (defense in depth;
    -- the fake/prod native pathfinders may disagree on corner semantics).
    local okV, endPos, badIdx, reason = StepValidator.validatePath(startPos, result.directions, {
      world = world,
      ignoreCreatures = opts.ignoreCreatures or false,
      allowFields = opts.allowFields or false,
      allowFloorChange = opts.allowFloorChange or false,
    })
    if not okV then
      -- Distinguish a creature block (temporary) from a static block.
      -- positions[i] is the tile BEFORE direction i; the blocked tile is
      -- the destination of the failing step.
      local blockedTile = result.positions and result.positions[badIdx + 1]
      local diag = nil
      if world and world.getTileBlockReason and blockedTile then
        diag = world.getTileBlockReason(blockedTile, {
          ignoreCreatures = opts.ignoreCreatures,
        })
      end
      local fieldBlock = (diag == D.OBSTACLE.FIRE_FIELD or diag == D.OBSTACLE.ENERGY_FIELD
        or diag == D.OBSTACLE.POISON_FIELD or diag == D.OBSTACLE.MAGIC_WALL
        or diag == D.OBSTACLE.WILD_GROWTH)
      local failure = (diag == D.OBSTACLE.TEMPORARY_CREATURE) and D.FAILURE.TEMPORARY_CREATURE_BLOCK
        or (diag and fieldBlock) and D.FAILURE.FIELD_BLOCK
        or D.FAILURE.STATIC_TOPOLOGY_BLOCK
      out = { status = "NO_PATH", failure = failure, reason = reason or diag, mapGeneration = mapGen }
    else
      out = {
        status = "FOUND",
        directions = result.directions,
        positions = result.positions,
        endPos = endPos,
        cost = result.cost or #result.directions,
        mapGeneration = mapGen,
      }
    end
  end

  if opts.useCache then cacheSet(PathPlanner.cache, key, out) end
  return out
end

--- Strict reachability probe (used by recovery). Bounded.
-- @return true, pathResult | false, pathResult|nil, failure
function PathPlanner.isReachable(ports, startPos, goalPos, opts)
  local res = PathPlanner.find(ports, startPos, goalPos, opts or { useCache = true, maxSteps = 120 })
  if not res then return false, nil, D.FAILURE.UNKNOWN_FAILURE end
  if res.status == "FOUND" then
    if res.endPos and res.endPos.x == goalPos.x and res.endPos.y == goalPos.y and res.endPos.z == goalPos.z then
      return true, res
    end
    -- Fallback: verify the final planned tile equals the goal.
    local dirs = res.directions
    local pos = { x = startPos.x, y = startPos.y, z = startPos.z }
    for i = 1, #dirs do
      local off = D.offsetOf(dirs[i])
      if off then pos = D.addOffset(pos, off) end
    end
    if pos.x == goalPos.x and pos.y == goalPos.y and pos.z == goalPos.z then
      return true, res
    end
    return false, res, D.FAILURE.NO_PATH_CURRENT_MAP
  end
  return false, res, res.failure
end

--- Bounded local clearance of the tile at pos (radius up to `maxR`).
-- 1 = blocked/unknown neighbour immediately. Used for chunk policy + recorder density.
function PathPlanner.clearanceAt(ports, pos, maxR)
  local world = ports.world
  if not world or not world.getClearance then return nil end
  return world.getClearance(pos, maxR or 4)
end

-- Invalidate whole cache (map generation changed, route changed).
function PathPlanner.invalidate()
  PathPlanner.cache = nil
end

if nExBot and nExBot.Nav then nExBot.Nav["navigation.path_planner"] = PathPlanner end
return PathPlanner