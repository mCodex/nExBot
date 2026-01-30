setDefaultTab("Tools")

local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Dropper')

  Button
    id: edit
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Edit
]])

local edit = setupUI([[
Panel
  height: 150
    
  Label
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 5
    text-align: center
    text: Trash:

  BotContainer
    id: TrashItems
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 32

  Label
    anchors.top: prev.bottom
    margin-top: 5
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: Use:

  BotContainer
    id: UseItems
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 32

  Label
    anchors.top: prev.bottom
    margin-top: 5
    anchors.left: parent.left
    anchors.right: parent.right
    text-align: center
    text: Drop if below 150 cap:

  BotContainer
    id: CapItems
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    height: 32   
]])
edit:hide()

-- Profile storage helpers
local function getProfileSetting(key)
  if ProfileStorage then
    return ProfileStorage.get(key)
  end
  return storage[key]
end

local function setProfileSetting(key, value)
  if ProfileStorage then
    ProfileStorage.set(key, value)
  else
    storage[key] = value
  end
end

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

local showEdit = false
ui.edit.onClick = function(widget)
  showEdit = not showEdit
  if showEdit then
    edit:show()
  else
    edit:hide()
  end
end

ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  ui.title:setOn(config.enabled)
  saveDropperConfig()
end

UI.Container(function()
    config.trashItems = edit.TrashItems:getItems()
    saveDropperConfig()
    end, true, nil, edit.TrashItems) 
edit.TrashItems:setItems(config.trashItems)

UI.Container(function()
    config.useItems = edit.UseItems:getItems()
    saveDropperConfig()
    end, true, nil, edit.UseItems) 
edit.UseItems:setItems(config.useItems)

UI.Container(function()
    config.capItems = edit.CapItems:getItems()
    saveDropperConfig()
    end, true, nil, edit.CapItems) 
edit.CapItems:setItems(config.capItems)

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

-- State
local lastActionTime = 0
local ACTION_COOLDOWN = 200

-- Check if table has any entries (safe check without using next())
local function hasItems(tbl)
    if not tbl then return false end
    for _ in pairs(tbl) do return true end
    return false
end

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
    
    -- Build lookup tables only if needed
    local trashLookup = hasTrash and buildLookupTable(config.trashItems) or {}
    local useLookup = hasUse and buildLookupTable(config.useItems) or {}
    local capLookup = hasCap and buildLookupTable(config.capItems) or {}
    
    -- Get player position for dropping
    local playerPos = player:getPosition()
    local currentCap = freecap()
    
    -- Scan all open containers
    for _, container in pairs(g_game.getContainers()) do
        for _, item in ipairs(container:getItems()) do
            if item then
                local itemId = item:getId()
                
                -- Priority 1: Trash items (always drop)
                if hasTrash and trashLookup[itemId] then
                    g_game.move(item, playerPos, item:getCount())
                    lastActionTime = now
                    return
                end
                
                -- Priority 2: Use items
                if hasUse and useLookup[itemId] then
                    g_game.use(item)
                    lastActionTime = now
                    return
                end
                
                -- Priority 3: Cap items (drop only if low capacity)
                if hasCap and capLookup[itemId] and currentCap < 150 then
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
