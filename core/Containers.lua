--[[
  Container Panel - Advanced Container Management System
  
  Features:
  - Open All: Opens main BP + all nested containers (auto-minimized)
  - Reopen: Closes all and reopens from back slot
  - Close All: Closes all open containers
  - Min/Max: Minimizes/Maximizes all containers
  - Setup: Configure containers with custom names and item sorting
  - Sort Items: Automatically moves items to designated containers
  - Keep Open: Force containers to stay open
  - Rename: Custom names for container windows
  
  All operations use BFS (Breadth-First Search) to find nested containers.
  Containers are auto-minimized after opening for cleaner UI.
  
  Architecture: DRY, SOLID, SRP principles with pure functions where possible.
]]

setDefaultTab("Tools")
local panelName = "containerPanel"

-- ============================================================================
-- CONSTANTS
-- ============================================================================
local PURSE_ITEM_ID = 23396
local LOOT_BAG_ITEM_ID = 23721

-- ============================================================================
-- DEFAULT CONFIGURATION
-- ============================================================================
local DEFAULT_CONTAINER_LIST = {
    {
        name = "Main Backpack",
        enabled = true,
        itemId = 2854,
        minimize = false,
        openNested = true,
        items = {}
    },
    {
        name = "Supplies",
        enabled = true,
        itemId = 2866,
        minimize = true,
        openNested = false,
        items = { 3155, 3161, 3180 }  -- Example: mana potions, runes
    }
}

-- Default config structure
local DEFAULT_CONFIG = {
    purse = true,
    autoMinimize = true,
    autoOpenOnLogin = false,
    sortEnabled = false,
    forceOpen = false,
    renameEnabled = false,
    lootBag = false,
    containerList = DEFAULT_CONTAINER_LIST,
    windowHeight = 200
}

