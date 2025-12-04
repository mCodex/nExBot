--[[
  NexBot Configuration System
  Centralized configuration management with persistence
  
  Features:
  - Schema-based validation
  - Multiple profile support
  - Auto-save functionality
  - Migration support
  
  Author: NexBot Team
  Version: 1.0.0
]]

local ConfigManager = {
  configs = {},
  profiles = {},
  activeProfile = "default",
  autoSaveInterval = 30000, -- 30 seconds
  lastSave = 0,
  dirty = false,
  
  -- Default configuration values
  defaults = {
    general = {
      enabled = true,
      debugMode = false,
      showNotifications = true,
      language = "en"
    },
    
    healing = {
      enabled = true,
      manaPotion = {
        item = 268,
        trigger = 50,
        enabled = true
      },
      healthPotion = {
        item = 266,
        trigger = 70,
        enabled = true
      },
      spells = {}
    },
    
    combat = {
      enabled = true,
      autoAttack = true,
      autoHaste = true,
      keepManaFor = {
        healing = 50,
        utility = 20
      }
    },
    
    cavebot = {
      enabled = false,
      walkDelay = 0,
      nodeDelay = 0,
      pingCompensation = true,
      pathfinding = {
        algorithm = "astar",
        maxNodes = 5000,
        cacheEnabled = true,
        cacheTTL = 10000
      }
    },
    
    targeting = {
      enabled = true,
      priorityMode = "danger",
      multiTarget = true,
      maxTargets = 8,
      avoidPlayers = true
    },
    
    luring = {
      enabled = false,
      pattern = "circle",
      minCreatures = 3,
      maxCreatures = 8,
      radius = 5,
      safetyMargin = 3
    },
    
    memory = {
      gcInterval = 30000,
      poolingEnabled = true,
      weakReferences = true,
      maxCacheSize = 1000
    },
    
    ui = {
      theme = "dark",
      scale = 1.0,
      opacity = 0.9,
      position = { x = 100, y = 100 }
    }
  },
  
  -- Config schema for validation
  schema = {
    general = {
      enabled = "boolean",
      debugMode = "boolean",
      showNotifications = "boolean",
      language = "string"
    },
    healing = {
      enabled = "boolean"
    },
    combat = {
      enabled = "boolean",
      autoAttack = "boolean",
      autoHaste = "boolean"
    },
    cavebot = {
      enabled = "boolean",
      walkDelay = "number",
      nodeDelay = "number"
    },
    targeting = {
      enabled = "boolean",
      priorityMode = "string",
      multiTarget = "boolean"
    }
  }
}

-- Initialize configuration
function ConfigManager:initialize()
  -- Load saved configs
  self:load()
  
  -- Start auto-save timer
  self:startAutoSave()
  
  return self
end

-- Get a configuration value
function ConfigManager:get(path, default)
  local parts = self:splitPath(path)
  local current = self.configs
  
  for _, part in ipairs(parts) do
    if type(current) ~= "table" then
      return default
    end
    current = current[part]
  end
  
  if current == nil then
    -- Check defaults
    current = self.defaults
    for _, part in ipairs(parts) do
      if type(current) ~= "table" then
        return default
      end
      current = current[part]
    end
  end
  
  return current ~= nil and current or default
end

