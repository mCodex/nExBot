--[[
  Unified Creature Cache - Single Source for All Creature Lookups
  
  Consolidates three separate caching systems:
  - SpectatorCache (utils/spectator_cache.lua)
  - CreatureCache (targetbot/target.lua)
  - MonsterCache (targetbot/creature_position.lua)
  
  ARCHITECTURE:
  - Single cache with category views (monsters, players, npcs)
  - Event-driven invalidation (no polling)
  - LRU eviction with configurable max size
  - Object pooling integration for reduced GC pressure
  - Weak table support for automatic memory cleanup (Phase 5)
  
  PERFORMANCE:
  - O(1) lookups by creature ID
  - Lazy category building (only when requested)
  - Automatic cleanup of removed/dead creatures
  
  USAGE:
    local CreatureCache = dofile("core/creature_cache.lua")
    local monsters = CreatureCache.getMonsters()
    local creature = CreatureCache.getById(creatureId)
    local nearest = CreatureCache.getNearestMonster(pos, maxRange)
]]

local CreatureCache = {}

-- ============================================================================
-- CONFIGURATION
-- ============================================================================

CreatureCache.CONFIG = {
  MAX_SIZE = 100,           -- Maximum creatures to cache
  SPECTATOR_RANGE_X = 14,   -- Default spectator range X
  SPECTATOR_RANGE_Y = 11,   -- Default spectator range Y
  CACHE_TTL = 200,          -- Base cache TTL (ms)
  CLEANUP_INTERVAL = 2000,  -- Cleanup interval (ms)
  ENABLE_POOLING = true,    -- Use object pooling for entries
  USE_WEAK_REFS = true      -- Use weak references for creature objects
}

-- ============================================================================
-- INTERNAL STATE
-- ============================================================================

-- Use WeakCache if available for automatic GC cleanup
local WC = WeakCache

local cache = {
  -- Main creature storage: id -> entry (uses weak values for creature refs)
  creatures = (WC and WC.createWeakValues) and WC.createWeakValues() or {},
  
  -- Category caches (lazily built)
  monsters = nil,
  players = nil,
  npcs = nil,
  
  -- Metadata
  lastUpdate = 0,
  lastCleanup = 0,
  categoryDirty = true,
  
  -- LRU tracking
  accessOrder = {},  -- Array of IDs in access order
  accessIndex = {},  -- id -> index in accessOrder
  
  -- Stats
  stats = {
    hits = 0,
    misses = 0,
    evictions = 0,
    cleanups = 0
  }
}

-- Time helper (use ClientHelper for DRY)
local nowMs = ClientHelper and ClientHelper.nowMs or function()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

-- ============================================================================
-- CLIENT HELPERS
-- ============================================================================

local function getClient()
  return ClientService
end

local function getLocalPlayer()
  local Client = getClient()
  if Client and Client.getLocalPlayer then
    return Client.getLocalPlayer()
  elseif g_game and g_game.getLocalPlayer then
    return g_game.getLocalPlayer()
  end
  return nil
end

local function getPlayerPosition()
  local player = getLocalPlayer()
  if not player then return nil end
  local ok, pos = pcall(function() return player:getPosition() end)
  return ok and pos or nil
end

local function getSpectatorsInRange(pos, rangeX, rangeY)
  if not pos then return {} end
  rangeX = rangeX or CreatureCache.CONFIG.SPECTATOR_RANGE_X
  rangeY = rangeY or CreatureCache.CONFIG.SPECTATOR_RANGE_Y
  
  local Client = getClient()
  if Client and Client.getSpectatorsInRange then
    return Client.getSpectatorsInRange(pos, false, rangeX, rangeY) or {}
  elseif g_map and g_map.getSpectatorsInRange then
    return g_map.getSpectatorsInRange(pos, false, rangeX, rangeY) or {}
  end
  return {}
end

-- ============================================================================
-- CREATURE VALIDATION (Safe accessors)
-- ============================================================================

local function safeGetId(creature)
  if not creature then return nil end
  local ok, id = pcall(function() return creature:getId() end)
  return ok and id or nil
end

local function safeIsMonster(creature)
  if not creature then return false end
  local ok, result = pcall(function() return creature:isMonster() end)
  return ok and result or false
end

local function safeIsPlayer(creature)
  if not creature then return false end
  local ok, result = pcall(function() return creature:isPlayer() end)
  return ok and result or false
end

local function safeIsNpc(creature)
  if not creature then return false end
  local ok, result = pcall(function() return creature:isNpc() end)
  return ok and result or false
end

local function safeIsDead(creature)
  if not creature then return true end
  local ok, result = pcall(function() return creature:isDead() end)
  return ok and result or true
