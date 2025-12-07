
TargetBot.Creature = {}
TargetBot.Creature.configsCache = {}
TargetBot.Creature.cached = 0
TargetBot.Creature.lastCacheClear = 0

-- Cache configuration for better performance
local CACHE_MAX_SIZE = 500  -- Reduced from 1000 for faster iteration
local CACHE_TTL = 60000  -- Clear cache every 60 seconds

TargetBot.Creature.resetConfigs = function()
  TargetBot.targetList:destroyChildren()
  TargetBot.Creature.resetConfigsCache()
end

TargetBot.Creature.resetConfigsCache = function()
  TargetBot.Creature.configsCache = {}
  TargetBot.Creature.cached = 0
  TargetBot.Creature.lastCacheClear = now
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
    TargetBot.targetList:ensureChildVisible(widget)
  end
  return widget
end

-- Optimized config lookup with TTL-based cache invalidation
TargetBot.Creature.getConfigs = function(creature)
  if not creature then return {} end
  
  -- Check cache TTL
  if now - TargetBot.Creature.lastCacheClear > CACHE_TTL then
    TargetBot.Creature.resetConfigsCache()
  end
  
  local name = creature:getName():trim():lower()
  
  -- Fast path: check cache first
  local cached = TargetBot.Creature.configsCache[name]
  if cached then
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
    local match = regexMatch(name, regex)
    if match[1] then
      -- Check if name is excluded
      local excluded = false
      if excludeRegex then
        local excludeMatch = regexMatch(name, excludeRegex)
        if excludeMatch[1] then
          excluded = true
        end
      end
      
      if not excluded then
        configCount = configCount + 1
        configs[configCount] = config.value
      end
    end
  end
  
  -- Cache management with size limit
  if TargetBot.Creature.cached >= CACHE_MAX_SIZE then
    TargetBot.Creature.resetConfigsCache()
  end
  
  TargetBot.Creature.configsCache[name] = configs
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

TargetBot.Creature.calculateDanger = function(creature, config, path)
  return config.danger
end