-- Set a configuration value
function ConfigManager:set(path, value)
  local parts = self:splitPath(path)
  local current = self.configs
  
  -- Create nested tables as needed
  for i = 1, #parts - 1 do
    local part = parts[i]
    if current[part] == nil then
      current[part] = {}
    elseif type(current[part]) ~= "table" then
      current[part] = {}
    end
    current = current[part]
  end
  
  -- Set the value
  local key = parts[#parts]
  local oldValue = current[key]
  current[key] = value
  
  -- Mark as dirty
  self.dirty = true
  
  -- Emit change event
  if NexBot and NexBot.EventBus then
    NexBot.EventBus:emit("CONFIG_CHANGED", path, value, oldValue)
  end
  
  return self
end

-- Split path string into parts
function ConfigManager:splitPath(path)
  local parts = {}
  for part in string.gmatch(path, "[^%.]+") do
    table.insert(parts, part)
  end
  return parts
end

-- Validate configuration against schema
function ConfigManager:validate(config, schema)
  schema = schema or self.schema
  local errors = {}
  
  local function validateValue(path, value, expectedType)
    local actualType = type(value)
    if actualType ~= expectedType then
      table.insert(errors, string.format(
        "Invalid type for '%s': expected %s, got %s",
        path, expectedType, actualType
      ))
      return false
    end
    return true
  end
  
  local function validateTable(path, tbl, schemaTable)
    for key, expectedType in pairs(schemaTable) do
      local fullPath = path ~= "" and (path .. "." .. key) or key
      local value = tbl[key]
      
      if value ~= nil then
        if type(expectedType) == "string" then
          validateValue(fullPath, value, expectedType)
        elseif type(expectedType) == "table" then
          if type(value) == "table" then
            validateTable(fullPath, value, expectedType)
          else
            table.insert(errors, string.format(
              "Invalid type for '%s': expected table, got %s",
              fullPath, type(value)
            ))
          end
        end
      end
    end
  end
  
  validateTable("", config, schema)
  
  return #errors == 0, errors
end

-- Load configuration from storage
function ConfigManager:load()
  local success, err = pcall(function()
    local savedConfig = storage.nexbotConfig
    if savedConfig then
      -- Deep merge with defaults
      self.configs = self:deepMerge(self.defaults, savedConfig)
    else
      -- Use defaults
      self.configs = self:deepCopy(self.defaults)
    end
    
    -- Load profiles
    self.profiles = storage.nexbotProfiles or { default = {} }
    self.activeProfile = storage.nexbotActiveProfile or "default"
  end)
  
  if not success then
    warn("[NexBot Config] Failed to load configuration: " .. tostring(err))
    self.configs = self:deepCopy(self.defaults)
  end
  
  self.dirty = false
  return self
end

-- Save configuration to storage
function ConfigManager:save()
  local success, err = pcall(function()
    storage.nexbotConfig = self.configs
    storage.nexbotProfiles = self.profiles
    storage.nexbotActiveProfile = self.activeProfile
  end)
  
  if not success then
    warn("[NexBot Config] Failed to save configuration: " .. tostring(err))
    return false
  end
  
  self.lastSave = os.time()
  self.dirty = false
  
  if NexBot and NexBot.EventBus then
    NexBot.EventBus:emit("CONFIG_SAVED")
  end
  
  return true
end

-- Start auto-save timer
function ConfigManager:startAutoSave()
  schedule(self.autoSaveInterval, function()
    if self.dirty then
      self:save()
    end
    self:startAutoSave() -- Reschedule
  end)
end

-- Deep copy a table
function ConfigManager:deepCopy(source)
  if type(source) ~= "table" then
    return source
  end
  
  local copy = {}
  for key, value in pairs(source) do
    copy[key] = self:deepCopy(value)
  end
  
  return copy
end

-- Deep merge two tables
function ConfigManager:deepMerge(base, override)
  if type(base) ~= "table" then
    return override
  end
  
  if type(override) ~= "table" then
    return override
  end
  
  local result = self:deepCopy(base)
  
  for key, value in pairs(override) do
    if type(value) == "table" and type(result[key]) == "table" then
      result[key] = self:deepMerge(result[key], value)
    else
      result[key] = value
    end
  end
  
  return result
end

-- Profile management
function ConfigManager:createProfile(name)
  if self.profiles[name] then
    return false, "Profile already exists"
  end
  
  self.profiles[name] = self:deepCopy(self.defaults)
  self.dirty = true
  
  return true
end

function ConfigManager:deleteProfile(name)
  if name == "default" then
    return false, "Cannot delete default profile"
  end
  
  if not self.profiles[name] then
    return false, "Profile not found"
  end
  
  self.profiles[name] = nil
  
  if self.activeProfile == name then
    self.activeProfile = "default"
    self.configs = self:deepMerge(self.defaults, self.profiles["default"] or {})
  end
  
  self.dirty = true
  return true
end

function ConfigManager:switchProfile(name)
  if not self.profiles[name] then
    return false, "Profile not found"
  end
  
  -- Save current profile
  self.profiles[self.activeProfile] = self:deepCopy(self.configs)
  
  -- Switch to new profile
  self.activeProfile = name
  self.configs = self:deepMerge(self.defaults, self.profiles[name])
  
  self.dirty = true
  
  if NexBot and NexBot.EventBus then
    NexBot.EventBus:emit("PROFILE_CHANGED", name)
  end
  
  return true
end

function ConfigManager:getProfileList()
  local list = {}
  for name, _ in pairs(self.profiles) do
    table.insert(list, name)
  end
  table.sort(list)
  return list
end

-- Reset to defaults
function ConfigManager:resetToDefaults(section)
  if section then
    local parts = self:splitPath(section)
    local defaultValue = self.defaults
    
    for _, part in ipairs(parts) do
      if type(defaultValue) == "table" then
        defaultValue = defaultValue[part]
      else
        return false, "Invalid section"
      end
    end
    
    self:set(section, self:deepCopy(defaultValue))
  else
    self.configs = self:deepCopy(self.defaults)
    self.dirty = true
  end
  
  return true
end

-- Export configuration
function ConfigManager:export()
  return json.encode(self.configs)
end

-- Import configuration
function ConfigManager:import(jsonString)
  local success, data = pcall(json.decode, jsonString)
  if not success then
    return false, "Invalid JSON"
  end
  
  local valid, errors = self:validate(data)
  if not valid then
    return false, errors
  end
  
  self.configs = self:deepMerge(self.defaults, data)
  self.dirty = true
  
  return true
end

-- Legacy compatibility - nexBotConfigSave function
function nexBotConfigSave(section, data)
  if section and data then
    ConfigManager:set(section, data)
  end
  ConfigManager:save()
end

return ConfigManager