end

local function safeIsRemoved(creature)
  if not creature then return true end
  local ok, result = pcall(function() return creature:isRemoved() end)
  return ok and result or true
end

local function safeGetPosition(creature)
  if not creature then return nil end
  local ok, pos = pcall(function() return creature:getPosition() end)
  return ok and pos or nil
end

local function safeGetName(creature)
  if not creature then return nil end
  local ok, name = pcall(function() return creature:getName() end)
  return ok and name or nil
end

local function safeGetHealthPercent(creature)
  if not creature then return 0 end
  local ok, hp = pcall(function() return creature:getHealthPercent() end)
  return ok and hp or 0
end

-- Check if creature is valid and alive
local function isValidCreature(creature)
  if not creature then return false end
  local ok, valid = pcall(function()
    return creature:getId() and not creature:isDead() and not creature:isRemoved()
  end)
  return ok and valid or false
end

-- ============================================================================
-- LRU MANAGEMENT
-- ============================================================================

local function touchLRU(id)
  local idx = cache.accessIndex[id]
  if idx then
    -- Move to end (most recently used)
    table.remove(cache.accessOrder, idx)
    -- Update indices for shifted elements
    for i = idx, #cache.accessOrder do
      cache.accessIndex[cache.accessOrder[i]] = i
    end
  end
  
  -- Add to end
  cache.accessOrder[#cache.accessOrder + 1] = id
  cache.accessIndex[id] = #cache.accessOrder
end

local function evictLRU()
  if #cache.accessOrder == 0 then return end
  
  local evictId = cache.accessOrder[1]
  -- Shift array left (O(n) but only on eviction, not every access)
  for i = 1, #cache.accessOrder - 1 do
    cache.accessOrder[i] = cache.accessOrder[i + 1]
    cache.accessIndex[cache.accessOrder[i]] = i
  end
  cache.accessOrder[#cache.accessOrder] = nil
  cache.accessIndex[evictId] = nil
  
  -- Release entry to pool if configured
  local entry = cache.creatures[evictId]
  if entry and CreatureCache.CONFIG.ENABLE_POOLING and nExBot and nExBot.releaseTable then
    nExBot.releaseTable("creatureCacheEntry", entry)
  end
  
  cache.creatures[evictId] = nil
  cache.categoryDirty = true
  cache.stats.evictions = cache.stats.evictions + 1
end

-- ============================================================================
-- CACHE OPERATIONS
-- ============================================================================

--[[
  Add or update a creature in cache
  @param creature Creature object
  @return entry table or nil
]]
function CreatureCache.set(creature)
  if not isValidCreature(creature) then return nil end
  
  local id = safeGetId(creature)
  if not id then return nil end
  
  local nowt = nowMs()
  
  -- Get or create entry
  local entry = cache.creatures[id]
  if not entry then
    -- Check capacity
    if #cache.accessOrder >= CreatureCache.CONFIG.MAX_SIZE then
      evictLRU()
    end
    
    -- Create new entry (use pool if available)
    if CreatureCache.CONFIG.ENABLE_POOLING and nExBot and nExBot.acquireTable then
      entry = nExBot.acquireTable("creatureCacheEntry")
    else
      entry = {}
    end
    
    cache.creatures[id] = entry
    cache.categoryDirty = true
  end
  
  -- Update entry
  entry.id = id
  entry.creature = creature
  entry.name = safeGetName(creature)
  entry.position = safeGetPosition(creature)
  entry.healthPercent = safeGetHealthPercent(creature)
  entry.isMonster = safeIsMonster(creature)
  entry.isPlayer = safeIsPlayer(creature)
  entry.isNpc = safeIsNpc(creature)
  entry.lastUpdate = nowt
  
  -- Touch LRU
  touchLRU(id)
  
  return entry
end

--[[
  Get creature by ID
  @param id number Creature ID
  @return entry table or nil
]]
function CreatureCache.getById(id)
  local entry = cache.creatures[id]
  if not entry then
    cache.stats.misses = cache.stats.misses + 1
    return nil
  end
  
  -- Validate creature is still valid
  if not isValidCreature(entry.creature) then
    CreatureCache.remove(id)
    cache.stats.misses = cache.stats.misses + 1
    return nil
  end
  
  cache.stats.hits = cache.stats.hits + 1
  touchLRU(id)
  return entry
end

--[[
  Get creature object by ID
  @param id number Creature ID
  @return Creature or nil
]]
function CreatureCache.getCreatureById(id)
  local entry = CreatureCache.getById(id)
  return entry and entry.creature or nil
end

--[[
  Remove creature from cache
  @param id number Creature ID
]]
function CreatureCache.remove(id)
  local entry = cache.creatures[id]
  if entry then
    -- Release to pool
    if CreatureCache.CONFIG.ENABLE_POOLING and nExBot and nExBot.releaseTable then
      nExBot.releaseTable("creatureCacheEntry", entry)
    end
    
    cache.creatures[id] = nil
    
    -- Remove from LRU
    local idx = cache.accessIndex[id]
    if idx then
      table.remove(cache.accessOrder, idx)
      cache.accessIndex[id] = nil
      for i = idx, #cache.accessOrder do
        cache.accessIndex[cache.accessOrder[i]] = i
      end
    end
    
    cache.categoryDirty = true
  end
end

--[[
  Clear entire cache
]]
function CreatureCache.clear()
  -- Release all entries to pool
  if CreatureCache.CONFIG.ENABLE_POOLING and nExBot and nExBot.releaseTable then
    for id, entry in pairs(cache.creatures) do
      nExBot.releaseTable("creatureCacheEntry", entry)
    end
  end
  
  cache.creatures = {}
  cache.monsters = nil
  cache.players = nil
  cache.npcs = nil
  cache.accessOrder = {}
  cache.accessIndex = {}
  cache.categoryDirty = true
end

-- ============================================================================
-- CATEGORY VIEWS
-- ============================================================================

-- Rebuild category caches
local function rebuildCategories()
  if not cache.categoryDirty then return end
  
  cache.monsters = {}
  cache.players = {}
  cache.npcs = {}
  
  for id, entry in pairs(cache.creatures) do
    if entry.isMonster then
      cache.monsters[#cache.monsters + 1] = entry
    elseif entry.isPlayer then
      cache.players[#cache.players + 1] = entry
    elseif entry.isNpc then
      cache.npcs[#cache.npcs + 1] = entry
    end
  end
  
  cache.categoryDirty = false
end

--[[
  Get all cached monsters
  @return array of entries
]]
function CreatureCache.getMonsters()
  rebuildCategories()
  return cache.monsters or {}
end

--[[
  Get all cached players
  @return array of entries
]]
function CreatureCache.getPlayers()
  rebuildCategories()
  return cache.players or {}
end

--[[
  Get all cached NPCs
  @return array of entries
]]
function CreatureCache.getNpcs()
  rebuildCategories()
  return cache.npcs or {}
end

--[[
  Get monster count
  @return number
]]
function CreatureCache.getMonsterCount()
  rebuildCategories()
  return cache.monsters and #cache.monsters or 0
end

-- ============================================================================
-- SPECTATOR UPDATE
-- ============================================================================

--[[
  Update cache with current spectators
  @param rangeX number (optional)
  @param rangeY number (optional)
  @return number creatures updated
]]
function CreatureCache.updateFromSpectators(rangeX, rangeY)
  local playerPos = getPlayerPosition()
  if not playerPos then return 0 end
  
  local spectators = getSpectatorsInRange(playerPos, rangeX, rangeY)
  if not spectators then return 0 end
  
  local updated = 0
  for i = 1, #spectators do
    local creature = spectators[i]
    if CreatureCache.set(creature) then
      updated = updated + 1
    end
  end
  
  cache.lastUpdate = nowMs()
  return updated
end

--[[
  Get spectators with caching (replaces SpectatorCache.getNearby)
  @param rangeX number
  @param rangeY number
  @param ttl number Cache TTL (ms)
  @return array of creatures
]]
function CreatureCache.getNearby(rangeX, rangeY, ttl)
  rangeX = rangeX or CreatureCache.CONFIG.SPECTATOR_RANGE_X
  rangeY = rangeY or CreatureCache.CONFIG.SPECTATOR_RANGE_Y
  ttl = ttl or CreatureCache.CONFIG.CACHE_TTL
  
  local nowt = nowMs()
  
  -- Check if cache is fresh enough
  if (nowt - cache.lastUpdate) < ttl then
    -- Return cached creatures
    local result = {}
    for id, entry in pairs(cache.creatures) do
      if entry.creature and isValidCreature(entry.creature) then
        result[#result + 1] = entry.creature
      end
    end
    cache.stats.hits = cache.stats.hits + 1
    return result
  end
  
  -- Refresh from spectators
  cache.stats.misses = cache.stats.misses + 1
  CreatureCache.updateFromSpectators(rangeX, rangeY)
  
  -- Return creatures
  local result = {}
  for id, entry in pairs(cache.creatures) do
    if entry.creature then
      result[#result + 1] = entry.creature
    end
  end
  return result
end

-- ============================================================================
-- SPATIAL QUERIES
-- ============================================================================

--[[
  Get nearest monster to a position
  @param pos Position
  @param maxRange number (optional)
  @return entry, distance or nil
]]
function CreatureCache.getNearestMonster(pos, maxRange)
  if not pos then return nil, nil end
  maxRange = maxRange or 50
  
  rebuildCategories()
  
  local nearest = nil
  local nearestDist = maxRange + 1
  
  for i = 1, #(cache.monsters or {}) do
    local entry = cache.monsters[i]
    if entry.position then
      local dist = math.max(
        math.abs(entry.position.x - pos.x),
        math.abs(entry.position.y - pos.y)
      )
      if dist < nearestDist then
        nearestDist = dist
        nearest = entry
      end
    end
  end
  
  return nearest, nearestDist
end

--[[
  Get monsters within range
  @param pos Position
  @param range number
  @return array of entries
]]
function CreatureCache.getMonstersInRange(pos, range)
  if not pos then return {} end
  range = range or 10
  
  rebuildCategories()
  
  local result = {}
  for i = 1, #(cache.monsters or {}) do
    local entry = cache.monsters[i]
    if entry.position then
      local dist = math.max(
        math.abs(entry.position.x - pos.x),
        math.abs(entry.position.y - pos.y)
      )
      if dist <= range then
        result[#result + 1] = entry
      end
    end
  end
  
  return result
end

--[[
  Get monsters on same floor
  @param z number Floor level
  @return array of entries
]]
function CreatureCache.getMonstersOnFloor(z)
  rebuildCategories()
  
  local result = {}
  for i = 1, #(cache.monsters or {}) do
    local entry = cache.monsters[i]
    if entry.position and entry.position.z == z then
      result[#result + 1] = entry
    end
  end
  
  return result
end

-- ============================================================================
-- CLEANUP
-- ============================================================================

--[[
  Remove dead and invalid creatures from cache
]]
function CreatureCache.cleanup()
  local nowt = nowMs()
  local removed = 0
  
  for id, entry in pairs(cache.creatures) do
    if not isValidCreature(entry.creature) then
      CreatureCache.remove(id)
      removed = removed + 1
    end
  end
  
  cache.lastCleanup = nowt
  cache.stats.cleanups = cache.stats.cleanups + 1
  
  return removed
end

-- ============================================================================
-- STATISTICS
-- ============================================================================

--[[
  Get cache statistics
  @return table
]]
function CreatureCache.getStats()
  local total = cache.stats.hits + cache.stats.misses
  return {
    hits = cache.stats.hits,
    misses = cache.stats.misses,
    evictions = cache.stats.evictions,
    cleanups = cache.stats.cleanups,
    hitRate = total > 0 and (cache.stats.hits / total) or 0,
    size = #cache.accessOrder,
    maxSize = CreatureCache.CONFIG.MAX_SIZE,
    monstersCount = cache.monsters and #cache.monsters or 0,
    playersCount = cache.players and #cache.players or 0
  }
end

--[[
  Reset statistics
]]
function CreatureCache.resetStats()
  cache.stats.hits = 0
  cache.stats.misses = 0
  cache.stats.evictions = 0
  cache.stats.cleanups = 0
end

-- ============================================================================
-- EVENTBUS INTEGRATION
-- Auto-update cache on creature events
-- ============================================================================

if EventBus and EventBus.on then
  -- Update cache when creature appears
  EventBus.on("creature:appear", function(creature)
    CreatureCache.set(creature)
  end, 10)  -- Lower priority
  
  -- Remove from cache when creature disappears
  EventBus.on("creature:disappear", function(creature)
    local id = safeGetId(creature)
    if id then
      CreatureCache.remove(id)
    end
  end, 10)
  
  -- Update health when it changes
  EventBus.on("creature:health", function(creature, percent)
    local id = safeGetId(creature)
    if id and cache.creatures[id] then
      cache.creatures[id].healthPercent = percent
    end
  end, 10)
  
  -- Clear cache on player position change (optional, for strict freshness)
  -- EventBus.on("player:move", function()
  --   cache.categoryDirty = true
  -- end, 5)
end

-- ============================================================================
-- BACKWARDS COMPATIBILITY
-- Provide same API as old SpectatorCache
-- ============================================================================

CreatureCache.SpectatorCompat = {
  getNearby = function(rx, ry, ttl)
    return CreatureCache.getNearby(rx, ry, ttl)
  end,
  clear = function()
    CreatureCache.clear()
  end,
  getStats = function()
    return CreatureCache.getStats()
  end
}

return CreatureCache
