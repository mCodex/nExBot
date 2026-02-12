--[[
  Monster Reachability Module v3.0
  
  Single Responsibility: Smart detection of unreachable creatures
  to prevent "Creature not reachable" errors. Uses pathfinding,
  line-of-sight, and tile analysis with aggressive caching.
  
  Depends on: monster_ai_core.lua
  Populates: MonsterAI.Reachability
]]

local H = MonsterAI._helpers
local nowMs            = H.nowMs
local safeGetId        = H.safeGetId
local safeIsDead       = H.safeIsDead
local safeIsRemoved    = H.safeIsRemoved
local safeIsMonster    = H.safeIsMonster
local safeCreatureCall = H.safeCreatureCall
local getClient        = H.getClient
local isCreatureValid  = H.isCreatureValid

-- ============================================================================
-- STATE
-- ============================================================================

MonsterAI.Reachability = MonsterAI.Reachability or {}
local R = MonsterAI.Reachability

R.cache            = {}
R.cacheTime        = {}
R.CACHE_TTL        = 1500
R.BLOCKED_COOLDOWN = 5000
R.blockedCreatures = {}

R.stats = {
  checksPerformed = 0, cacheHits = 0, blocked = 0, reachable = 0,
  byReason = { no_path = 0, blocked_tile = 0, elevation = 0, too_far = 0, no_los = 0 }
}

local DIR_OFFSETS = {
  [0] = {x=0,y=-1}, [1] = {x=1,y=0}, [2] = {x=0,y=1}, [3] = {x=-1,y=0},
  [4] = {x=1,y=-1}, [5] = {x=1,y=1}, [6] = {x=-1,y=1}, [7] = {x=-1,y=-1}
}

-- ============================================================================
-- CORE CHECK
-- ============================================================================

