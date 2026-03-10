--[[
  Container Panel - Advanced Container Management System v12.3
  
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
  
  v12.3 Changes:
  - FIXED: Main backpack not minimizing when auto-minimize enabled
  - FIXED: Quiver not opening - now uses OTClient slot constants
  - FIXED: Container count check using pairs() instead of # operator
  - IMPROVED: Always minimize when auto-minimize is enabled (not just during processing)
  
  v12.2 Changes:
  - FIXED: Infinite loop when opening/closing containers recursively
  - FIXED: Quiver not opening on right hand slot for OpenTibiaBR
  - IMPROVED: Container tracking now uses itemId to prevent re-opens
  - IMPROVED: Scanner cooldowns prevent over-scanning same container
  - IMPROVED: Grace periods increased for better stability
  - IMPROVED: Max opens per item type to prevent infinite loops
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

-- Alias shared deepClone (DRY)
local deepClone = nExBot.Shared.deepClone

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
NxBotSection
  height: 128

  Label
    text-align: center
    text: Container Panel
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    font: verdana-11px-rounded

  NxSwitch
    id: openAll
    !text: tr('Auto Open')
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.horizontalCenter
    margin-right: 2
    margin-top: 4
    text-align: center
    font: verdana-11px-rounded

  NxButton
    id: setupBtn
    !text: tr('Setup')
    anchors.top: prev.top
    anchors.left: parent.horizontalCenter
    anchors.right: parent.right
    margin-left: 2
    height: 20
    font: verdana-11px-rounded

  NxButton
    id: reopenAll
    !text: tr('Reopen All')
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 2
    height: 20
    font: verdana-11px-rounded

  NxButton
    id: closeAll
    !text: tr('Close All')
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 2
    height: 20
    font: verdana-11px-rounded

  NxButton
    id: minimizeAll
    !text: tr('Minimize All')
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.horizontalCenter
    margin-right: 2
    margin-top: 2
    height: 20
    font: verdana-11px-rounded

  NxButton
    id: maximizeAll
    !text: tr('Maximize All')
    anchors.top: prev.top
    anchors.left: parent.horizontalCenter
    anchors.right: parent.right
    margin-left: 2
    height: 20
    font: verdana-11px-rounded

  NxSwitch
    id: purseSwitch
    anchors.top: minimizeAll.bottom
    anchors.left: parent.left
    anchors.right: parent.horizontalCenter
    margin-right: 2
    margin-top: 4
    text-align: center
    !text: tr('Open Purse')
    font: verdana-11px-rounded

  NxSwitch
    id: autoMinSwitch
    anchors.top: minimizeAll.bottom
    anchors.left: prev.right
    anchors.right: parent.right
    margin-top: 4
    margin-left: 4
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
    background-color: #3be4d033

  Button
    id: minimize
    !text: tr('M')
    anchors.right: nested.left
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 2
    width: 16
    height: 16
    font: cipsoftFont
    color: #f5f7ff

  Button
    id: nested
    !text: tr('N')
    anchors.right: remove.left
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 2
    width: 16
    height: 16
    font: cipsoftFont
    color: #f5f7ff

  Button
    id: remove
    !text: tr('X')
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    margin-right: 20
    width: 16
    height: 16
    font: cipsoftFont
    color: #f5f7ff

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

  NxButton
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

  NxButtonSm
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
refreshContainerList = function()
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
                        if entry.minimize then
                            minimizeWindow(window)
                        else
                            maximizeWindow(window)
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
            if ContainerBFS and ContainerBFS.isActive() and entry.enabled and entry.openNested and entry.itemId then
                for _, container in pairs(g_game.getContainers()) do
                    local containerItem = container:getContainerItem()
                    if containerItem and containerItem:getId() == entry.itemId then
                        for slot, item in ipairs(container:getItems()) do
                            if item:isContainer() and item:getId() == entry.itemId then
                                if ContainerBFS.queueItem then
                                    ContainerBFS.queueItem(item, container:getId(), slot, true)
                                else
                                    g_game.open(item)
                                end
                                break
                            end
                        end
                    end
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
    if not rootWidget then
        warn("[Container Panel] rootWidget not available")
        return
    end
    
    local ok, win = pcall(function() return UI.createWindow('ContainerSetupWindow', rootWidget) end)
    if not ok or not win then
        warn("[Container Panel] Failed to create setup window: " .. tostring(win))
        return
    end
    
    setupWindow = win
    
    -- Set height BEFORE hide to avoid geometry callback saving 0
    local h = tonumber(config.windowHeight)
    if not h or h < 150 then h = 220 end
    setupWindow:setHeight(h)
    
    -- Save window height on resize
    setupWindow.onGeometryChange = function(widget, old, new)
        if new.height >= 150 and old.height > 0 and new.height ~= old.height then
            config.windowHeight = new.height
        end
    end
    
    setupWindow:hide()
    
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

-- ============================================================================
-- SHARED UI HELPERS (DRY — single definition for minimize/maximize)
-- ============================================================================

local function minimizeWindow(window)
    if not window then return end
    if window.minimize then window:minimize()
    elseif window.setOn then window:setOn(false)
    elseif window.minimizeButton then window.minimizeButton:onClick() end
end

local function maximizeWindow(window)
    if not window then return end
    if window.maximize then window:maximize()
    elseif window.setOn then window:setOn(true)
    elseif window.minimizeButton then window.minimizeButton:onClick() end
end

local function applyMinimize(container)
    if not container then return end
    local containerItem = container:getContainerItem()
    local itemId = containerItem and containerItem:getId() or 0
    local entry = getContainerConfig(itemId)
    local shouldMinimize = (entry and entry.minimize) or config.autoMinimize
    if shouldMinimize then
        schedule(50, function()
            minimizeWindow(getContainerWindow(container:getId()))
        end)
    end
end

local function applyRename(container)
    if not config.renameEnabled or not container then return end
    local containerItem = container:getContainerItem()
    if not containerItem then return end
    local itemId = containerItem:getId()
    local entry = getContainerConfig(itemId)
    if entry and entry.name then
        schedule(60, function()
            local window = getContainerWindow(container:getId())
            if window and window.setText then window:setText(entry.name) end
        end)
    end
end

-- ============================================================================
-- QUIVER HELPERS
-- ============================================================================

local function isQuiverOpen()
    for _, container in pairs(g_game.getContainers()) do
        local name = container and container:getName() or ""
        if name:lower():find("quiver") then return true end
        local containerItem = container:getContainerItem()
        if containerItem and containerItem:isContainer() then
            local itemId = containerItem:getId()
            if itemId >= 35847 and itemId <= 35860 then return true end
        end
    end
    return false
end

local function getInventoryItemSafe(slotId)
    local player = g_game.getLocalPlayer()
    if not player then return nil end
    if player.getInventoryItem then
        local ok, item = pcall(function() return player:getInventoryItem(slotId) end)
        if ok and item then return item end
    end
    return nil
end

local function getQuiverItem()
    local player = g_game.getLocalPlayer()
    if not player then return nil, nil end

    local rightSlot = InventorySlotRight or 6
    if player.getInventoryItem then
        local ok, item = pcall(function() return player:getInventoryItem(rightSlot) end)
        if ok and item then
            local okC, isC = pcall(function() return item:isContainer() end)
            if okC and isC then return item, "right" end
        end
    end
    if getRight then
        local ok, item = pcall(getRight)
        if ok and item then
            local okC, isC = pcall(function() return item:isContainer() end)
            if okC and isC then return item, "right_global" end
        end
    end

    local ammoSlot = InventorySlotAmmo or 10
    if player.getInventoryItem then
        local ok, item = pcall(function() return player:getInventoryItem(ammoSlot) end)
        if ok and item then
            local okC, isC = pcall(function() return item:isContainer() end)
            if okC and isC then return item, "ammo" end
        end
    end
    if getAmmo then
        local ok, item = pcall(getAmmo)
        if ok and item then
            local okC, isC = pcall(function() return item:isContainer() end)
            if okC and isC then return item, "ammo_global" end
        end
    end
    return nil, nil
end

local function openQuiver()
    if isQuiverOpen() then return true end
    local quiverItem = getQuiverItem()
    if quiverItem then
        local Client = nExBot.Shared.getClient()
        if Client and Client.open then Client.open(quiverItem)
        else g_game.open(quiverItem) end
        return true
    end
    return false
end

local function openQuiverWithRetry(attempts)
    attempts = attempts or 3
    if openQuiver() then return end
    if attempts <= 1 then return end
    schedule(300, function() openQuiverWithRetry(attempts - 1) end)
end

-- ============================================================================
-- CLIENT SERVICE HELPERS
-- ============================================================================

local getClient = nExBot.Shared.getClient

local function getNow()
    if now then return now end
    if g_clock and g_clock.millis then return g_clock.millis() end
    return os.time() * 1000
end

local _lastSyncRequest = 0
local function requestContainerSync()
    local t = getNow()
    if (t - _lastSyncRequest) < 500 then return end
    _lastSyncRequest = t
    local Client = getClient()
    if Client and Client.requestContainerQueue then
        pcall(function() Client.requestContainerQueue() end)
    end
end

local _lastRefresh = {}
local function refreshContainer(container)
    local Client = getClient()
    if not (Client and Client.refreshContainer) then return false end
    local cid = container:getId()
    local t = getNow()
    if _lastRefresh[cid] and (t - _lastRefresh[cid]) < 300 then return false end
    _lastRefresh[cid] = t
    return pcall(function() Client.refreshContainer(container) end)
end

local function hasEnhancedAPIs()
    local Client = getClient()
    return Client and Client.isOpenTibiaBR and Client.isOpenTibiaBR()
end

-- ============================================================================
-- CONTAINER BFS — Event-Driven State Machine
-- Replaces ContainerTracker + ContainerQueue + ContainerScanner + ContainerOpener
-- States: IDLE → OPENING_MAIN → RUNNING → (finish) → IDLE
-- ============================================================================

local ContainerBFS = {
    state = "IDLE",
    queue = {},             -- array of {parentId, slot, itemId}
    opened = {},            -- set: "parentId:slot" -> true
    openedTypes = {},       -- itemId -> count (prevents infinite loops)
    pendingOpen = nil,      -- {entry, ts} or nil
    lastOpenTime = 0,
    onCompleteCallback = nil,

    OPEN_DELAY = 200,       -- ms between opens
    SAFETY_TIMEOUT = 3000,  -- ms before giving up on a pending open
    MAX_PER_TYPE = 50,      -- max opens per container type
}

function ContainerBFS.reset()
    ContainerBFS.state = "IDLE"
    ContainerBFS.queue = {}
    ContainerBFS.opened = {}
    ContainerBFS.openedTypes = {}
    ContainerBFS.pendingOpen = nil
    ContainerBFS.lastOpenTime = 0
    ContainerBFS.onCompleteCallback = nil
end

function ContainerBFS.isActive()
    return ContainerBFS.state ~= "IDLE"
end

-- Scan a container's items and enqueue nested containers for opening
function ContainerBFS.scanContainer(container)
    if not container then return end
    local name = container:getName() or ""
    if isExcludedContainer(name) then return end

    local containerId = container:getId()
    local items = container:getItems()

    for slot, item in ipairs(items) do
        if item and item:isContainer() then
            local key = containerId .. ":" .. slot
            if not ContainerBFS.opened[key] then
                ContainerBFS.opened[key] = true
                local itemId = item:getId()
                local typeCount = ContainerBFS.openedTypes[itemId] or 0
                if typeCount < ContainerBFS.MAX_PER_TYPE then
                    ContainerBFS.openedTypes[itemId] = typeCount + 1
                    ContainerBFS.queue[#ContainerBFS.queue + 1] = {
                        parentId = containerId,
                        slot = slot,
                        itemId = itemId,
                    }
                end
            end
        end
    end
end

-- Handle paged containers — seek to unvisited pages and scan them
function ContainerBFS.handlePages(container)
    if not container or not container.hasPages or not container:hasPages() then return end

    local containerId = container:getId()
    local capacity = container:getCapacity()
    local totalSize = container:getSize()
    if capacity <= 0 or totalSize <= capacity then return end

    local totalPages = math.ceil(totalSize / capacity)
    local firstIndex = container:getFirstIndex()
    local currentPage = math.floor(firstIndex / capacity)

    for pageIdx = 0, totalPages - 1 do
        if pageIdx ~= currentPage then
            local targetIndex = pageIdx * capacity
            schedule(150 * (pageIdx + 1), function()
                if not ContainerBFS.isActive() then return end
                g_game.seekInContainer(containerId, targetIndex)
                schedule(200, function()
                    local c = g_game.getContainer(containerId)
                    if c and ContainerBFS.isActive() then
                        ContainerBFS.scanContainer(c)
                    end
                end)
            end)
        end
    end
end

-- Queue an item for opening (used by forward refs and onAddItem)
function ContainerBFS.queueItem(item, containerId, slotIndex, prioritize)
    if not item then return false end
    local ok, isC = pcall(function() return item:isContainer() end)
    if not ok or not isC then return false end
    local key = containerId .. ":" .. slotIndex
    if ContainerBFS.opened[key] then return false end
    ContainerBFS.opened[key] = true

    local itemId = nil
    pcall(function() itemId = item:getId() end)
    local typeCount = ContainerBFS.openedTypes[itemId] or 0
    if itemId and typeCount >= ContainerBFS.MAX_PER_TYPE then return false end
    if itemId then ContainerBFS.openedTypes[itemId] = typeCount + 1 end

    local entry = { parentId = containerId, slot = slotIndex, itemId = itemId }
    if prioritize then
        table.insert(ContainerBFS.queue, 1, entry)
    else
        ContainerBFS.queue[#ContainerBFS.queue + 1] = entry
    end
    return true
end

-- Open the next container in the queue (called from event handler, not timer chain)
function ContainerBFS.openNext()
    if ContainerBFS.state ~= "RUNNING" then return end

    -- Respect timing between opens
    local t = getNow()
    local elapsed = t - ContainerBFS.lastOpenTime
    if elapsed < ContainerBFS.OPEN_DELAY then
        schedule(ContainerBFS.OPEN_DELAY - elapsed + 20, ContainerBFS.openNext)
        return
    end

    -- Pop entries until we find a valid one
    while #ContainerBFS.queue > 0 do
        local entry = table.remove(ContainerBFS.queue, 1)
        local parent = g_game.getContainer(entry.parentId)
        if parent then
            local items = parent:getItems()
            local item = items[entry.slot]

            -- Verify item is still a container at that slot
            if not item or not item:isContainer() then
                item = nil
                for idx, candidate in ipairs(items) do
                    if candidate and candidate:isContainer() then
                        local cId = candidate:getId()
                        if cId == entry.itemId then
                            local key = entry.parentId .. ":" .. idx
                            if not ContainerBFS.opened[key] then
                                ContainerBFS.opened[key] = true
                                entry.slot = idx
                                item = candidate
                                break
                            end
                        end
                    end
                end
            end

            if item then
                -- Set pending and open
                local pending = { entry = entry, ts = getNow() }
                ContainerBFS.pendingOpen = pending
                ContainerBFS.lastOpenTime = getNow()

                local Client = getClient()
                if Client and Client.open then
                    Client.open(item, nil)
                else
                    g_game.open(item, nil)
                end

                -- Refresh parent for OpenTibiaBR
                if hasEnhancedAPIs() then
                    schedule(100, function() refreshContainer(parent) end)
                end

                -- Safety timeout: if container doesn't open in time, skip and move on
                schedule(ContainerBFS.SAFETY_TIMEOUT, function()
                    if ContainerBFS.pendingOpen == pending then
                        ContainerBFS.pendingOpen = nil
                        ContainerBFS.openNext()
                    end
                end)
                return  -- Wait for onContainerOpen or safety timeout
            end
        end
        -- Parent gone or item invalid — skip, loop continues
    end

    -- Queue is empty → finish
    ContainerBFS.finish()
end

-- Called from onContainerOpen when a new container window opens
function ContainerBFS.onContainerOpened(container)
    if not container then return end

    if ContainerBFS.state == "OPENING_MAIN" then
        ContainerBFS.pendingOpen = nil
        if hasEnhancedAPIs() then refreshContainer(container) end
        ContainerBFS.scanContainer(container)
        ContainerBFS.handlePages(container)
        ContainerBFS.state = "RUNNING"
        ContainerBFS.openNext()

    elseif ContainerBFS.state == "RUNNING" and ContainerBFS.pendingOpen then
        local openedItemId = nil
        local containerItem = container:getContainerItem()
        if containerItem then
            pcall(function() openedItemId = containerItem:getId() end)
        end

        local pending = ContainerBFS.pendingOpen
        if openedItemId and pending.entry.itemId == openedItemId then
            ContainerBFS.pendingOpen = nil
            if hasEnhancedAPIs() then refreshContainer(container) end
            ContainerBFS.scanContainer(container)
            ContainerBFS.handlePages(container)
            ContainerBFS.openNext()
        end
    end
end

-- Finish the BFS process
function ContainerBFS.finish()
    local prevState = ContainerBFS.state
    ContainerBFS.state = "IDLE"
    ContainerBFS.pendingOpen = nil

    -- Don't apply finalization if we never actually ran
    if prevState == "IDLE" then return end

    -- Apply minimize to all open containers
    if config.autoMinimize then
        schedule(100, function()
            for _, c in pairs(g_game.getContainers()) do
                applyMinimize(c)
            end
        end)
    end

    -- Apply renaming
    if config.renameEnabled then
        schedule(150, function()
            for _, c in pairs(g_game.getContainers()) do
                applyRename(c)
            end
        end)
    end

    -- Callback
    local cb = ContainerBFS.onCompleteCallback
    ContainerBFS.onCompleteCallback = nil
    if cb then schedule(50, cb) end

    -- Emit event
    if EventBus and EventBus.emit then
        EventBus.emit("containers:open_all_complete")
    end
end

-- Start BFS: scan all open containers, then begin opening queued entries
function ContainerBFS.start(onComplete)
    ContainerBFS.reset()
    ContainerBFS.onCompleteCallback = onComplete
    requestContainerSync()

    -- Scan all currently open containers for nested items
    for _, c in pairs(g_game.getContainers()) do
        if hasEnhancedAPIs() then refreshContainer(c) end
        ContainerBFS.scanContainer(c)
    end

    -- If we already found items to open, go straight to RUNNING
    if #ContainerBFS.queue > 0 then
        ContainerBFS.state = "RUNNING"
        ContainerBFS.openNext()
    else
        -- Nothing queued — containers may be empty or all already open
        ContainerBFS.state = "IDLE"
        if onComplete then schedule(50, onComplete) end
        if EventBus and EventBus.emit then
            EventBus.emit("containers:open_all_complete")
        end
    end
end

-- Stop BFS
function ContainerBFS.stop()
    ContainerBFS.state = "IDLE"
    ContainerBFS.pendingOpen = nil
end

-- ============================================================================
-- FORCE OPEN COOLDOWN (Simple cooldown for sorting macro's force-open)
-- ============================================================================

local _forceOpenCooldown = {}  -- itemId -> timestamp
local FORCE_OPEN_COOLDOWN_MS = 2000

local function canForceOpen(itemId)
    local t = _forceOpenCooldown[itemId]
    if t and (getNow() - t) < FORCE_OPEN_COOLDOWN_MS then return false end
    return true
end

local function markForceOpen(itemId)
    _forceOpenCooldown[itemId] = getNow()
end

-- ============================================================================
-- CONTAINER EVENT HANDLERS
-- ============================================================================

-- Helper: check if TargetBot looting is actively using container windows.
-- Uses isActive() (not isLocked()) so forceOpen stays suppressed while
-- corpses remain in the loot queue, preventing the open/close loop.
local function isLootLocked()
    return TargetBot and TargetBot.Looting and TargetBot.Looting.isActive and TargetBot.Looting.isActive()
end

onContainerOpen(function(container, previousContainer)
    if not container then return end

    -- Drive the BFS state machine
    ContainerBFS.onContainerOpened(container)

    -- Apply minimize and rename
    applyMinimize(container)
    applyRename(container)

    -- Trigger sorting macro (suppress during active looting to prevent container fights)
    if sortingMacro and not isLootLocked() then sortingMacro:setOn() end

    -- If BFS active and config says open nested: prioritize same-type children
    if ContainerBFS.isActive() then
        local containerItem = container:getContainerItem()
        local itemId = containerItem and containerItem:getId() or 0
        local entry = getContainerConfig(itemId)
        if entry and entry.openNested then
            local containerId = container:getId()
            for slotIndex, item in ipairs(container:getItems()) do
                if item:isContainer() and item:getId() == itemId then
                    ContainerBFS.queueItem(item, containerId, slotIndex, true)
                end
            end
        end
    end
end)

onContainerClose(function(container)
    if container and not container.lootContainer and not isLootLocked() then
        if sortingMacro and (config.sortEnabled or config.forceOpen) then
            sortingMacro:setOn()
        end
    end
end)

onAddItem(function(container, slot, item, oldItem)
    -- If BFS active and a new container item appears, queue it
    if item and ContainerBFS.isActive() and container then
        local ok, isC = pcall(function() return item:isContainer() end)
        if ok and isC then
            local containerName = container:getName() or ""
            if not isExcludedContainer(containerName) then
                local slotIndex = (slot or 0) + 1
                ContainerBFS.queueItem(item, container:getId(), slotIndex, true)
            end
        end
    end

    if sortingMacro and (config.sortEnabled or config.forceOpen) and not isLootLocked() then
        sortingMacro:setOn()
    end
end)

onRemoveItem(function(container, slot, item)
    if sortingMacro and (config.sortEnabled or config.forceOpen) and not isLootLocked() then
        sortingMacro:setOn()
    end
end)

onPlayerInventoryChange(function(slot, item, oldItem)
    if sortingMacro and (config.sortEnabled or config.forceOpen) and not isLootLocked() then
        sortingMacro:setOn()
    end
end)

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Open all containers: open main BP if needed, then BFS
local function openAllContainers()
    local hasMainBP = false
    for _ in pairs(g_game.getContainers()) do hasMainBP = true; break end

    if hasMainBP then
        -- Main BP already open, start BFS directly
        ContainerBFS.start()
        schedule(200, function() openQuiverWithRetry(3) end)
    else
        -- Open main backpack from back slot
        local bpItem = getBack()
        if not bpItem then
            warn("[Container Panel] No backpack in back slot!")
            return
        end
        g_game.open(bpItem)
        -- Use OPENING_MAIN state: BFS waits for first container:open event
        ContainerBFS.reset()
        ContainerBFS.state = "OPENING_MAIN"
        -- Safety: if main BP doesn't open in 3s, abort
        local pending = {}
        ContainerBFS.pendingOpen = pending
        schedule(3000, function()
            if ContainerBFS.pendingOpen == pending and ContainerBFS.state == "OPENING_MAIN" then
                ContainerBFS.state = "IDLE"
                ContainerBFS.pendingOpen = nil
            end
        end)
        schedule(400, function() openQuiverWithRetry(5) end)
    end
end

-- Reopen all backpacks: close all → open from back slot → BFS
function reopenBackpacks(onComplete)
    if EventBus and EventBus.emit then
        EventBus.emit("containers:close_all")
    end

    -- Close all containers
    for _, container in pairs(g_game.getContainers()) do
        g_game.close(container)
    end

    -- After close, open main BP and start BFS
    schedule(300, function()
        local bpItem = getBack()
        if not bpItem then
            warn("[Container Panel] No backpack in back slot!")
            if onComplete then onComplete() end
            return
        end
        g_game.open(bpItem)

        -- Handle purse
        if config.purse then
            schedule(300, function()
                local purseItem = getPurse()
                if purseItem then use(purseItem) end
            end)
        end

        -- Open quiver
        schedule(400, function() openQuiverWithRetry(5) end)

        -- Use OPENING_MAIN state: BFS waits for first container:open event
        ContainerBFS.reset()
        ContainerBFS.state = "OPENING_MAIN"
        ContainerBFS.onCompleteCallback = onComplete
        -- Safety timeout
        local pending = {}
        ContainerBFS.pendingOpen = pending
        schedule(3000, function()
            if ContainerBFS.pendingOpen == pending and ContainerBFS.state == "OPENING_MAIN" then
                ContainerBFS.finish()
            end
        end)
    end)
end

-- ============================================================================
-- BUTTON HANDLERS
-- ============================================================================

containerUI.openAll.onClick = function(widget)
    config.autoOpenOnLogin = not config.autoOpenOnLogin
    widget:setOn(config.autoOpenOnLogin)
    saveConfig()
end

containerUI.setupBtn.onClick = function(widget)
    if not setupWindow then initSetupWindow() end
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
    for _, container in pairs(g_game.getContainers()) do
        minimizeWindow(getContainerWindow(container:getId()))
    end
end

containerUI.maximizeAll.onClick = function(widget)
    for _, container in pairs(g_game.getContainers()) do
        maximizeWindow(getContainerWindow(container:getId()))
    end
end

containerUI.purseSwitch.onClick = function(widget)
    config.purse = not config.purse
    widget:setOn(config.purse)
    saveConfig()
end

containerUI.autoMinSwitch.onClick = function(widget)
    config.autoMinimize = not config.autoMinimize
    widget:setOn(config.autoMinimize)
    saveConfig()
end

-- ============================================================================
-- AUTO-OPEN ON RE-LOGIN
-- ============================================================================

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
    local t = getNow()
    if (t - autoOpenState.lastStart) < autoOpenState.minInterval then return end
    autoOpenState.inProgress = true
    autoOpenState.lastStart = t
    schedule(1500, function()
        reopenBackpacks(clearAutoOpenState)
    end)
end

onPlayerHealthChange(function(healthPercent)
    if not config.autoOpenOnLogin then return end
    if lastKnownHealth == 0 and healthPercent > 0 and not hasTriggeredThisSession then
        hasTriggeredThisSession = true
        triggerAutoOpen()
    end
    lastKnownHealth = healthPercent
end)

onPlayerHealthChange(function(healthPercent)
    if healthPercent == 0 then
        hasTriggeredThisSession = false
        lastKnownHealth = 0
    end
end)

-- Initial startup check
schedule(1000, function()
    if not config.autoOpenOnLogin then return end
    if hasTriggeredThisSession then return end
    local p = player and player:getHealthPercent()
    if not p or p == 0 then return end

    local containerCount = 0
    for _ in pairs(g_game.getContainers()) do containerCount = containerCount + 1 end
    if containerCount == 0 then
        hasTriggeredThisSession = true
        triggerAutoOpen()
    end
end)

-- ============================================================================
-- ITEM SORTING SYSTEM
-- ============================================================================

local function moveItemToContainer(item, destContainer)
    if not item or not destContainer then return false end
    if containerIsFull(destContainer) then return false end
    local destPos = destContainer:getSlotPosition(destContainer:getItemsCount())
    g_game.move(item, destPos, item:getCount())
    return true
end

local function findDestinationForItem(itemId)
    for _, entry in ipairs(config.containerList) do
        if entry.enabled and entry.items then
            local items = extractItemIds(entry.items)
            for _, id in ipairs(items) do
                if id == itemId then
                    return getContainerByItem and getContainerByItem(entry.itemId, true)
                end
            end
        end
    end
    return nil
end

local function isContainerOpen(itemId)
    if not itemId then return false end
    for _, container in pairs(g_game.getContainers()) do
        local containerItem = container:getContainerItem()
        if containerItem and containerItem:getId() == itemId then
            return true
        end
    end
    return false
end

local function openConfiguredContainer(itemId)
    if isContainerOpen(itemId) then return false end
    if not canForceOpen(itemId) then return false end

    local slots = {getBack(), getAmmo(), getFinger(), getNeck(), getLeft(), getRight()}
    for _, slotItem in ipairs(slots) do
        if slotItem and slotItem:getId() == itemId then
            markForceOpen(itemId)
            g_game.open(slotItem)
            return true
        end
    end

    for _, container in pairs(g_game.getContainers()) do
        for _, item in ipairs(container:getItems()) do
            if item:isContainer() and item:getId() == itemId then
                markForceOpen(itemId)
                g_game.open(item)
                return true
            end
        end
    end

    local item = findItem(itemId)
    if item then
        markForceOpen(itemId)
        g_game.open(item)
        return true
    end

    return false
end

-- ============================================================================
-- SORTING MACRO (runs periodically, paused during BFS)
-- ============================================================================

sortingMacro = macro(300, function(m)
    if not config.sortEnabled and not config.forceOpen then
        m:setOff()
        return
    end

    -- Don't interfere during container BFS
    if ContainerBFS.isActive() then return end

    -- Don't interfere during active looting
    if isLootLocked() then return end

    -- Item sorting
    if config.sortEnabled then
        for _, container in pairs(getContainers()) do
            local containerName = container:getName()
            if not isExcludedContainer(containerName) then
                local containerItemId = container:getContainerItem():getId()
                for _, item in ipairs(container:getItems()) do
                    local itemId = item:getId()
                    local destination = findDestinationForItem(itemId)
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

    -- Force open containers (early return above already guards loot lock)
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
            if not purseContainer and not isContainerOpen(PURSE_ITEM_ID) then
                if canForceOpen(PURSE_ITEM_ID) then
                    local purseItem = getPurse()
                    if purseItem then
                        markForceOpen(PURSE_ITEM_ID)
                        use(purseItem)
                        return
                    end
                end
            end
        end

        -- Force open loot bag
        if config.lootBag then
            local lootBagContainer = getContainerByItem(LOOT_BAG_ITEM_ID)
            if not lootBagContainer and not isContainerOpen(LOOT_BAG_ITEM_ID) then
                if canForceOpen(LOOT_BAG_ITEM_ID) then
                    local lootBag = findItem(LOOT_BAG_ITEM_ID)
                    if lootBag then
                        local purseContainer = getContainerByItem(PURSE_ITEM_ID)
                        if purseContainer then
                            markForceOpen(LOOT_BAG_ITEM_ID)
                            g_game.open(lootBag, purseContainer)
                        else
                            use(getPurse())
                        end
                        return
                    end
                end
            end
        end
    end

    -- Nothing to do
    m:setOff()
end)
