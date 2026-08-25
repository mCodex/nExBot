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

local lookups = {
    trashItems = buildLookupTable(config.trashItems),
    useItems = buildLookupTable(config.useItems),
    capItems = buildLookupTable(config.capItems),
}

local function setItems(key, items)
    config[key] = items or {}
    lookups[key] = buildLookupTable(config[key])
    saveDropperConfig()
end

nExBot.Dropper = {
    getConfig = function() return config end,
    isEnabled = function() return config.enabled == true end,
    setEnabled = function(enabled)
        config.enabled = enabled == true
        saveDropperConfig()
    end,
    setTrashItems = function(items) setItems("trashItems", items) end,
    setUseItems = function(items) setItems("useItems", items) end,
    setCapItems = function(items) setItems("capItems", items) end,
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
