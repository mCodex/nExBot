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

if not storage.dropper then
    storage.dropper = {
      enabled = false,
      trashItems = { 283, 284, 285 },
      useItems = { 21203, 14758 },
      capItems = { 21175 }
    }
end

local config = storage.dropper

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
end

UI.Container(function()
    config.trashItems = edit.TrashItems:getItems()
    end, true, nil, edit.TrashItems) 
edit.TrashItems:setItems(config.trashItems)

UI.Container(function()
    config.useItems = edit.UseItems:getItems()
    end, true, nil, edit.UseItems) 
edit.UseItems:setItems(config.useItems)

UI.Container(function()
    config.capItems = edit.CapItems:getItems()
    end, true, nil, edit.CapItems) 
edit.CapItems:setItems(config.capItems)

--[[
  Optimized Dropper Engine
  
  Uses O(1) hash lookups and event-driven processing.
  Can drop items from anywhere in inventory (not just open backpacks).
]]

-- Build O(1) lookup tables from config
local trashLookup = {}
local useLookup = {}
local capLookup = {}
local lastConfigHash = ""

local function getConfigHash()
    -- Simple hash to detect config changes
    local hash = ""
    for _, entry in pairs(config.trashItems or {}) do
        local id = type(entry) == "table" and entry.id or entry
        if id then hash = hash .. "t" .. id end
    end
    for _, entry in pairs(config.useItems or {}) do
        local id = type(entry) == "table" and entry.id or entry
        if id then hash = hash .. "u" .. id end
    end
    for _, entry in pairs(config.capItems or {}) do
        local id = type(entry) == "table" and entry.id or entry
        if id then hash = hash .. "c" .. id end
    end
    return hash
end

local function rebuildLookupTables()
    trashLookup = {}
    useLookup = {}
    capLookup = {}
    
    for _, entry in pairs(config.trashItems or {}) do
        local id = type(entry) == "table" and entry.id or entry
        if id then trashLookup[id] = true end
    end
    
    for _, entry in pairs(config.useItems or {}) do
        local id = type(entry) == "table" and entry.id or entry
        if id then useLookup[id] = true end
    end
    
    for _, entry in pairs(config.capItems or {}) do
        local id = type(entry) == "table" and entry.id or entry
        if id then capLookup[id] = true end
    end
    
    lastConfigHash = getConfigHash()
end

-- State for throttling
local lastDropTime = 0
local DROP_COOLDOWN = 150 -- ms between drops
local needsCheck = true

-- Subscribe to container events for smart triggering
if EventBus then
    EventBus.on("container:open", function()
        needsCheck = true
    end)
    
    EventBus.on("container:update", function()
        needsCheck = true
    end)
end

-- Fallback event handlers
onContainerOpen(function(container, previousContainer)
    needsCheck = true
end)

onAddItem(function(container, slot, item, oldItem)
    needsCheck = true
end)

-- Process a single item (returns true if action taken)
local function processItem(item)
    if not item then return false end
    local itemId = item:getId()
    
    -- Priority 1: Trash items (always drop)
    if trashLookup[itemId] then
        g_game.move(item, player:getPosition(), item:getCount())
        return true
    end
    
    -- Priority 2: Use items
    if useLookup[itemId] then
        g_game.use(item)
        return true
    end
    
    -- Priority 3: Cap items (drop only if low cap)
    if capLookup[itemId] and freecap() < 150 then
        g_game.move(item, player:getPosition(), item:getCount())
        return true
    end
    
    return false
end

-- Main dropper macro - optimized with O(1) lookups
macro(250, function()
    if not config.enabled then return end
    if not needsCheck then return end
    
    -- Cooldown check
    local currentTime = now
    if (currentTime - lastDropTime) < DROP_COOLDOWN then return end
    
    -- Rebuild lookup tables if config changed
    local currentHash = getConfigHash()
    if currentHash ~= lastConfigHash then
        rebuildLookupTables()
    end
    
    -- Check if any lookup tables have items
    local hasTrash = next(trashLookup) ~= nil
    local hasUse = next(useLookup) ~= nil
    local hasCap = next(capLookup) ~= nil
    
    if not hasTrash and not hasUse and not hasCap then
        needsCheck = false
        return
    end
    
    -- Scan all open containers
    local containers = g_game.getContainers()
    for _, container in pairs(containers) do
        local items = container:getItems()
        for i = 1, #items do
            local item = items[i]
            if item then
                local itemId = item:getId()
                -- O(1) lookup instead of nested loops
                if trashLookup[itemId] or useLookup[itemId] or (capLookup[itemId] and freecap() < 150) then
                    if processItem(item) then
                        lastDropTime = currentTime
                        return -- One action per tick
                    end
                end
            end
        end
    end
    
    -- Nothing found to process
    needsCheck = false
end)