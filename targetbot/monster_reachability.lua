-- Authoritative TargetBot reachability, path cache and quarantine service.

TargetReachability = TargetReachability or {}
local R = TargetReachability
R.VERSION = "4.0"
R.DEBUG = R.DEBUG or false

local cache = {}
local quarantine = {}
local stats = { evaluations = 0, cacheHits = 0, pathCalls = 0, rejected = 0 }
local MAX_ENTRIES = 128
local CACHE_TTL = 300
local TEMP_COOLDOWN = 1000
local HARD_COOLDOWN = 4000
local HARD_COOLDOWN_MAX = 30000

local function debugEvent(name, data)
  if not R.DEBUG then return end
  if EventBus and EventBus.emit then pcall(EventBus.emit, name, data) end
  if type(print) == "function" then print("[TargetReachability] " .. name .. " " .. tostring(data and data.reason or "")) end
end

local function nowMs()
  if nExBot and nExBot.Shared and nExBot.Shared.nowMs then return nExBot.Shared.nowMs() end
  return now or os.time() * 1000
end

local function call(object, method, fallback)
  if not object or type(object[method]) ~= "function" then return fallback end
  local ok, value = pcall(object[method], object)
  return ok and value or fallback
end

local function creatureId(creature)
  if SafeCreature and SafeCreature.getId then return SafeCreature.getId(creature) end
  return call(creature, "getId")
end

local function creaturePos(creature)
  if SafeCreature and SafeCreature.getPosition then return SafeCreature.getPosition(creature) end
  return call(creature, "getPosition")
end

local function playerPos()
  local p = player
  if not p and g_game and g_game.getLocalPlayer then p = g_game.getLocalPlayer() end
  if SafeCreature and SafeCreature.getPosition then return SafeCreature.getPosition(p) end
  return call(p, "getPosition")
end

local function isDead(creature)
  if not creature then return true end
  if SafeCreature and SafeCreature.isDead and SafeCreature.isDead(creature) then return true end
  if SafeCreature and SafeCreature.isRemoved and SafeCreature.isRemoved(creature) then return true end
  return call(creature, "isDead", false) or call(creature, "isRemoved", false)
end

local function posKey(p)
  return p and (tostring(p.x) .. "," .. tostring(p.y) .. "," .. tostring(p.z)) or "?"
end

local function modeFor(context)
  context = context or {}
  if context.mode then return context.mode end
  local config = context.config or {}
  if config.keepDistance or config.ranged or (config.distance or 1) > 1 then return "ranged" end
  return "melee"
end

local function profileFor(context)
  context = context or {}
  local mode = modeFor(context)
  local config = context.config or {}
  local minDistance = mode == "melee" and 1 or (context.minDistance or context.marginMin or config.minDistance or 1)
  local maxDistance = mode == "melee" and 1 or (context.maxDistance or context.marginMax or context.distance or config.distance or 7)
  return {
    name = context.profile or (mode == "melee" and "melee_attack_position" or "ranged_attack_position"),
    mode = mode,
    marginMin = minDistance,
    marginMax = maxDistance,
    ignoreLastCreature = true,
    ignoreCreatures = context.ignoreCreatures == true,
    ignoreNonPathable = false,
    ignoreNonWalkable = false,
    ignoreCost = false,
    allowOnlyVisibleTiles = context.allowOnlyVisibleTiles ~= false,
    precision = 0,
  }
end

local function profileKey(p)
  return table.concat({ p.name, p.mode, p.marginMin, p.marginMax,
    p.ignoreCreatures and 1 or 0, p.allowOnlyVisibleTiles and 1 or 0 }, ":")
end

local function makeKey(id, pp, cp, profile)
  return table.concat({ id, posKey(pp), posKey(cp), profileKey(profile) }, "|")
end

local function classificationFor(reason)
  if reason == "creature_blocked" or reason == "incomplete_map" or reason == "no_path_api" then
    return "temporarily_blocked"
  end
  if reason == "different_floor" then return "different_floor" end
  if reason == "no_line_of_sight" then return "no_line_of_sight" end
  if reason == "no_attack_position" then return "hard_unreachable" end
  return "insufficient_information"
end

local function result(id, pp, cp, profile, attackable, reason, path, capability)
  return {
    creatureId = id,
    reachable = attackable,
    attackable = attackable,
    path = path,
    attackPosition = nil,
    reason = reason,
    classification = attackable and "confirmed" or classificationFor(reason),
    playerPosition = pp,
    creaturePosition = cp,
    evaluatedAt = nowMs(),
    capability = capability or "none",
    profile = profile.name,
  }
end

