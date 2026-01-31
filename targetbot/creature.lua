
-- Safe function calls to prevent "attempt to call global function (a nil value)" errors
local SafeCall = SafeCall or require("core.safe_call")

-- Use WeakCache if available for memory-efficient caching
local WC = WeakCache

TargetBot.Creature = {}
TargetBot.Creature.configsCache = (WC and WC.createWeakValues) and WC.createWeakValues() or {}
TargetBot.Creature.cached = 0
TargetBot.Creature.lastCacheClear = 0

-- Cache configuration optimized for memory efficiency (tuned for lower memory usage)
local CACHE_MAX_SIZE = 50   -- Reduced from 100 to limit memory per-character
local CACHE_TTL = 10000      -- Clear cache every 10 seconds to free memory more aggressively
local CACHE_LRU_SIZE = 20    -- Keep only 20 most recent entries when pruning

-- LRU tracking for smart cache eviction
local cacheAccessOrder = {}  -- Array of {name, accessTime}

TargetBot.Creature.resetConfigs = function()
  -- Safety check: targetList may not be initialized yet
  if TargetBot.targetList then
    TargetBot.targetList:destroyChildren()
  end
  TargetBot.Creature.resetConfigsCache()
end

TargetBot.Creature.resetConfigsCache = function()
  -- Recreate with weak values for automatic GC
  TargetBot.Creature.configsCache = (WC and WC.createWeakValues) and WC.createWeakValues() or {}
  TargetBot.Creature.cached = 0
  TargetBot.Creature.lastCacheClear = now
  cacheAccessOrder = {}
end

