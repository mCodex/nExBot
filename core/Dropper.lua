local SharedHelpers = nExBot.SharedHelpers
if not SharedHelpers then
  warn("[Dropper] SharedHelpers not loaded")
  return
end
local getProfileSetting = SharedHelpers.getProfileSetting
local setProfileSetting = SharedHelpers.setProfileSetting

-- Load dropper config from profile storage
local config = getProfileSetting("dropper") or {
  enabled = false,
  trashItems = { 283, 284, 285 },
  useItems = { 21203, 14758 },
  capItems = { 21175 }
}

-- Helper to save config changes
local function saveDropperConfig()
  setProfileSetting("dropper", config)
end

--[[
  Optimized Dropper Engine
  Uses O(1) hash lookups for fast item detection.
]]

-- Build lookup tables from config items
local function buildLookupTable(items)
    local lookup = {}
    if not items then return lookup end
    for _, entry in pairs(items) do
        local id = type(entry) == "table" and entry.id or entry
        if id then lookup[id] = true end
    end
    return lookup
end

local BEHAVIOR_KEYS = { trash = "trashItems", use = "useItems", lowCap = "capItems" }
local KEY_BEHAVIORS = { trashItems = "trash", useItems = "use", capItems = "lowCap" }
local revision = 0

local function normalizedId(entry)
  local id = type(entry) == "table" and entry.id or entry
  id = tonumber(id)
  if not id or id <= 0 or id ~= math.floor(id) then return nil end
  return id
end

local function findItem(itemId)
  for key, behavior in pairs(KEY_BEHAVIORS) do
    for index, entry in ipairs(config[key] or {}) do
      if normalizedId(entry) == itemId then return key, behavior, index end
    end
  end
end

local lookups = {
    trashItems = buildLookupTable(config.trashItems),
    useItems = buildLookupTable(config.useItems),
    capItems = buildLookupTable(config.capItems),
}

local function setItems(key, items)
    config[key] = items or {}
    lookups[key] = buildLookupTable(config[key])
    saveDropperConfig()
    revision = revision + 1
end

nExBot.Dropper = {
    getConfig = function() return config end,
    isEnabled = function() return config.enabled == true end,
    setEnabled = function(enabled)
        config.enabled = enabled == true
        revision = revision + 1
        saveDropperConfig()
    end,
    setTrashItems = function(items) setItems("trashItems", items) end,
    setUseItems = function(items) setItems("useItems", items) end,
    setCapItems = function(items) setItems("capItems", items) end,
    getProjection = function()
        local rows = {}
        for _, key in ipairs({ "trashItems", "useItems", "capItems" }) do
            for _, entry in ipairs(config[key] or {}) do
                local id = normalizedId(entry)
                if id then rows[#rows + 1] = { id = id, behavior = KEY_BEHAVIORS[key], revision = revision } end
            end
        end
        return { revision = revision, enabled = config.enabled == true, lowCap = 150, rows = rows }
    end,
    addItem = function(itemId, behavior)
        itemId = normalizedId(itemId)
        local key = BEHAVIOR_KEYS[behavior]
        if not itemId or not key or findItem(itemId) then return false end
        local items = config[key] or {}
        items[#items + 1] = itemId
        setItems(key, items)
        return true
    end,
    removeItem = function(itemId)
        itemId = normalizedId(itemId)
        if not itemId then return false end
        local key, _, index = findItem(itemId)
        if not key then return false end
        table.remove(config[key], index)
        setItems(key, config[key])
        return true
    end,
    setBehavior = function(itemId, behavior)
        itemId = normalizedId(itemId)
        local destination = BEHAVIOR_KEYS[behavior]
        if not itemId then return false end
        local source, currentBehavior, index = findItem(itemId)
        if not source or not destination then return false end
        if currentBehavior == behavior then return true end
        table.remove(config[source], index)
        config[destination] = config[destination] or {}
        config[destination][#config[destination] + 1] = itemId
        lookups[source] = buildLookupTable(config[source])
        setItems(destination, config[destination])
        return true
    end,
    updateItem = function(itemId, nextItemId, behavior)
        itemId = normalizedId(itemId)
        nextItemId = normalizedId(nextItemId)
        local destination = BEHAVIOR_KEYS[behavior]
        if not itemId then return false end
        local source, _, index = findItem(itemId)
        local duplicateKey = nextItemId and findItem(nextItemId)
        if not source or not destination or (duplicateKey and nextItemId ~= itemId) then return false end

        if source == destination then
            config[source][index] = nextItemId
        else
            table.remove(config[source], index)
            config[destination] = config[destination] or {}
            config[destination][#config[destination] + 1] = nextItemId
        end
        lookups[source] = buildLookupTable(config[source])
        lookups[destination] = buildLookupTable(config[destination])
        revision = revision + 1
        saveDropperConfig()
        return true
    end,
}

-- State
local lastActionTime = 0
local ACTION_COOLDOWN = 200

-- Dropper handler function (shared by UnifiedTick and fallback macro)
local function dropperHandler()
    if not config.enabled then return end
    
    -- Cooldown between actions
    if (now - lastActionTime) < ACTION_COOLDOWN then return end
    
    -- Check if anything is configured (simple length check)
    local hasTrash = config.trashItems and #config.trashItems > 0
    local hasUse = config.useItems and #config.useItems > 0
    local hasCap = config.capItems and #config.capItems > 0
    
    if not hasTrash and not hasUse and not hasCap then
        return
    end
    
    -- Get player position for dropping
    local playerPos = player:getPosition()
    local currentCap = freecap()
    
    -- Scan all open containers
    for _, container in pairs(g_game.getContainers()) do
        for _, item in ipairs(container:getItems()) do
            if item then
                local itemId = item:getId()
                
                -- Priority 1: Trash items (always drop)
                if hasTrash and lookups.trashItems[itemId] then
                    g_game.move(item, playerPos, item:getCount())
                    lastActionTime = now
                    return
                end
                
                -- Priority 2: Use items
                if hasUse and lookups.useItems[itemId] then
                    g_game.use(item)
                    lastActionTime = now
                    return
                end
                
                -- Priority 3: Cap items (drop only if low capacity)
                if hasCap and lookups.capItems[itemId] and currentCap < 150 then
                    g_game.move(item, playerPos, item:getCount())
                    lastActionTime = now
                    return
                end
            end
        end
    end
end

-- Main dropper macro - use UnifiedTick if available
if UnifiedTick and UnifiedTick.register then
  UnifiedTick.register("dropper", {
    interval = 250,
    priority = UnifiedTick.Priority.LOW,
    handler = dropperHandler,
    group = "tools"
  })
else
  macro(250, dropperHandler)
end