-- Deep clone utility
local function deepClone(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do
        copy[k] = deepClone(v)
    end
    return copy
end

-- ============================================================================
-- STORAGE & STATE (Per-Character with CharacterDB)
-- ============================================================================

-- Internal state (not persisted)
local _configData = nil
local _saveTimer = nil

-- Schedule save to CharacterDB (debounced)
local function scheduleSave()
    if not CharacterDB or not CharacterDB.isReady or not CharacterDB.isReady() then return end
    if not _configData then return end
    if _saveTimer then removeEvent(_saveTimer) end
    _saveTimer = schedule(300, function()
        _saveTimer = nil
        CharacterDB.setModule("containers", _configData)
    end)
end

-- Initialize config from CharacterDB with migration from legacy storage
local function initConfig()
    local cfg = {}
    
    -- Try to load from CharacterDB first
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
        cfg = CharacterDB.getModule("containers") or {}
        
        -- Migration: if CharacterDB has never been initialized (no _migrated flag) 
        -- and legacy storage has data, migrate once
        if not cfg._migrated and storage[panelName] then
            local legacy = storage[panelName]
            if legacy.containerList and #legacy.containerList > 0 then
                -- Migrate from legacy storage
                cfg = deepClone(legacy)
            end
            -- Mark as migrated so we don't overwrite user deletions
            cfg._migrated = true
            CharacterDB.setModule("containers", cfg)
        end
    else
        -- Fallback to legacy storage (CharacterDB not ready yet)
        if storage[panelName] and type(storage[panelName]) == "table" then
            cfg = storage[panelName]
        end
    end
    
    -- Ensure all required fields exist (migration for old configs)
    for key, defaultValue in pairs(DEFAULT_CONFIG) do
        if cfg[key] == nil then
            cfg[key] = type(defaultValue) == "table" and deepClone(defaultValue) or defaultValue
        end
    end
    
    _configData = cfg
    return cfg
end

-- Create a proxy that auto-saves to CharacterDB on changes
local function createConfigProxy()
    return setmetatable({}, {
        __index = function(t, k)
            if not _configData then initConfig() end
            return _configData[k]
        end,
        __newindex = function(t, k, v)
            if not _configData then initConfig() end
            _configData[k] = v
            scheduleSave()
        end,
        __pairs = function(t) 
            if not _configData then initConfig() end
            return pairs(_configData) 
        end,
        __ipairs = function(t) 
            if not _configData then initConfig() end
            return ipairs(_configData) 
        end,
    })
end

-- Initialize config now
initConfig()
local config = createConfigProxy()

-- Force save function (call after modifying nested tables like containerList)
local function saveConfig()
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() and _configData then
        CharacterDB.setModule("containers", _configData)
    end
end

-- Forward declaration for UI sync functions
local syncUIWithConfig
local refreshContainerList

UI.Separator()
local containerUI = setupUI([[
Panel
  height: 110

  Label
    text-align: center
    text: Container Panel
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    font: verdana-11px-rounded

  BotSwitch
    id: openAll
    !text: tr('Auto Open')
    anchors.top: prev.bottom
    anchors.left: parent.left
    width: 90
    margin-top: 3
    text-align: center
    font: verdana-11px-rounded

  Button
    id: setupBtn
    !text: tr('Setup')
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 2
    height: 17
    font: verdana-11px-rounded

  Button
    id: reopenAll
    !text: tr('Reopen All')
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 2
    height: 17
    font: verdana-11px-rounded

  Button
    id: closeAll
    !text: tr('Close All')
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 2
    height: 17
    font: verdana-11px-rounded

  Button
    id: minimizeAll
    !text: tr('Minimize All')
    anchors.top: prev.bottom
    anchors.left: parent.left
    width: 90
    margin-top: 2
    height: 17
    font: verdana-11px-rounded

  Button
    id: maximizeAll
    !text: tr('Maximize All')
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 2
    height: 17
    font: verdana-11px-rounded

  BotSwitch
    id: purseSwitch
    anchors.top: minimizeAll.bottom
    anchors.left: parent.left
    width: 90
    margin-top: 3
    text-align: center
    !text: tr('Open Purse')
    font: verdana-11px-rounded

  BotSwitch
    id: autoMinSwitch
    anchors.top: minimizeAll.bottom
    anchors.left: prev.right
    anchors.right: parent.right
    margin-top: 3
    margin-left: 2
    text-align: center
    !text: tr('Auto Min')
    font: verdana-11px-rounded
  ]])
containerUI:setId(panelName)

-- Set tooltips programmatically for better control
containerUI.openAll:setTooltip("When enabled, automatically opens all containers on re-login\n(Toggle ON to enable auto-open on each login)")
containerUI.setupBtn:setTooltip("Configure container names, sorting rules, and behavior")
containerUI.reopenAll:setTooltip("Close all containers and reopen from back slot")
containerUI.closeAll:setTooltip("Close all open containers")
containerUI.minimizeAll:setTooltip("Minimize all container windows")
containerUI.maximizeAll:setTooltip("Maximize all container windows")
containerUI.purseSwitch:setTooltip("Also open the purse when reopening")
containerUI.autoMinSwitch:setTooltip("Automatically minimize containers after opening")

-- Sync UI with config (call on init and when CharacterDB becomes ready)
syncUIWithConfig = function()
    if containerUI then
        containerUI.openAll:setOn(config.autoOpenOnLogin == true)
        containerUI.purseSwitch:setOn(config.purse == true)
        containerUI.autoMinSwitch:setOn(config.autoMinimize ~= false)
    end
end

-- Initial sync
syncUIWithConfig()

-- Delayed re-sync to ensure CharacterDB is ready
-- (In case the player wasn't fully available at init time)
schedule(500, function()
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
        -- Reinitialize config from CharacterDB
        initConfig()
        syncUIWithConfig()
        -- Refresh setup window if it exists
        if setupWindow then
            if refreshContainerList then refreshContainerList() end
            -- Sync setup window checkboxes
            setupWindow.sortEnabled:setChecked(config.sortEnabled == true)
            setupWindow.forceOpen:setChecked(config.forceOpen == true)
            setupWindow.renameEnabled:setChecked(config.renameEnabled == true)
            setupWindow.lootBag:setChecked(config.lootBag == true)
        end
    end
end)

-- ============================================================================
-- SETUP WINDOW UI DEFINITION
-- ============================================================================
g_ui.loadUIFromString([[
ContainerEntry < Label
  background-color: alpha
  text-offset: 20 2
  focusable: true
  height: 18
  font: verdana-11px-rounded

  CheckBox
    id: enabled
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: 15
    height: 15
    margin-left: 2

  $focus:
    background-color: #00000066

  Button
    id: minimize
    !text: tr('M')
    anchors.right: nested.left
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 2
    width: 16
    height: 16

  Button
    id: nested
    !text: tr('N')
    anchors.right: remove.left
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 2
    width: 16
    height: 16

  Button
    id: remove
    !text: tr('X')
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 20
    width: 16
    height: 16

ContainerSetupWindow < MainWindow
  !text: tr('Container Setup')
  size: 550 220
  @onEscape: self:hide()

  TextList
    id: containerList
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: separator.top
    width: 210
    margin-bottom: 8
    margin-top: 3
    margin-left: 3
    vertical-scrollbar: containerListScrollBar

  VerticalScrollBar
    id: containerListScrollBar
    anchors.top: containerList.top
    anchors.bottom: containerList.bottom
    anchors.right: containerList.right
    step: 18
    pixels-scroll: true

  VerticalSeparator
    id: sep
    anchors.top: parent.top
    anchors.left: containerList.right
    anchors.bottom: separator.top
    margin-top: 3
    margin-bottom: 8
    margin-left: 8

  Label
    id: lblName
    anchors.left: sep.right
    anchors.top: sep.top
    width: 65
    text: Name:
    margin-left: 10
    margin-top: 3
    font: verdana-11px-rounded

  TextEdit
    id: containerName
    anchors.left: lblName.right
    anchors.top: sep.top
    anchors.right: parent.right
    margin-right: 8
    font: verdana-11px-rounded

  Label
    id: lblContainer
    anchors.left: lblName.left
    anchors.top: containerName.bottom
    width: 65
    text: Container:
    margin-top: 8
    font: verdana-11px-rounded

  BotItem
    id: containerId
    anchors.left: containerName.left
    anchors.top: lblContainer.top
    margin-top: -3

  Button
    id: addContainer
    anchors.left: containerId.right
    anchors.top: containerId.top
    margin-left: 8
    text: Add/Update
    width: 90
    height: 20
    font: verdana-11px-rounded

  Label
    id: lblItems
    anchors.left: lblName.left
    anchors.top: containerId.bottom
    width: 65
    text: Items:
    margin-top: 8
    font: verdana-11px-rounded

  BotContainer
    id: itemsList
    anchors.left: containerName.left
    anchors.top: lblItems.top
    anchors.right: parent.right
    anchors.bottom: separator.top
    margin-right: 8
    margin-bottom: 8
    margin-top: -3

  HorizontalSeparator
    id: separator
    anchors.right: parent.right
    anchors.left: parent.left
    anchors.bottom: closeBtn.top
    margin-bottom: 8

  CheckBox
    id: sortEnabled
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    text: Sort Items
    tooltip: Automatically move items to designated containers
    width: 80
    height: 15
    margin-left: 8
    font: verdana-11px-rounded

  CheckBox
    id: forceOpen
    anchors.left: prev.right
    anchors.bottom: parent.bottom
    text: Keep Open
    tooltip: Force containers to stay open
    width: 85
    height: 15
    margin-left: 10
    font: verdana-11px-rounded

  CheckBox
    id: renameEnabled
    anchors.left: prev.right
    anchors.bottom: parent.bottom
    text: Rename
    tooltip: Rename container windows with custom names
    width: 70
    height: 15
    margin-left: 10
    font: verdana-11px-rounded

  CheckBox
    id: lootBag
    anchors.left: prev.right
    anchors.bottom: parent.bottom
    text: Loot Bag
    tooltip: Also manage loot bag
    width: 75
    height: 15
    margin-left: 10
    font: verdana-11px-rounded

  Button
    id: closeBtn
    !text: tr('Close')
    font: verdana-11px-rounded
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    size: 50 20

  ResizeBorder
    id: bottomResizeBorder
    anchors.fill: separator
    height: 3
    minimum: 180
    maximum: 350
    margin-left: 3
    margin-right: 3
    background: #ffffff44
]])

-- ============================================================================
-- SETUP WINDOW INSTANCE AND LOGIC
-- ============================================================================
local setupWindow = nil
local selectedContainerIndex = nil

-- Pure function: Extract item IDs from container items table
local function extractItemIds(items)
    local ids = {}
    for _, entry in ipairs(items) do
        if type(entry) == "number" then
            ids[#ids + 1] = entry
        elseif type(entry) == "table" and entry.id then
            ids[#ids + 1] = entry.id
        end
    end
    return ids
end

-- Pure function: Find container entry by item ID
local function findContainerByItemId(list, itemId)
    for index, entry in ipairs(list) do
        if entry.itemId == itemId then
            return index, entry
        end
    end
    return nil, nil
end

-- Pure function: Check if item should go to container
local function shouldItemGoToContainer(itemId, containerEntry)
    if not containerEntry or not containerEntry.items then return false end
    local items = extractItemIds(containerEntry.items)
    for _, id in ipairs(items) do
        if id == itemId then return true end
    end
    return false
end

-- Refresh the container list UI
local function refreshContainerList()
    if not setupWindow then return end
    
    local list = setupWindow.containerList
    list:destroyChildren()
    
    for index, entry in ipairs(config.containerList) do
        local label = g_ui.createWidget("ContainerEntry", list)
        label:setText(entry.name or "Container")
        label.enabled:setChecked(entry.enabled)
        
        -- Color coding for buttons
        label.minimize:setColor(entry.minimize and '#00FF00' or '#FF6666')
        label.minimize:setTooltip(entry.minimize and 'Opens Minimized' or 'Opens Normal')
        
        label.nested:setColor(entry.openNested and '#00FF00' or '#FF6666')
        label.nested:setTooltip(entry.openNested and 'Opens Nested' or 'No Nested')
        
        -- Selection handler
        label.onMouseRelease = function()
            selectedContainerIndex = index
            setupWindow.containerId:setItemId(entry.itemId or 0)
            setupWindow.containerName:setText(entry.name or "")
            setupWindow.itemsList:setItems(entry.items or {})
            list:focusChild(label)
        end
        
        -- Toggle enabled - immediately trigger sorting when activated
        label.enabled.onClick = function()
            entry.enabled = not entry.enabled
            label.enabled:setChecked(entry.enabled)
            saveConfig()  -- Persist to CharacterDB
            -- Trigger immediate processing when rule is enabled
            if entry.enabled and sortingMacro and (config.sortEnabled or config.forceOpen) then
                sortingMacro:setOn()
            end
        end
        
        -- Toggle minimize - apply immediately to open containers
        label.minimize.onClick = function()
            entry.minimize = not entry.minimize
            label.minimize:setColor(entry.minimize and '#00FF00' or '#FF6666')
            label.minimize:setTooltip(entry.minimize and 'Opens Minimized' or 'Opens Normal')
            saveConfig()  -- Persist to CharacterDB
            -- Apply minimize state to currently open containers of this type
            if entry.enabled and entry.itemId then
                for _, container in pairs(g_game.getContainers()) do
                    local containerItem = container:getContainerItem()
                    if containerItem and containerItem:getId() == entry.itemId then
                        local window = getContainerWindow(container:getId())
                        if window then
                            if entry.minimize then
                                if window.minimize then window:minimize()
                                elseif window.setOn then window:setOn(false) end
                            else
                                if window.maximize then window:maximize()
                                elseif window.setOn then window:setOn(true) end
                            end
                        end
                    end
                end
            end
        end
        
        -- Toggle nested - trigger container opening if enabled
        label.nested.onClick = function()
            entry.openNested = not entry.openNested
            label.nested:setColor(entry.openNested and '#00FF00' or '#FF6666')
            label.nested:setTooltip(entry.openNested and 'Opens Nested' or 'No Nested')
            saveConfig()  -- Persist to CharacterDB
            -- Trigger nested container opening if enabled
            if ContainerOpener and ContainerOpener.isProcessing and entry.enabled and entry.openNested and entry.itemId then
                for _, container in pairs(g_game.getContainers()) do
                    local containerItem = container:getContainerItem()
                    if containerItem and containerItem:getId() == entry.itemId then
                        local parentSig = getItemSignature(containerItem)
                        for slot, item in ipairs(container:getItems()) do
                            if item:isContainer() and item:getId() == entry.itemId then
                                if ContainerOpener and ContainerOpener.queueItem then
                                    local resolvedIndex, slotId, absoluteSlotId = getSlotInfo(container, item, slot, nil)
                                    ContainerOpener.queueItem(item, container:getId(), resolvedIndex, slotId, absoluteSlotId, true, parentSig)
                                else
                                    g_game.open(item)
                                end
                                break
                            end
                        end
                    end
                end
                if ContainerOpener and ContainerOpener.isProcessing then
                    schedule(30, ContainerOpener.processNext)
                end
            end
        end
        
        -- Remove entry
        label.remove.onClick = function()
            table.remove(config.containerList, index)
            refreshContainerList()
            selectedContainerIndex = nil
            saveConfig()  -- Persist to CharacterDB
        end
    end
end

-- Initialize setup window
local function initSetupWindow()
    if setupWindow then return end
    
    local rootWidget = g_ui.getRootWidget()
    if not rootWidget then return end
    
    setupWindow = UI.createWindow('ContainerSetupWindow', rootWidget)
    setupWindow:hide()
    setupWindow:setHeight(config.windowHeight or 200)
    
    -- Save window height on resize
    setupWindow.onGeometryChange = function(widget, old, new)
        if old.height > 0 and new.height ~= old.height then
            config.windowHeight = new.height
        end
    end
    
    -- Close button
    setupWindow.closeBtn.onClick = function()
        setupWindow:hide()
    end
    
    -- Checkboxes
    setupWindow.sortEnabled:setChecked(config.sortEnabled)
    setupWindow.sortEnabled.onClick = function(widget)
        config.sortEnabled = not config.sortEnabled
        widget:setChecked(config.sortEnabled)
        saveConfig()  -- Persist to CharacterDB
        -- Trigger immediate sorting when enabled
        if config.sortEnabled and sortingMacro then
            sortingMacro:setOn()
        end
    end
    
    setupWindow.forceOpen:setChecked(config.forceOpen)
    setupWindow.forceOpen.onClick = function(widget)
        config.forceOpen = not config.forceOpen
        widget:setChecked(config.forceOpen)
        saveConfig()  -- Persist to CharacterDB
        -- Trigger immediate check when enabled
        if config.forceOpen and sortingMacro then
            sortingMacro:setOn()
        end
    end
    
    setupWindow.renameEnabled:setChecked(config.renameEnabled)
    setupWindow.renameEnabled.onClick = function(widget)
        config.renameEnabled = not config.renameEnabled
        widget:setChecked(config.renameEnabled)
        saveConfig()  -- Persist to CharacterDB
    end
    
    setupWindow.lootBag:setChecked(config.lootBag)
    setupWindow.lootBag.onClick = function(widget)
        config.lootBag = not config.lootBag
        widget:setChecked(config.lootBag)
        saveConfig()  -- Persist to CharacterDB
    end
    
    -- Add/Update container button
    setupWindow.addContainer.onClick = function()
        local itemId = setupWindow.containerId:getItemId()
        local name = setupWindow.containerName:getText()
        
        if itemId < 100 or name:len() == 0 then
            setupWindow.containerId:setImageColor('#FF6666')
            setupWindow.containerName:setColor('#FF6666')
            schedule(500, function()
                if setupWindow then
                    setupWindow.containerId:setImageColor('#FFFFFF')
                    setupWindow.containerName:setColor('#FFFFFF')
                end
            end)
            return
        end
        
        local existingIndex = findContainerByItemId(config.containerList, itemId)
        local items = setupWindow.itemsList:getItems() or {}
        
        if existingIndex then
            -- Update existing
            config.containerList[existingIndex].name = name
            config.containerList[existingIndex].items = items
        else
            -- Add new
            config.containerList[#config.containerList + 1] = {
                name = name,
                enabled = true,
                itemId = itemId,
                minimize = false,
                openNested = false,
                items = items
            }
        end
        
        -- Clear inputs
        setupWindow.containerId:setItemId(0)
        setupWindow.containerName:setText("")
        setupWindow.itemsList:setItems({})
        selectedContainerIndex = nil
        
        refreshContainerList()
        saveConfig()  -- Persist to CharacterDB
        
        -- Trigger immediate sorting when rule is added/updated
        if config.sortEnabled and sortingMacro then
            sortingMacro:setOn()
        end
    end
    
    -- Items list change handler
    UI.Container(function()
        if selectedContainerIndex and config.containerList[selectedContainerIndex] then
            config.containerList[selectedContainerIndex].items = setupWindow.itemsList:getItems()
            saveConfig()  -- Persist to CharacterDB
            -- Trigger immediate sorting when items list changes
            if config.sortEnabled and sortingMacro then
                sortingMacro:setOn()
            end
        end
    end, true, nil, setupWindow.itemsList)
    
    refreshContainerList()
end

-- Sync setup window checkboxes with current config
local function syncSetupWindowCheckboxes()
    if not setupWindow then return end
    setupWindow.sortEnabled:setChecked(config.sortEnabled == true)
    setupWindow.forceOpen:setChecked(config.forceOpen == true)
    setupWindow.renameEnabled:setChecked(config.renameEnabled == true)
    setupWindow.lootBag:setChecked(config.lootBag == true)
end

--[[
  Container Opening System v5 - Event-Driven with Deep Nesting Support
  
  Key Improvements:
  1. EventBus integration for instant container open detection
  2. Proper depth tracking with level-by-level processing
  3. Exponential backoff on failures
  4. Queue-based processing for reliable ordering
  5. Container ID tracking to prevent duplicate opens
  
  Algorithm:
  1. Open main backpack, wait for container:open event
  2. Scan all open containers for nested containers
  3. Queue nested containers for opening (tracks container item IDs to prevent duplicates)
  4. Process queue one at a time, wait for container:open event
  5. When container opens, re-scan for more nested containers
  6. Repeat until queue is empty and no more nested containers found
]]

-- Helper: Check if container name should be excluded from operations
-- (defined early so ContainerOpener can use it)
local function isExcludedContainer(containerName)
    if not containerName then return false end
    local name = containerName:lower()
    return name:find("depot") or name:find("inbox") or name:find("quiver")
end

-- Helper: Get container window from game_containers module
-- (defined early so ContainerOpener can use it)
local function getContainerWindow(containerId)
    local gameContainers = modules.game_containers
    if gameContainers then
        if gameContainers.getContainerWindow then
            local window = gameContainers.getContainerWindow(containerId)
            if window then return window end
        end
        if gameContainers.containerWindows and gameContainers.containerWindows[containerId] then
            return gameContainers.containerWindows[containerId]
        end
    end
    local rootWidget = g_ui.getRootWidget()
    if rootWidget then
        local patterns = {
            "containerWindow" .. containerId,
            "container" .. containerId,
            "containerMiniWindow" .. containerId
        }
        for _, pattern in ipairs(patterns) do
            local window = rootWidget:recursiveGetChildById(pattern)
            if window then return window end
        end
    end
    return nil
end

-- Helper: Get configured entry for a container by its item ID
-- (defined early so ContainerOpener can use it)
local function getContainerConfig(itemId)
    for _, entry in ipairs(config.containerList) do
        if entry.enabled and entry.itemId == itemId then
            return entry
        end
    end
    return nil
end

-- Helper: Minimize a container window
-- (defined early so ContainerOpener can use it)
local function minimizeContainer(container)
    if not config.autoMinimize then return end
    if not container then return end
    
    local window = getContainerWindow(container:getId())
    if window then
        if window.minimize then
            window:minimize()
        elseif window.setOn then
            window:setOn(false)
        elseif window.minimizeButton then
            window.minimizeButton:onClick()
        end
    end
end

-- Helper: Rename a container window based on config
-- (defined early so ContainerOpener can use it)
local function renameContainer(container)
    if not config.renameEnabled then return end
    if not container then return end
    
    local containerItem = container:getContainerItem()
    if not containerItem then return end
    
    local itemId = containerItem:getId()
    local entry = getContainerConfig(itemId)
    
    if entry and entry.name then
        local window = getContainerWindow(container:getId())
        if window and window.setText then
            window:setText(entry.name)
        end
    end
end

-- Helper: Check if a quiver container is already open
local function isQuiverOpen()
    for _, container in pairs(g_game.getContainers()) do
        local name = container and container:getName() or ""
        if name:lower():find("quiver") then
            return true
        end
    end
    return false
end

-- Helper: Open equipped quiver from right hand/ammo slot (for paladins)
-- (defined early so it can be called from openAllContainers)
local function openQuiver()
    if isQuiverOpen() then return true end

    local rightItem = getRight()
    if rightItem and rightItem:isContainer() then
        g_game.open(rightItem)
        return true
    end

    local ammoItem = getAmmo and getAmmo() or nil
    if ammoItem and ammoItem:isContainer() then
        g_game.open(ammoItem)
        return true
    end

    return false
end

-- Helper: Retry opening quiver a few times (handles delayed equips)
local function openQuiverWithRetry(attempts)
    attempts = attempts or 3
    if openQuiver() then return end
    if attempts <= 1 then return end
    schedule(250, function()
        openQuiverWithRetry(attempts - 1)
    end)
end

-- ============================================================================
-- BFS CONTAINER OPENING STATE (Event-Driven v6 - Complete Rewrite)
-- ============================================================================
--[[
  This rewrite uses the OTCv8 API properly:
  - Container:getItems() returns a deque of ItemPtr
  - Item:isContainer() checks if item is a container
  - Item:getId() returns the item type ID
  - g_game.open(item, previousContainer) opens a container
  - onContainerOpen fires when a container is opened
  
  The algorithm:
  1. When triggered, scan all open containers for nested containers
  2. Queue each nested container by storing a reference to the actual item object
  3. Process queue: open one container, wait for onContainerOpen event
  4. When container opens, scan it for more nested containers, continue
]]

local ContainerOpener = {
  -- State
  isProcessing = false,
  isPaused = false,
  
  -- Queue of container items to open
  -- Each entry: { item = ItemPtr, parentContainerId = number, slot = number }
  queue = {},
  
    -- Tracking which containers we've queued (by "parentId_slot" key -> item signature)
    queuedSlots = {},
  
    -- Dirty container tracking (event-driven scans)
    dirtyContainerIds = {},
  
    -- Tracking opened container items (by item signature -> timestamp)
    openedItemSigs = {},
    openedByContainerId = {},
    containerIdBySig = {},
    inFlightSigs = {},
    inFlightEntries = {},
    openAttempts = {},
  
    -- Graph tracking (for diagnostics / stability)
    graphNodes = {},
    graphEdges = {},
  
  -- Tracking which game container IDs we've already scanned
  scannedContainerIds = {},
  
  -- Timing
  openDelay = 200,       -- Delay between open attempts (ms)
  lastOpenTime = 0,
    lastFullScanTime = 0,
    fullScanInterval = 900, -- Full rescan interval (ms)
    reopenGraceMs = 5000,  -- Prevent rapid reopen/close loops
    inFlightTimeoutMs = 1800,
    inFlightRetryMs = 2200,
    attemptWindowMs = 2500,
    autoOpenActiveUntil = 0,
    settleDelayMs = 12000,
    rescanDelays = { 200, 500, 900, 1400 },
    rescanTimers = {},
    stableEmptyCount = 0,
    stableRequired = 3,
    pageState = {},
  
  -- Retry tracking
  currentAttempt = 0,
    maxAttempts = 5,
  
  -- Depth tracking
  maxDepth = 15,
  
  -- Callbacks
  onComplete = nil,
}

-- Reset all state
function ContainerOpener.reset()
  ContainerOpener.isProcessing = false
  ContainerOpener.isPaused = false
  ContainerOpener.queue = {}
  ContainerOpener.queuedSlots = {}
    ContainerOpener.dirtyContainerIds = {}
    ContainerOpener.openedItemSigs = {}
    ContainerOpener.openedByContainerId = {}
    ContainerOpener.containerIdBySig = {}
    ContainerOpener.inFlightSigs = {}
    ContainerOpener.inFlightEntries = {}
    ContainerOpener.openAttempts = {}
    ContainerOpener.graphNodes = {}
    ContainerOpener.graphEdges = {}
  ContainerOpener.scannedContainerIds = {}
  ContainerOpener.lastOpenTime = 0
    ContainerOpener.lastFullScanTime = 0
    ContainerOpener.autoOpenActiveUntil = 0
    ContainerOpener.rescanTimers = {}
    ContainerOpener.stableEmptyCount = 0
    ContainerOpener.pageState = {}
  ContainerOpener.currentAttempt = 0
  ContainerOpener.onComplete = nil
end

-- Handle paged containers to discover items on other pages
function ContainerOpener.ensurePagedContainers(container)
    if not container or not container.hasPages or not container:hasPages() then return end
    if not container.getSize or not container.getCapacity or not container.getFirstIndex then return end

    local size = container:getSize()
    local capacity = container:getCapacity()
    if capacity <= 0 or size <= capacity then return end

    local containerId = container:getId()
    local firstIndex = container:getFirstIndex()
    local pageIndex = math.floor(firstIndex / capacity)
    local totalPages = math.ceil(size / capacity)

    local state = ContainerOpener.pageState[containerId]
    if not state then
        state = { visited = {}, pending = false }
        ContainerOpener.pageState[containerId] = state
    end

    state.visited[pageIndex] = true

    if state.pending then return end

    -- Find next unvisited page
    local nextPage = nil
    for i = 0, totalPages - 1 do
        if not state.visited[i] then
            nextPage = i
            break
        end
    end

    if nextPage == nil then return end

    state.pending = true
    local nextFirstIndex = nextPage * capacity
    schedule(200, function()
        g_game.seekInContainer(containerId, nextFirstIndex)
        schedule(200, function()
            state.pending = false
            local c = g_game.getContainer(containerId)
            if c then
                ContainerOpener.scanContainer(c)
                ContainerOpener.markDirty(c)
            end
            if ContainerOpener.isProcessing then
                schedule(50, ContainerOpener.processNext)
            end
        end)
    end)
end

-- Schedule delayed rescans for a container to catch late-loaded items
function ContainerOpener.scheduleRescan(containerId)
    if not containerId then return end
    if not ContainerOpener.rescanTimers[containerId] then
        ContainerOpener.rescanTimers[containerId] = true
        for _, delay in ipairs(ContainerOpener.rescanDelays) do
            schedule(delay, function()
                local container = g_game.getContainer(containerId)
                if container then
                    ContainerOpener.scanContainer(container)
                    ContainerOpener.markDirty(container)
                end
            end)
        end
        schedule(ContainerOpener.rescanDelays[#ContainerOpener.rescanDelays] + 50, function()
            ContainerOpener.rescanTimers[containerId] = nil
        end)
    end
end

-- Retry opens that did not result in a container window
function ContainerOpener.scheduleInFlightCheck(itemSig)
    if not itemSig then return end
    schedule(ContainerOpener.inFlightRetryMs, function()
        if not ContainerOpener.inFlightSigs[itemSig] then return end
        local entry = ContainerOpener.inFlightEntries[itemSig]
        if not entry then return end

        local attempts = ContainerOpener.openAttempts[itemSig] or { count = 0, lastAttempt = 0 }
        if attempts.count >= ContainerOpener.maxAttempts then
            ContainerOpener.inFlightSigs[itemSig] = nil
            ContainerOpener.inFlightEntries[itemSig] = nil
            return
        end

        ContainerOpener.inFlightSigs[itemSig] = nil
        ContainerOpener.queueItem(entry.item, entry.parentContainerId, entry.slotIndex, entry.slotId, entry.absoluteSlotId, true, entry.parentSig)
        if not ContainerOpener.isProcessing then
            ContainerOpener.isProcessing = true
        end
        schedule(50, ContainerOpener.processNext)
    end)
end

-- Generate a unique key for a slot
local function makeSlotKey(containerId, slot)
    return tostring(containerId) .. "_" .. tostring(slot)
end

local function getSlotInfo(container, item, slotIndex, slotId)
    local resolvedSlotId = slotId
    if resolvedSlotId == nil then
        resolvedSlotId = item and item.getStackPos and item:getStackPos() or (slotIndex and (slotIndex - 1)) or 0
    end
    local resolvedSlotIndex = slotIndex or (resolvedSlotId + 1)
    local firstIndex = (container and container.getFirstIndex and container:getFirstIndex()) or 0
    local absoluteSlotId = firstIndex + resolvedSlotId
    return resolvedSlotIndex, resolvedSlotId, absoluteSlotId
end

local function getNow()
    return now or (g_clock and g_clock.millis and g_clock.millis()) or (os.time() * 1000)
end

-- Generate a best-effort signature for a container item
local function getItemPathKey(item, depth)
    if not item then return "nil" end
    depth = (depth or 0) + 1
    if depth > 12 then return "depth" end

    local id = item.getId and item:getId() or 0
    local parent = item.getParentContainer and item:getParentContainer() or nil
    local slot = item.getStackPos and item:getStackPos() or -1

    if not parent then
        local pos = item.getPosition and item:getPosition() or nil
        local invSlot = (pos and pos.y) or slot
        return "inv:" .. tostring(invSlot) .. ":" .. tostring(id)
    end

    local parentItem = parent.getContainerItem and parent:getContainerItem() or nil
    local parentKey = getItemPathKey(parentItem, depth)
    return parentKey .. "/" .. tostring(id) .. ":" .. tostring(slot)
end

local function getItemSignature(item)
    if not item then return "nil" end
    return getItemPathKey(item, 0)
end

-- Mark a container as dirty so it will be scanned soon
function ContainerOpener.markDirty(container)
    if not container then return end
    local containerId = container.getId and container:getId() or nil
    if not containerId then return end
    ContainerOpener.dirtyContainerIds[containerId] = true
end

-- Scan only dirty containers for performance
function ContainerOpener.scanDirtyContainers()
    local totalFound = 0
    for containerId, _ in pairs(ContainerOpener.dirtyContainerIds) do
        local container = g_game.getContainer(containerId)
        if container then
            totalFound = totalFound + ContainerOpener.scanContainer(container)
        end
        ContainerOpener.dirtyContainerIds[containerId] = nil
    end
    return totalFound
end

-- Queue a container item safely (front = true inserts at front)
function ContainerOpener.queueItem(item, parentContainerId, slotIndex, slotId, absoluteSlotId, front, parentSig)
    if not item or not item:isContainer() then return false end
    local nowMs = getNow()
    if slotId == nil then
        slotId = item.getStackPos and item:getStackPos() or (slotIndex and (slotIndex - 1)) or 0
    end
    if slotIndex == nil then
        slotIndex = slotId + 1
    end
    if absoluteSlotId == nil then
        absoluteSlotId = slotId
    end
    local parentKey = parentSig or parentContainerId or "unknown"
    local slotKey = makeSlotKey(parentKey, absoluteSlotId)
    local itemSig = getItemSignature(item)
    local lastOpened = ContainerOpener.openedItemSigs[itemSig]
    local inFlight = ContainerOpener.inFlightSigs[itemSig]
    if lastOpened and (nowMs - lastOpened) < ContainerOpener.reopenGraceMs then return false end
    if inFlight and (nowMs - inFlight) < ContainerOpener.inFlightTimeoutMs then return false end
    if ContainerOpener.queuedSlots[slotKey] == itemSig then return false end
    ContainerOpener.queuedSlots[slotKey] = itemSig
    local entry = {
        item = item,
        itemSig = itemSig,
        parentContainerId = parentContainerId,
        parentSig = parentSig,
        slotIndex = slotIndex,
        slotId = slotId,
        absoluteSlotId = absoluteSlotId,
        slotKey = slotKey
    }
    if front then
        table.insert(ContainerOpener.queue, 1, entry)
    else
        table.insert(ContainerOpener.queue, entry)
    end
    return true
end

-- Scan a single container for nested containers and add them to queue
function ContainerOpener.scanContainer(container)
  if not container then return 0 end
  
  local containerId = container:getId()
  local containerName = container:getName() or ""
  
  -- Skip excluded containers
  if isExcludedContainer(containerName) then
    return 0
  end
  
  -- Mark as scanned
  ContainerOpener.scannedContainerIds[containerId] = true
  
  local items = container:getItems()
  local foundCount = 0
    local nowMs = getNow()
    local parentItem = container.getContainerItem and container:getContainerItem() or nil
    local parentSig = parentItem and getItemSignature(parentItem) or nil
  
    for slotIndex, item in ipairs(items) do
    if item and item:isContainer() then
            local resolvedIndex, slotId, absoluteSlotId = getSlotInfo(container, item, slotIndex, nil)
            local slotKey = makeSlotKey(containerId, absoluteSlotId)
            local itemSig = getItemSignature(item)
      
            -- Update graph
            ContainerOpener.graphNodes[itemSig] = {
                itemId = item:getId(),
                parentContainerId = containerId,
                parentSig = parentSig,
                slotIndex = resolvedIndex,
                slotId = slotId,
                absoluteSlotId = absoluteSlotId,
                lastSeen = nowMs
            }
            if parentSig then
                ContainerOpener.graphEdges[parentSig] = ContainerOpener.graphEdges[parentSig] or {}
                ContainerOpener.graphEdges[parentSig][itemSig] = true
            end

            -- Skip if already open/in-flight; only queue if slot is new or item changed
            if ContainerOpener.queueItem(item, containerId, resolvedIndex, slotId, absoluteSlotId, false, parentSig) then
                foundCount = foundCount + 1
            end
    end
  end

    -- If container has pages, ensure all pages are visited to find nested containers
    if ContainerOpener.isProcessing or getNow() < ContainerOpener.autoOpenActiveUntil then
        ContainerOpener.ensurePagedContainers(container)
    end
  
  return foundCount
end

-- Scan all open containers
function ContainerOpener.scanAllContainers()
  local totalFound = 0
  
  for containerId, container in pairs(g_game.getContainers()) do
    -- Scan even if previously scanned (items may have been added)
    totalFound = totalFound + ContainerOpener.scanContainer(container)
  end
  
  return totalFound
end

-- Process the next item in the queue
function ContainerOpener.processNext()
  if not ContainerOpener.isProcessing then return end
  if ContainerOpener.isPaused then return end
  
  -- Respect timing
    local currentTime = getNow()
  local elapsed = currentTime - ContainerOpener.lastOpenTime
  if elapsed < ContainerOpener.openDelay then
    schedule(ContainerOpener.openDelay - elapsed + 20, ContainerOpener.processNext)
    return
  end
  
    -- Event-driven scan of dirty containers for performance
    ContainerOpener.scanDirtyContainers()
  
    -- Periodic full scan for accuracy
    if (currentTime - ContainerOpener.lastFullScanTime) > ContainerOpener.fullScanInterval then
        ContainerOpener.lastFullScanTime = currentTime
        ContainerOpener.scanAllContainers()
    end
  
    -- Check if queue is empty
    if #ContainerOpener.queue == 0 then
        -- Force a full scan to catch late container items
        ContainerOpener.scanAllContainers()
        if #ContainerOpener.queue == 0 then
            ContainerOpener.stableEmptyCount = ContainerOpener.stableEmptyCount + 1
            if getNow() < ContainerOpener.autoOpenActiveUntil or ContainerOpener.stableEmptyCount < ContainerOpener.stableRequired then
                schedule(200, ContainerOpener.processNext)
                return
            end
            -- All done
            ContainerOpener.finish()
            return
        end
        -- New items found after scan; reset stability
        ContainerOpener.stableEmptyCount = 0
    end
  
  -- Get next entry
  local entry = table.remove(ContainerOpener.queue, 1)
  if not entry then
    schedule(50, ContainerOpener.processNext)
    return
  end
  
    -- Skip if already open recently
    if entry.itemSig and ContainerOpener.openedItemSigs[entry.itemSig] and (currentTime - ContainerOpener.openedItemSigs[entry.itemSig]) < ContainerOpener.reopenGraceMs then
        schedule(20, ContainerOpener.processNext)
        return
    end
  
  -- Verify the parent container still exists
    local parentContainerId = entry.parentContainerId
    if entry.parentSig and ContainerOpener.containerIdBySig[entry.parentSig] then
        parentContainerId = ContainerOpener.containerIdBySig[entry.parentSig]
    end
    local parentContainer = parentContainerId and g_game.getContainer(parentContainerId) or nil
  if not parentContainer then
    -- Parent closed, skip this entry
    schedule(50, ContainerOpener.processNext)
    return
  end
  
  -- Get fresh item reference from the slot
  local items = parentContainer:getItems()
  local item = nil
    local entrySig = entry.itemSig
  
    -- First try the original slot index (1-based)
    if entry.slotIndex and items[entry.slotIndex] then
        local candidate = items[entry.slotIndex]
        if candidate and candidate:isContainer() and (not entrySig or getItemSignature(candidate) == entrySig) then
            item = candidate
        end
    end
  
    -- If not found at slot, search for the same item by signature or slotId
  if not item then
    for idx, candidate in ipairs(items) do
      if candidate and candidate:isContainer() then
                local sig = getItemSignature(candidate)
                local resolvedIndex, candidateSlotId, absoluteSlotId = getSlotInfo(parentContainer, candidate, idx, nil)
                if (entrySig and sig == entrySig) or (entry.absoluteSlotId ~= nil and absoluteSlotId == entry.absoluteSlotId) then
                    entry.slotIndex = resolvedIndex
                    entry.slotId = candidateSlotId
                    entry.absoluteSlotId = absoluteSlotId
                    entry.slotKey = makeSlotKey(entry.parentContainerId or entry.parentSig or "unknown", absoluteSlotId)
                    ContainerOpener.queuedSlots[entry.slotKey] = sig
                    item = candidate
                    break
        end
      end
    end
  end

    -- If still not found, fall back to any container not already queued
    if not item then
        for idx, candidate in ipairs(items) do
            if candidate and candidate:isContainer() then
                local resolvedIndex, candidateSlotId, absoluteSlotId = getSlotInfo(parentContainer, candidate, idx, nil)
                local candidateKey = makeSlotKey(entry.parentContainerId or entry.parentSig or "unknown", absoluteSlotId)
                local sig = getItemSignature(candidate)
                if ContainerOpener.queuedSlots[candidateKey] ~= sig then
                    ContainerOpener.queuedSlots[candidateKey] = sig
                    entry.itemSig = sig
                    entry.slotIndex = resolvedIndex
                    entry.slotId = candidateSlotId
                    entry.absoluteSlotId = absoluteSlotId
                    entry.slotKey = candidateKey
                    item = candidate
                    break
                end
            end
        end
    end
  
  if not item then
    -- No valid container found, move on
    schedule(50, ContainerOpener.processNext)
    return
  end
  
    -- Skip if already open (late check)
    local finalSig = getItemSignature(item)
    if ContainerOpener.openedItemSigs[finalSig] and (currentTime - ContainerOpener.openedItemSigs[finalSig]) < ContainerOpener.reopenGraceMs then
        schedule(20, ContainerOpener.processNext)
        return
    end
  
  -- Record timing
  ContainerOpener.lastOpenTime = currentTime
    ContainerOpener.inFlightSigs[finalSig] = currentTime
        ContainerOpener.inFlightEntries[finalSig] = {
                item = item,
                itemSig = finalSig,
                parentContainerId = entry.parentContainerId,
                parentSig = entry.parentSig,
                slotIndex = entry.slotIndex,
                slotId = entry.slotId,
                absoluteSlotId = entry.absoluteSlotId
        }
        ContainerOpener.scheduleInFlightCheck(finalSig)
    local attempt = ContainerOpener.openAttempts[finalSig] or { count = 0, lastAttempt = 0 }
    if (currentTime - attempt.lastAttempt) < ContainerOpener.attemptWindowMs then
        attempt.count = attempt.count + 1
    else
        attempt.count = 1
    end
    attempt.lastAttempt = currentTime
    ContainerOpener.openAttempts[finalSig] = attempt
    if attempt.count >= ContainerOpener.maxAttempts then
        ContainerOpener.openedItemSigs[finalSig] = currentTime
        ContainerOpener.inFlightSigs[finalSig] = nil
                ContainerOpener.inFlightEntries[finalSig] = nil
        schedule(60, ContainerOpener.processNext)
        return
    end
  
  -- Open the container
  -- g_game.open(item, nil) opens in a new window
    g_game.open(item, nil)
  
  -- Schedule next processing after a delay
  -- The onContainerOpen handler will also trigger scan + processNext
  schedule(ContainerOpener.openDelay + 100, ContainerOpener.processNext)
end

-- Finish the opening process
function ContainerOpener.finish()
  ContainerOpener.isProcessing = false
  
  -- Apply final minimize pass
  if config.autoMinimize then
    schedule(100, function()
      for _, container in pairs(g_game.getContainers()) do
        minimizeContainer(container)
      end
    end)
  end
  
  -- Apply renaming
  if config.renameEnabled then
    schedule(150, function()
      for _, container in pairs(g_game.getContainers()) do
        renameContainer(container)
      end
    end)
  end
  
  -- Call completion callback
  if ContainerOpener.onComplete then
    local cb = ContainerOpener.onComplete
    ContainerOpener.onComplete = nil
    schedule(50, cb)
  end
  
  -- Emit event
  if EventBus and EventBus.emit then
    EventBus.emit("containers:open_all_complete")
  end
end

-- Start the container opening process
function ContainerOpener.start(onComplete)
  ContainerOpener.reset()
  ContainerOpener.isProcessing = true
  ContainerOpener.onComplete = onComplete
  ContainerOpener.lastOpenTime = 0
    ContainerOpener.autoOpenActiveUntil = getNow() + ContainerOpener.settleDelayMs
  
  -- Initial scan
  ContainerOpener.scanAllContainers()
  
  -- Start processing
  schedule(50, ContainerOpener.processNext)
end

-- Stop the opening process
function ContainerOpener.stop()
  ContainerOpener.isProcessing = false
  ContainerOpener.isPaused = false
end

-- Called when a container opens (from event handler)
function ContainerOpener.onContainerOpened(container)
  if not ContainerOpener.isProcessing then return end
  if not container then return end
  
    -- Mark as opened to prevent reopen loops
    local containerItem = container.getContainerItem and container:getContainerItem() or nil
    if containerItem then
        local sig = getItemSignature(containerItem)
        ContainerOpener.openedItemSigs[sig] = getNow()
        ContainerOpener.openedByContainerId[container:getId()] = sig
        ContainerOpener.containerIdBySig[sig] = container:getId()
        ContainerOpener.inFlightSigs[sig] = nil
        ContainerOpener.inFlightEntries[sig] = nil
    end
  
  -- Scan the newly opened container for nested containers
  ContainerOpener.scanContainer(container)
    ContainerOpener.markDirty(container)
    ContainerOpener.scheduleRescan(container:getId())
    ContainerOpener.ensurePagedContainers(container)
    ContainerOpener.autoOpenActiveUntil = math.max(ContainerOpener.autoOpenActiveUntil, getNow() + 2000)
    ContainerOpener.stableEmptyCount = 0
  
  -- Trigger processing immediately
  schedule(50, ContainerOpener.processNext)
end

-- ============================================================================
-- CONTAINER EVENTS (NO EVENTBUS)
-- ============================================================================

onContainerOpen(function(container, previousContainer)
    if not container then return end

    -- Trigger the ContainerOpener handler
    if ContainerOpener and ContainerOpener.onContainerOpened then
        ContainerOpener.onContainerOpened(container)
    end

    local containerItem = container:getContainerItem()
    local itemId = containerItem and containerItem:getId() or 0
    local entry = getContainerConfig(itemId)

    -- Apply minimize based on config entry or global auto-minimize during processing
    if entry and entry.minimize then
        schedule(50, function()
            local window = getContainerWindow(container:getId())
            if window then
                if window.minimize then
                    window:minimize()
                elseif window.setOn then
                    window:setOn(false)
                end
            end
        end)
    elseif ContainerOpener.isProcessing and config.autoMinimize then
        schedule(50, function()
            minimizeContainer(container)
        end)
    end

    -- Apply rename if enabled
    if config.renameEnabled then
        schedule(60, function()
            renameContainer(container)
        end)
    end

    -- Trigger sorting macro
    if sortingMacro then
        sortingMacro:setOn()
    end

    -- If configured, prioritize opening nested containers of the same type (only during BFS)
    if ContainerOpener.isProcessing and entry and entry.openNested then
        local parentSig = containerItem and getItemSignature(containerItem) or nil
        for slot, item in ipairs(container:getItems()) do
            if item:isContainer() and item:getId() == itemId then
                if ContainerOpener and ContainerOpener.queueItem then
                    local resolvedIndex, slotId, absoluteSlotId = getSlotInfo(container, item, slot, nil)
                    ContainerOpener.queueItem(item, container:getId(), resolvedIndex, slotId, absoluteSlotId, true, parentSig)
                end
            end
        end
        schedule(20, ContainerOpener.processNext)
    end
end)

-- ============================================================================
-- PUBLIC API (using ContainerOpener)
-- ============================================================================
local function startContainerBFS(onComplete)
    ContainerOpener.start(onComplete)
end

-- Open main backpack first, then start BFS
local function openAllContainers()
    -- Check if main backpack is already open
    local containers = g_game.getContainers()
    local hasMainBP = false
    
    for _, container in pairs(containers) do
        if container then
            hasMainBP = true
            break
        end
    end
    
    if not hasMainBP then
        -- Open main backpack from back slot first
        local bpItem = getBack()
        if bpItem then
            g_game.open(bpItem)
            -- Wait until a container appears (the main backpack) then start BFS and open quiver
            local attempts = 0
            local function waitForMain()
                attempts = attempts + 1
                if #g_game.getContainers() > 0 then
                    startContainerBFS()
                    schedule(200, function() openQuiverWithRetry(3) end)
                elseif attempts < 12 then
                    -- retry a few times (~1.8s total)
                    schedule(150, waitForMain)
                else
                    -- Fallback: start anyway after retries
                    startContainerBFS()
                    schedule(200, function() openQuiverWithRetry(3) end)
                end
            end
            schedule(150, waitForMain)
        else
            warn("[Container Panel] No backpack in back slot!")
        end
    else
        -- Main backpack already open, start BFS directly
        startContainerBFS()
        -- Also try to open quiver
        schedule(200, function() openQuiverWithRetry(3) end)
    end
end

-- Reopen all backpacks from back slot
function reopenBackpacks(onComplete)
    -- Emit event so other modules know we're closing all containers
    if EventBus and EventBus.emit then
        EventBus.emit("containers:close_all")
    end
    
    -- Close all containers first
    for _, container in pairs(g_game.getContainers()) do 
        g_game.close(container) 
    end
    
    -- Wait for containers to close, then open main backpack
    schedule(300, function()
        local bpItem = getBack()
        if bpItem then
            g_game.open(bpItem)
        else
            warn("[Container Panel] No backpack in back slot!")
            if onComplete then onComplete() end
            return
        end
        
        -- Handle purse if enabled
        if config.purse then
            schedule(300, function()
                local purseItem = getPurse()
                if purseItem then
                    use(purseItem)
                end
            end)
        end
        
        -- Always open quiver (default behavior)
        schedule(350, function() openQuiverWithRetry(3) end)
        
        -- Start BFS after main backpack opens; poll until a container appears
        local attempts = 0
        local function waitForMainReopen()
            attempts = attempts + 1
            local containerCount = 0
            for _ in pairs(g_game.getContainers()) do containerCount = containerCount + 1 end
            
            if containerCount > 0 then
                startContainerBFS(onComplete)
            elseif attempts < 12 then
                schedule(150, waitForMainReopen)
            else
                -- Fallback
                startContainerBFS(onComplete)
            end
        end
        schedule(150, waitForMainReopen)
    end)
end

-- Auto Open switch (toggle for auto-open on login)
containerUI.openAll.onClick = function(widget)
    config.autoOpenOnLogin = not config.autoOpenOnLogin
    widget:setOn(config.autoOpenOnLogin)
    saveConfig()  -- Persist to CharacterDB
end

-- Setup button - opens configuration window
containerUI.setupBtn.onClick = function(widget)
    initSetupWindow()
    if setupWindow then
        setupWindow:show()
        setupWindow:raise()
        setupWindow:focus()
        refreshContainerList()
    end
end

containerUI.reopenAll.onClick = function(widget)
    reopenBackpacks()
end

containerUI.closeAll.onClick = function(widget)
    for _, container in pairs(g_game.getContainers()) do
        g_game.close(container)
    end
end

containerUI.minimizeAll.onClick = function(widget)
    local containers = g_game.getContainers()
    for _, container in pairs(containers) do
        local window = getContainerWindow(container:getId())
        if window then
            -- Try minimize method
            if window.minimize then
                window:minimize()
            -- Fallback: try setOn method (some MiniWindows use this)
            elseif window.setOn then
                window:setOn(false)
            -- Fallback: try clicking minimize button if it exists
            elseif window.minimizeButton then
                window.minimizeButton:onClick()
            end
        end
    end
end

containerUI.maximizeAll.onClick = function(widget)
    local containers = g_game.getContainers()
    for _, container in pairs(containers) do
        local window = getContainerWindow(container:getId())
        if window then
            -- Try maximize method
            if window.maximize then
                window:maximize()
            -- Fallback: try setOn method (some MiniWindows use this)
            elseif window.setOn then
                window:setOn(true)
            -- Fallback: try clicking minimize button if it exists (toggle behavior)
            elseif window.minimizeButton then
                window.minimizeButton:onClick()
            end
        end
    end
end

-- Purse switch
containerUI.purseSwitch.onClick = function(widget)
    config.purse = not config.purse
    widget:setOn(config.purse)
    saveConfig()  -- Persist to CharacterDB
end

-- Auto minimize switch
containerUI.autoMinSwitch.onClick = function(widget)
    config.autoMinimize = not config.autoMinimize
    widget:setOn(config.autoMinimize)
    saveConfig()  -- Persist to CharacterDB
end

--[[
  Auto-Open on Re-Login Detection
  
  Uses onPlayerHealthChange to detect when player logs back in.
  When health changes from 0 (or initial state) to a positive value,
  it indicates a new login session.
  
  On relogin, we close all containers first and then reopen from backpack slot
  to ensure a clean state.
]]

local lastKnownHealth = 0
local hasTriggeredThisSession = false
local autoOpenState = {
    inProgress = false,
    lastStart = 0,
    minInterval = 6000
}

local function clearAutoOpenState()
    autoOpenState.inProgress = false
end

local function triggerAutoOpen()
    if not config.autoOpenOnLogin then return end
    if autoOpenState.inProgress then return end
    local nowMs = getNow()
    if (nowMs - autoOpenState.lastStart) < autoOpenState.minInterval then return end
    autoOpenState.inProgress = true
    autoOpenState.lastStart = nowMs
    schedule(1500, function()
        reopenBackpacks(clearAutoOpenState)
    end)
end

-- Detect login by watching for health to appear
onPlayerHealthChange(function(healthPercent)
    -- Only proceed if auto-open is enabled
    if not config.autoOpenOnLogin then return end
    
    -- Detect fresh login: health was 0 (or we just loaded) and now it's positive
    if lastKnownHealth == 0 and healthPercent > 0 and not hasTriggeredThisSession then
        hasTriggeredThisSession = true
        
        triggerAutoOpen()
    end
    
    lastKnownHealth = healthPercent
end)

-- Reset session flag when player health drops to 0 (death or disconnect)
onPlayerHealthChange(function(healthPercent)
    if healthPercent == 0 then
        hasTriggeredThisSession = false
        lastKnownHealth = 0
    end
end)

-- Initial startup check: if player is logged in and auto-open is enabled but no containers are open,
-- this likely indicates a relogin; trigger the auto-open behavior once to restore the user's containers.
schedule(1000, function()
    if not config.autoOpenOnLogin then return end
    if hasTriggeredThisSession then return end
    local p = player and player:getHealthPercent()
    if not p or p == 0 then return end

    -- Only auto-open if no containers are currently open (avoids surprising behavior during normal play)
    if #g_game.getContainers() == 0 then
        hasTriggeredThisSession = true
        triggerAutoOpen()
    end
end)

-- ============================================================================
-- ITEM SORTING SYSTEM
-- ============================================================================

-- Pure function: Move item to destination container
local function moveItemToContainer(item, destContainer)
    if not item or not destContainer then return false end
    if containerIsFull(destContainer) then return false end
    
    local destPos = destContainer:getSlotPosition(destContainer:getItemsCount())
    g_game.move(item, destPos, item:getCount())
    return true
end

-- Pure function: Find destination container for an item
local function findDestinationForItem(itemId)
    for _, entry in ipairs(config.containerList) do
        if entry.enabled and entry.items then
            local items = extractItemIds(entry.items)
            for _, id in ipairs(items) do
                if id == itemId then
                    -- Find open container with this itemId that has space
                    return getContainerByItem and getContainerByItem(entry.itemId, true)
                end
            end
        end
    end
    return nil
end

-- Pure function: Open container from configured list
local function openConfiguredContainer(itemId)
    -- Check equipment slots first
    local slots = {getBack(), getAmmo(), getFinger(), getNeck(), getLeft(), getRight()}
    for _, slotItem in ipairs(slots) do
        if slotItem and slotItem:getId() == itemId then
            g_game.open(slotItem)
            return true
        end
    end
    
    -- Check in open containers
    for _, container in pairs(g_game.getContainers()) do
        for _, item in ipairs(container:getItems()) do
            if item:isContainer() and item:getId() == itemId then
                g_game.open(item)
                return true
            end
        end
    end
    
    -- Try to find anywhere
    local item = findItem(itemId)
    if item then
        g_game.open(item)
        return true
    end
    
    return false
end

-- Sorting macro - runs periodically to organize items
sortingMacro = macro(150, function(m)
    -- Early exit if no features enabled
    if not config.sortEnabled and not config.forceOpen then
        m:setOff()
        return
    end
    
    -- Item sorting logic
    if config.sortEnabled then
        for _, container in pairs(getContainers()) do
            local containerName = container:getName()
            
            -- Skip excluded containers
            if not isExcludedContainer(containerName) then
                local containerItemId = container:getContainerItem():getId()
                
                for _, item in ipairs(container:getItems()) do
                    local itemId = item:getId()
                    local destination = findDestinationForItem(itemId)
                    
                    -- Only move if destination exists and is different from current container
                    if destination then
                        local destItemId = destination:getContainerItem():getId()
                        if destItemId ~= containerItemId then
                            if moveItemToContainer(item, destination) then
                                return  -- One move per tick
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Force open containers logic
    if config.forceOpen then
        for _, entry in ipairs(config.containerList) do
            if entry.enabled then
                local container = getContainerByItem(entry.itemId)
                if not container then
                    if openConfiguredContainer(entry.itemId) then
                        return  -- One open per tick
                    end
                end
            end
        end
        
        -- Force open purse
        if config.purse then
            local purseContainer = getContainerByItem(PURSE_ITEM_ID)
            if not purseContainer then
                local purseItem = getPurse()
                if purseItem then
                    use(purseItem)
                    return
                end
            end
        end
        
        -- Force open loot bag
        if config.lootBag then
            local lootBagContainer = getContainerByItem(LOOT_BAG_ITEM_ID)
            if not lootBagContainer then
                local lootBag = findItem(LOOT_BAG_ITEM_ID)
                if lootBag then
                    local purseContainer = getContainerByItem(PURSE_ITEM_ID)
                    if purseContainer then
                        g_game.open(lootBag, purseContainer)
                    else
                        use(getPurse())
                    end
                    return
                end
            end
        end
    end
    
    -- Turn off if nothing to do
    m:setOff()
end)

-- Event handlers to trigger sorting
onAddItem(function(container, slot, item, oldItem)
    -- If a container item is added into an open container, queue it for opening
    if item and item:isContainer() and ContainerOpener and (ContainerOpener.isProcessing or getNow() < ContainerOpener.autoOpenActiveUntil) then
        local parentId = container and container.getId and container:getId() or 0
        local containerName = container and container.getName and container:getName() or ""
        if not isExcludedContainer(containerName) then
            if ContainerOpener and ContainerOpener.queueItem then
                local parentItem = container and container.getContainerItem and container:getContainerItem() or nil
                local parentSig = parentItem and getItemSignature(parentItem) or nil
                local slotIndex = (slot or 0) + 1
                local slotId = slot
                local resolvedIndex, resolvedSlotId, absoluteSlotId = getSlotInfo(container, item, slotIndex, slotId)
                if ContainerOpener.queueItem(item, parentId, resolvedIndex, resolvedSlotId, absoluteSlotId, true, parentSig) then
                    -- If opener is active, process immediately for realtime behavior
                    if not ContainerOpener.isProcessing then
                        ContainerOpener.isProcessing = true
                    end
                    schedule(10, ContainerOpener.processNext)
                end
            end
        end
    end

    -- Mark container dirty for rescan (items may have changed)
    if container and ContainerOpener and ContainerOpener.markDirty then
        ContainerOpener.markDirty(container)
    end

    if sortingMacro and (config.sortEnabled or config.forceOpen) then
        sortingMacro:setOn()
    end
end)

onRemoveItem(function(container, slot, item)
    if container and ContainerOpener and ContainerOpener.markDirty then
        ContainerOpener.markDirty(container)
    end
    if sortingMacro and (config.sortEnabled or config.forceOpen) then
        sortingMacro:setOn()
    end
end)

onPlayerInventoryChange(function(slot, item, oldItem)
    if sortingMacro and (config.sortEnabled or config.forceOpen) then
        sortingMacro:setOn()
    end
end)

onContainerClose(function(container)
    if container and ContainerOpener and ContainerOpener.openedItemSigs then
        local containerItem = container.getContainerItem and container:getContainerItem() or nil
        if containerItem then
            local sig = getItemSignature(containerItem)
            ContainerOpener.openedItemSigs[sig] = getNow()
            if ContainerOpener.openedByContainerId then
                ContainerOpener.openedByContainerId[container:getId()] = nil
            end
            if ContainerOpener.containerIdBySig and ContainerOpener.containerIdBySig[sig] == container:getId() then
                ContainerOpener.containerIdBySig[sig] = nil
            end
            if ContainerOpener.pageState then
                ContainerOpener.pageState[container:getId()] = nil
            end
        end
    end
    if container and not container.lootContainer then
        if sortingMacro and (config.sortEnabled or config.forceOpen) then
            sortingMacro:setOn()
        end
    end
end)