-- LRU cache eviction - keeps most recently used entries
local function evictOldCacheEntries()
  if TargetBot.Creature.cached < CACHE_MAX_SIZE then return end
  
  -- Sort by access time (most recent first)
  table.sort(cacheAccessOrder, function(a, b)
    return a.time > b.time
  end)
  
  -- Keep only CACHE_LRU_SIZE most recent entries
  local newCache = {}
  local newOrder = {}
  local kept = 0
  
  for i = 1, math.min(CACHE_LRU_SIZE, #cacheAccessOrder) do
    local entry = cacheAccessOrder[i]
    if entry and TargetBot.Creature.configsCache[entry.name] then
      newCache[entry.name] = TargetBot.Creature.configsCache[entry.name]
      newOrder[#newOrder + 1] = entry
      kept = kept + 1
    end
  end
  
  TargetBot.Creature.configsCache = newCache
  cacheAccessOrder = newOrder
  TargetBot.Creature.cached = kept
end

-- Pre-compile regex patterns for faster matching
local compiledPatterns = {}

--[[
  Pattern Matching System:
  - Normal names: "Dragon", "Demon" - matches exactly
  - Wildcards: "Dragon*" - matches names starting with Dragon
  - All monsters: "*" - matches everything
  - Exclusions: "!Dragon" - excludes Dragon from matching
  - Combined: "*, !Dragon, !Demon" - all monsters except Dragon and Demon
  
  The exclusion patterns (!) are processed separately from include patterns.
]]

-- Parse name patterns into include and exclude lists
local function parsePatterns(name)
  local includes = {}
  local excludes = {}
  
  for part in string.gmatch(name, "[^,]+") do
    local trimmed = part:trim():lower()
    if trimmed:sub(1, 1) == "!" then
      -- Exclusion pattern
      local excludeName = trimmed:sub(2):trim()
      if excludeName:len() > 0 then
        -- Convert to regex pattern
        local pattern = "^" .. excludeName:gsub("%*", ".*"):gsub("%?", ".?") .. "$"
        table.insert(excludes, pattern)
      end
    else
      -- Include pattern
      local pattern = "^" .. trimmed:gsub("%*", ".*"):gsub("%?", ".?") .. "$"
      table.insert(includes, pattern)
    end
  end
  
  return includes, excludes
end

TargetBot.Creature.addConfig = function(config, focus)
  if type(config) ~= 'table' or type(config.name) ~= 'string' then
    return error("Invalid targetbot creature config (missing name)")
  end

  -- Defaults: chase by default; keep-distance only when explicitly enabled
  if config.chase == nil then config.chase = true end
  if config.keepDistance == nil then config.keepDistance = false end
  if not config.keepDistanceRange then config.keepDistanceRange = 1 end

  TargetBot.Creature.resetConfigsCache()
  compiledPatterns = {}  -- Clear compiled patterns on config change

  if not config.regex then
    -- Parse patterns into include and exclude lists
    local includes, excludes = parsePatterns(config.name)
    
    -- Build include regex (OR of all include patterns)
    if #includes > 0 then
      config.regex = table.concat(includes, "|")
    else
      config.regex = "^$"  -- Match nothing if no includes
    end
    
    -- Store exclude patterns for later matching
    if #excludes > 0 then
      config.excludeRegex = table.concat(excludes, "|")
    else
      config.excludeRegex = nil
    end
  end

  -- Safety check: targetList must be initialized
  if not TargetBot.targetList then
    warn("[TargetBot] Cannot add config - UI not initialized yet")
    return nil
  end

  local widget = UI.createWidget("TargetBotEntry", TargetBot.targetList)
  widget:setText(config.name)
  widget.value = config

  widget.onDoubleClick = function(entry)
    schedule(20, function()
      TargetBot.Creature.edit(entry.value, function(newConfig)
        entry:setText(newConfig.name)
        entry.value = newConfig
        TargetBot.Creature.resetConfigsCache()
        compiledPatterns = {}
        TargetBot.save()
      end)
    end)
  end

  if focus then
    widget:focus()
    if TargetBot.targetList then
      TargetBot.targetList:ensureChildVisible(widget)
    end
  end
  return widget
end

-- Optimized config lookup with TTL-based cache invalidation and LRU eviction
TargetBot.Creature.getConfigs = function(creature)
  if not creature then return {} end
  
  -- Safety check: targetList may not be initialized yet during startup
  if not TargetBot.targetList then return {} end
  
  -- Check cache TTL
  if now - TargetBot.Creature.lastCacheClear > CACHE_TTL then
    TargetBot.Creature.resetConfigsCache()
  end
  
  local name = creature:getName():trim():lower()
  
  -- Fast path: check cache first
  local cached = TargetBot.Creature.configsCache[name]
  if cached then
    -- Update LRU access time
    for i = 1, #cacheAccessOrder do
      if cacheAccessOrder[i].name == name then
        cacheAccessOrder[i].time = now
        break
      end
    end
    return cached
  end
  
  -- Build configs list with optimized iteration
  local configs = {}
  local configCount = 0
  local children = TargetBot.targetList:getChildren()
  
  for i = 1, #children do
    local config = children[i]
    local regex = config.value.regex
    local excludeRegex = config.value.excludeRegex
    
    -- Check if name matches include pattern
    local match = SafeCall.regexMatch(name, regex)
    if match and match[1] then
      -- Check if name is excluded
      local excluded = false
      if excludeRegex then
        local excludeMatch = SafeCall.regexMatch(name, excludeRegex)
        if excludeMatch and excludeMatch[1] then
          excluded = true
        end
      end
      
      if not excluded then
        configCount = configCount + 1
        configs[configCount] = config.value
      end
    end
  end
  
  -- Cache management with LRU eviction
  evictOldCacheEntries()
  
  TargetBot.Creature.configsCache[name] = configs
  cacheAccessOrder[#cacheAccessOrder + 1] = { name = name, time = now }
  TargetBot.Creature.cached = TargetBot.Creature.cached + 1
  return configs
end

-- Optimized calculateParams with reduced function calls
TargetBot.Creature.calculateParams = function(creature, path)
  local configs = TargetBot.Creature.getConfigs(creature)
  local configCount = #configs
  
  if configCount == 0 then
    return {
      config = nil,
      creature = creature,
      danger = 0,
      priority = 0
    }
  end
  
  -- Fast path for single config (common case)
  if configCount == 1 then
    local config = configs[1]
    return {
      config = config,
      creature = creature,
      danger = config.danger,
      priority = TargetBot.Creature.calculatePriority(creature, config, path)
    }
  end
  
  -- Multiple configs: find highest priority
  local priority = 0
  local danger = 0
  local selectedConfig = nil
  
  for i = 1, configCount do
    local config = configs[i]
    local config_priority = TargetBot.Creature.calculatePriority(creature, config, path)
    if config_priority > priority then
      priority = config_priority
      danger = config.danger  -- Direct access instead of function call
      selectedConfig = config
    end
  end
  
  return {
    config = selectedConfig,
    creature = creature,
    danger = danger,
    priority = priority
  }
end

-- NOTE: calculateDanger was removed (unused) - danger is accessed directly via config.danger