local OFFSETS = {
  [0] = { 0, -1 }, [1] = { 1, 0 }, [2] = { 0, 1 }, [3] = { -1, 0 },
  [4] = { 1, -1 }, [5] = { 1, 1 }, [6] = { -1, 1 }, [7] = { -1, -1 },
}

local function pathEnd(start, path)
  local endpoint = { x = start.x, y = start.y, z = start.z }
  for i = 1, #path do
    local offset = OFFSETS[path[i]]
    if not offset then return nil end
    endpoint.x, endpoint.y = endpoint.x + offset[1], endpoint.y + offset[2]
  end
  return endpoint
end

local function findPathToRing(pp, cp, maxSteps, profile)
  local currentDistance = math.max(math.abs(pp.x - cp.x), math.abs(pp.y - cp.y))
  if currentDistance >= profile.marginMin and currentDistance <= profile.marginMax then
    return {}, { x = pp.x, y = pp.y, z = pp.z }, "already_in_attack_position"
  end
  local fn = type(findPath) == "function" and findPath or nil
  local capability = fn and "findPath_wrapper" or nil
  if not fn and PathUtils and type(PathUtils.findPath) == "function" then
    fn, capability = PathUtils.findPath, "PathUtils.findPath"
  end
  if fn then
    stats.pathCalls = stats.pathCalls + 1
    local ok, path = pcall(fn, pp, cp, maxSteps, profile)
    if ok and type(path) == "table" and #path > 0 then
      return path, pathEnd(pp, path), capability
    end
    return nil, nil, capability, "no_attack_position"
  end

  -- Last-resort native API has no margin support; probe the small attack ring.
  if g_map and type(g_map.findPath) == "function" then
    local bestPath, bestPosition
    for dx = -profile.marginMax, profile.marginMax do
      for dy = -profile.marginMax, profile.marginMax do
        local distance = math.max(math.abs(dx), math.abs(dy))
        if distance >= profile.marginMin and distance <= profile.marginMax then
          local candidate = { x = cp.x + dx, y = cp.y + dy, z = cp.z }
          stats.pathCalls = stats.pathCalls + 1
          local ok, path, code = pcall(g_map.findPath, pp, candidate, maxSteps, 0)
          if ok and code == 0 and type(path) == "table" and #path > 0
            and (not bestPath or #path < #bestPath) then
            bestPath, bestPosition = path, candidate
          end
        end
      end
    end
    if bestPath then return bestPath, bestPosition, "g_map.findPath" end
    return nil, nil, "g_map.findPath", "no_attack_position"
  end
  return nil, nil, "none", "no_path_api"
end

local function hasShot(pp, cp, maxDistance)
  if g_map and type(g_map.isSightClear) == "function" then
    local ok, clear = pcall(g_map.isSightClear, pp, cp)
    if ok then return clear == true, "g_map.isSightClear" end
  end
  if g_map and type(g_map.getTile) == "function" then
    local okTile, tile = pcall(g_map.getTile, cp)
    if okTile and tile and type(tile.canShoot) == "function" then
      local ok, clear = pcall(tile.canShoot, tile, maxDistance)
      if ok then return clear == true, "tile.canShoot" end
    end
  end
  return false, "shoot_api_unavailable"
end

local function prune(tableValue)
  local count, oldestKey, oldestAt = 0, nil, math.huge
  for key, entry in pairs(tableValue) do
    count = count + 1
    local at = entry.evaluatedAt or entry.blockedAt or 0
    if at < oldestAt then oldestKey, oldestAt = key, at end
  end
  if count >= MAX_ENTRIES and oldestKey then tableValue[oldestKey] = nil end
end

function R.evaluate(creature, context)
  context = context or {}
  if not context.config and TargetBot and TargetBot.Creature and TargetBot.Creature.getConfigs then
    local ok, configs = pcall(TargetBot.Creature.getConfigs, creature)
    if ok and configs then context.config = configs[1] end
  end
  local id = creatureId(creature)
  local pp, cp = playerPos(), creaturePos(creature)
  local profile = profileFor(context)
  if not id or isDead(creature) or not pp or not cp then
    return result(id, pp, cp, profile, false, "invalid_target")
  end
  if pp.z ~= cp.z then return result(id, pp, cp, profile, false, "different_floor") end

  local key = makeKey(id, pp, cp, profile)
  local cached = cache[key]
  if not context.force and cached and nowMs() - cached.evaluatedAt <= CACHE_TTL then
    stats.cacheHits = stats.cacheHits + 1
    cached.cacheHit = true
    debugEvent("target_path_cache_hit", cached)
    return cached
  end

  stats.evaluations = stats.evaluations + 1
  local path, attackPosition, capability, failure = findPathToRing(pp, cp, context.maxSteps or 15, profile)
  local evaluated
  if not path then
    if failure == "no_attack_position" and not profile.ignoreCreatures then
      local optimistic = {}
      for key, value in pairs(profile) do optimistic[key] = value end
      optimistic.ignoreCreatures = true
      local probe = findPathToRing(pp, cp, context.maxSteps or 15, optimistic)
      if probe then failure = "creature_blocked" end
    end
    evaluated = result(id, pp, cp, profile, false, failure, nil, capability)
  elseif profile.mode == "ranged" then
    local clear, shotCapability = hasShot(attackPosition or pp, cp, profile.marginMax)
    evaluated = result(id, pp, cp, profile, clear, clear and "reachable" or "no_line_of_sight", path,
      capability .. "+" .. shotCapability)
  else
    evaluated = result(id, pp, cp, profile, true, "reachable", path, capability)
  end
  evaluated.attackPosition = attackPosition

  if not evaluated.attackable then stats.rejected = stats.rejected + 1 end
  prune(cache)
  cache[key] = evaluated
  debugEvent("target_reachability_evaluated", evaluated)
  if not evaluated.attackable then debugEvent("target_candidate_rejected", evaluated) end
  return evaluated
end

function R.quarantine(creature, evaluated)
  local id = creatureId(creature)
  if not id or not evaluated or evaluated.attackable then return end
  local previous = quarantine[id]
  local failures = previous and previous.failureCount + 1 or 1
  local temporary = evaluated.classification == "temporarily_blocked"
  local cooldown = temporary and TEMP_COOLDOWN or math.min(HARD_COOLDOWN * (2 ^ (failures - 1)), HARD_COOLDOWN_MAX)
  prune(quarantine)
  quarantine[id] = {
    creatureId = id,
    reason = evaluated.reason,
    classification = evaluated.classification,
    blockedAt = nowMs(),
    retryAt = nowMs() + cooldown,
    playerPosition = evaluated.playerPosition,
    creaturePosition = evaluated.creaturePosition,
    failureCount = failures,
    cooldown = cooldown,
  }
  debugEvent("target_quarantined", quarantine[id])
  return quarantine[id]
end

function R.isQuarantined(creature)
  local id = type(creature) == "number" and creature or creatureId(creature)
  local entry = id and quarantine[id]
  if not entry then return false end
  if nowMs() >= entry.retryAt then quarantine[id] = nil; return false end
  return true, entry
end

function R.invalidate(creatureIdValue)
  if creatureIdValue then quarantine[creatureIdValue] = nil else quarantine = {} end
  cache = {}
end

function R.release(creature, evaluated)
  R.quarantine(creature, evaluated)
  R.invalidateCache()
end

function R.invalidateCache()
  cache = {}
  debugEvent("target_path_cache_invalidated", { reason = "explicit" })
end
function R.clearCache() R.invalidateCache() end
function R.clearBlocked(id) if id then quarantine[id] = nil end end
function R.markBlocked(id, reason)
  if not id then return end
  R.quarantine({ getId = function() return id end }, {
    attackable = false, reason = reason or "no_attack_position", classification = classificationFor(reason)
  })
end

function R.isReachable(creature, force)
  local evaluated = R.evaluate(creature, { force = force == true })
  return evaluated.attackable, evaluated.reason, evaluated.path, evaluated
end

function R.validateTarget(creature, context)
  local evaluated = R.evaluate(creature, context)
  return evaluated.attackable, evaluated.reason, evaluated.path, evaluated
end

function R.isBlocked(id) return R.isQuarantined(id) end
function R.getCachedPath(id)
  for _, entry in pairs(cache) do if entry.creatureId == id then return entry.path end end
end
function R.cleanup()
  local t = nowMs()
  for key, entry in pairs(cache) do if t - entry.evaluatedAt > CACHE_TTL * 3 then cache[key] = nil end end
  for id, entry in pairs(quarantine) do if t >= entry.retryAt then quarantine[id] = nil end end
end
function R.getStats()
  local q = 0
  for _ in pairs(quarantine) do q = q + 1 end
  return { evaluations = stats.evaluations, cacheHits = stats.cacheHits, pathCalls = stats.pathCalls,
    rejected = stats.rejected, quarantined = q }
end

MonsterAI = MonsterAI or {}
MonsterAI.Reachability = R

if EventBus and EventBus.on then
  EventBus.on("player:position", function() R.invalidateCache() end)
  EventBus.on("creature:move", function(creature) R.invalidate(creatureId(creature), "creature_moved") end)
  EventBus.on("monster:disappear", function(creature) R.invalidate(creatureId(creature), "disappeared") end)
end

if UnifiedTick and UnifiedTick.register then
  UnifiedTick.register({ id = "target_reachability_cleanup", interval = 5000, priority = 10, callback = R.cleanup })
elseif type(macro) == "function" then
  macro(5000, R.cleanup)
end

return R