function R.isReachable(creature, forceRecheck)
  if not creature then return false, "invalid", nil end
  if safeIsDead(creature) or safeIsRemoved(creature) then return false, "invalid", nil end

  local id = safeGetId(creature)
  if not id then return false, "invalid", nil end
  local nowt = nowMs()

  -- Cache
  if not forceRecheck then
    local cr = R.cache[id]
    local ct = R.cacheTime[id] or 0
    if cr ~= nil and (nowt - ct) < R.CACHE_TTL then
      R.stats.cacheHits = R.stats.cacheHits + 1
      return cr.reachable, cr.reason, cr.path
    end
    local bl = R.blockedCreatures[id]
    if bl and (nowt - bl.blockedTime) < R.BLOCKED_COOLDOWN then
      if bl.attempts < 3 then bl.attempts = bl.attempts + 1
      else R.stats.cacheHits = R.stats.cacheHits + 1; return false, bl.reason, nil end
    end
  end

  R.stats.checksPerformed = R.stats.checksPerformed + 1

  local playerPos = player and (function() local ok,p = pcall(function() return player:getPosition() end); return ok and p end)()
  local creaturePos = safeCreatureCall(creature, "getPosition", nil)
  if not playerPos or not creaturePos then return R.cacheResult(id, false, "no_position", nil) end

  -- Same floor
  if creaturePos.z ~= playerPos.z then
    R.stats.byReason.elevation = R.stats.byReason.elevation + 1
    return R.cacheResult(id, false, "elevation", nil)
  end

  -- Distance
  local dist = math.max(math.abs(creaturePos.x - playerPos.x), math.abs(creaturePos.y - playerPos.y))
  if dist > 15 then
    R.stats.byReason.too_far = R.stats.byReason.too_far + 1
    return R.cacheResult(id, false, "too_far", nil)
  end

  -- Pathfinding
  local ok, result = pcall(function()
    return findPath(playerPos, creaturePos, 12, {
      ignoreCreatures = true, ignoreNonPathable = false, ignoreCost = true, precision = 1
    })
  end)
  if not ok or not result or #result == 0 then
    R.stats.byReason.no_path = R.stats.byReason.no_path + 1
    R.markBlocked(id, "no_path")
    return R.cacheResult(id, false, "no_path", nil)
  end

  -- Validate first few tiles
  local probe = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
  for i = 1, math.min(5, #result) do
    local off = DIR_OFFSETS[result[i]]
    if off then
      probe = {x = probe.x + off.x, y = probe.y + off.y, z = probe.z}
      local C = getClient()
      local tile = (C and C.getTile) and C.getTile(probe) or (g_map and g_map.getTile and g_map.getTile(probe))
      if tile then
        if tile.isWalkable and not tile:isWalkable() then
          R.stats.byReason.blocked_tile = R.stats.byReason.blocked_tile + 1
          R.markBlocked(id, "blocked_tile")
          return R.cacheResult(id, false, "blocked_tile", nil)
        end
        local items = tile.getItems and tile:getItems()
        if items then
          for _, item in ipairs(items) do
            if item.isNotWalkable and item:isNotWalkable() then
              R.stats.byReason.blocked_tile = R.stats.byReason.blocked_tile + 1
              R.markBlocked(id, "blocked_tile")
              return R.cacheResult(id, false, "blocked_tile", nil)
            end
          end
        end
      end
    end
  end

  -- Line of sight (soft)
  local hasLOS = true
  if dist <= 7 then
    local ok2, los = pcall(function()
      local C = getClient()
      if C and C.isSightClear then return C.isSightClear(playerPos, creaturePos)
      elseif g_map and g_map.isSightClear then return g_map.isSightClear(playerPos, creaturePos) end
      return true
    end)
    if ok2 then hasLOS = los end
  end

  R.stats.reachable = R.stats.reachable + 1
  R.clearBlocked(id)
  return R.cacheResult(id, true, hasLOS and "clear" or "no_los_melee_ok", result)
end

-- ============================================================================
-- CACHE / BLOCKED MANAGEMENT
-- ============================================================================

function R.cacheResult(id, reachable, reason, path)
  R.cache[id]     = { reachable = reachable, reason = reason, path = path }
  R.cacheTime[id] = nowMs()
  if not reachable then R.stats.blocked = R.stats.blocked + 1 end
  return reachable, reason, path
end

function R.markBlocked(id, reason)
  local e = R.blockedCreatures[id]
  if e then e.attempts = e.attempts + 1; e.reason = reason
  else R.blockedCreatures[id] = { blockedTime = nowMs(), attempts = 1, reason = reason } end
end

function R.clearBlocked(id) R.blockedCreatures[id] = nil end
function R.clearCache()      R.cache = {}; R.cacheTime = {} end

function R.cleanup()
  local nowt   = nowMs()
  local expiry = R.BLOCKED_COOLDOWN * 2
  for id, d in pairs(R.blockedCreatures) do
    if (nowt - d.blockedTime) > expiry then R.blockedCreatures[id] = nil end
  end
  for id, t in pairs(R.cacheTime) do
    if (nowt - t) > R.CACHE_TTL * 3 then R.cache[id] = nil; R.cacheTime[id] = nil end
  end
end

-- ============================================================================
-- BATCH & ACCESSORS
-- ============================================================================

function R.filterReachable(creatures)
  local reach, unreach = {}, {}
  for _, c in ipairs(creatures) do
    local ok, reason = R.isReachable(c)
    if ok then reach[#reach+1] = c else unreach[#unreach+1] = { creature = c, reason = reason } end
  end
  return reach, unreach
end

function R.getCachedPath(cid) local c = R.cache[cid]; return c and c.path or nil end

function R.isBlocked(cid)
  local b = R.blockedCreatures[cid]
  if not b then return false end
  if (nowMs() - b.blockedTime) > R.BLOCKED_COOLDOWN then R.blockedCreatures[cid] = nil; return false end
  return true, b.reason, b.attempts
end

function R.validateTarget(creature)
  if not creature then return false, "no_creature" end
  local ok, reason, path = R.isReachable(creature)
  if not ok and EventBus and EventBus.emit then EventBus.emit("reachability:blocked", creature, reason) end
  return ok, reason, path
end

function R.getStats()
  local bc, cc = 0, 0
  for _ in pairs(R.blockedCreatures) do bc = bc + 1 end
  for _ in pairs(R.cache) do cc = cc + 1 end
  return { checksPerformed = R.stats.checksPerformed, cacheHits = R.stats.cacheHits,
           blocked = R.stats.blocked, reachable = R.stats.reachable,
           byReason = R.stats.byReason, blockedCount = bc, cacheSize = cc }
end

-- ============================================================================
-- TICK REGISTRATION
-- ============================================================================

if UnifiedTick and UnifiedTick.register then
  UnifiedTick.register({ id = "monsterai_reachability_cleanup", interval = 10000,
    priority = UnifiedTick.PRIORITY and UnifiedTick.PRIORITY.IDLE or 10,
    callback = function() pcall(R.cleanup) end })
else
  macro(10000, function() pcall(R.cleanup) end)
end

-- EventBus hooks
if EventBus and EventBus.on then
  EventBus.on("player:position", function(newPos, oldPos)
    if oldPos then
      local d = math.max(math.abs(newPos.x - oldPos.x), math.abs(newPos.y - oldPos.y))
      if d > 2 then R.clearCache() end
    end
  end)
  EventBus.on("creature:move", function(creature)
    if creature and safeIsMonster(creature) then
      local id = safeGetId(creature)
      if id and R.blockedCreatures[id] then R.clearBlocked(id); R.cache[id] = nil; R.cacheTime[id] = nil end
    end
  end)
end

if MonsterAI.DEBUG then print("[MonsterAI] Reachability module v3.0 loaded") end
