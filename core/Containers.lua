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
        -- Also check by container item type (some quivers don't have "quiver" in name)
        local containerItem = container:getContainerItem()
        if containerItem and containerItem:isContainer() then
            -- Quiver IDs: 35848 (Quiver), 35849 (Red Quiver), etc.
            local itemId = containerItem:getId()
            -- Common quiver item IDs (expanded range)
            if itemId >= 35847 and itemId <= 35860 then
                return true
            end
        end
    end
    return false
end

-- Helper: Get inventory item by slot (cross-client compatible)
-- Uses OTClient global constants when available, with fallbacks
-- OTClient slot constants (globals):
--   InventorySlotHead, InventorySlotNeck, InventorySlotBack, InventorySlotBody
--   InventorySlotRight, InventorySlotLeft, InventorySlotLeg, InventorySlotFeet
--   InventorySlotFinger, InventorySlotAmmo

local function getInventoryItemSafe(slotId)
    local player = g_game.getLocalPlayer()
    if not player then return nil end
    
    -- Try direct player method first
    if player.getInventoryItem then
        local ok, item = pcall(function() return player:getInventoryItem(slotId) end)
        if ok and item then return item end
    end
    
    return nil
end

-- Get quiver slot item (right hand or ammo)
local function getQuiverItem()
    local player = g_game.getLocalPlayer()
    if not player then return nil end
    
    -- Try right hand slot using global constant or fallback
    local rightSlot = InventorySlotRight or 6
    if player.getInventoryItem then
        local ok, item = pcall(function() return player:getInventoryItem(rightSlot) end)
        if ok and item then
            local okC, isContainer = pcall(function() return item:isContainer() end)
            if okC and isContainer then
                return item, "right"
            end
        end
    end
    
    -- Fallback: try global getRight()
    if getRight then
        local ok, item = pcall(getRight)
        if ok and item then
            local okC, isContainer = pcall(function() return item:isContainer() end)
            if okC and isContainer then
                return item, "right_global"
            end
        end
    end
    
    -- Try ammo slot using global constant or fallback
    local ammoSlot = InventorySlotAmmo or 10
    if player.getInventoryItem then
        local ok, item = pcall(function() return player:getInventoryItem(ammoSlot) end)
        if ok and item then
            local okC, isContainer = pcall(function() return item:isContainer() end)
            if okC and isContainer then
                return item, "ammo"
            end
        end
    end
    
    -- Fallback: try global getAmmo()
    if getAmmo then
        local ok, item = pcall(getAmmo)
        if ok and item then
            local okC, isContainer = pcall(function() return item:isContainer() end)
            if okC and isContainer then
                return item, "ammo_global"
            end
        end
    end
    
    return nil, nil
end

-- Helper: Open equipped quiver from right hand/ammo slot (for paladins)
-- FIXED v12.2: Uses OTClient slot constants for OpenTibiaBR compatibility
local function openQuiver()
    if isQuiverOpen() then return true end
    
    local quiverItem, source = getQuiverItem()
    if quiverItem then
        local Client = getClient()
        if Client and Client.open then
            Client.open(quiverItem)
        else
            g_game.open(quiverItem)
        end
        return true
    end
    
    return false
end

-- Helper: Retry opening quiver a few times (handles delayed equips)
local function openQuiverWithRetry(attempts)
    attempts = attempts or 3
    if openQuiver() then return end
    if attempts <= 1 then return end
    schedule(300, function()  -- Increased from 250 for better reliability
        openQuiverWithRetry(attempts - 1)
    end)
end

-- ============================================================================
-- BFS CONTAINER OPENER (OTClient Optimized v12.2)
-- FIXED: Infinite loop prevention for OpenTibiaBR
-- FIXED: Proper slot tracking with itemId
-- FIXED: Quiver opening for OpenTibiaBR
-- ============================================================================
--[[
  OTClientBR API Reference (used here):
  - g_game.getContainers() -> map<int, Container>
  - g_game.getContainer(id) -> Container
  - g_game.open(item, previousContainer) -> containerId
  - g_game.seekInContainer(containerId, index) -> void (pagination)
  - container:getItems() -> deque<Item>
  - container:getCapacity() -> int
  - container:getSize() -> int (total items across all pages)
  - container:getFirstIndex() -> int (current page start index)
  - container:hasPages() -> bool
  - container:getId() -> int
  - container:getContainerItem() -> Item
  - item:isContainer() -> bool
  - item:getId() -> int
  
  Architecture (SRP/SOLID):
  - ContainerQueue: Manages the queue of containers to open
  - ContainerTracker: Tracks opened containers to prevent duplicates
  - ContainerScanner: Scans containers for nested containers
  - ContainerOpener: Orchestrates the opening process
  - ForceOpenTracker: Prevents infinite open/close loops (NEW in v12.1)
]]

-- ============================================================================
-- UTILITY FUNCTIONS (DRY - Single Definition)
-- ============================================================================

-- Get current timestamp in milliseconds (defined early for ForceOpenTracker)
local function getNow()
    if now then return now end
    if g_clock and g_clock.millis then return g_clock.millis() end
    return os.time() * 1000
end

-- ============================================================================
-- FORCE OPEN TRACKER (Prevents infinite open/close loops)
-- ============================================================================
local ForceOpenTracker = {
    lastAttempt = {},       -- itemId -> timestamp
    cooldownMs = 2000,      -- Wait 2 seconds between attempts for same container
    openedThisCycle = {},   -- itemId -> true (containers opened this macro cycle)
    cycleStart = 0,         -- When the current cycle started
    cycleMaxDuration = 500, -- Max duration of a single macro cycle
}

function ForceOpenTracker.reset()
    ForceOpenTracker.lastAttempt = {}
    ForceOpenTracker.openedThisCycle = {}
    ForceOpenTracker.cycleStart = 0
end

function ForceOpenTracker.canAttempt(itemId)
    local currentTime = getNow()
    local lastTime = ForceOpenTracker.lastAttempt[itemId]
    if lastTime and (currentTime - lastTime) < ForceOpenTracker.cooldownMs then
        return false
    end
    return true
end

function ForceOpenTracker.markAttempt(itemId)
    ForceOpenTracker.lastAttempt[itemId] = getNow()
    ForceOpenTracker.openedThisCycle[itemId] = true
end

function ForceOpenTracker.startCycle()
    local currentTime = getNow()
    -- Reset cycle tracking if enough time has passed
    if (currentTime - ForceOpenTracker.cycleStart) > ForceOpenTracker.cycleMaxDuration then
        ForceOpenTracker.openedThisCycle = {}
        ForceOpenTracker.cycleStart = currentTime
    end
end

function ForceOpenTracker.wasOpenedThisCycle(itemId)
    return ForceOpenTracker.openedThisCycle[itemId] == true
end

-- Generate unique key for container slot
local function makeSlotKey(containerId, slotIndex)
    return string.format("%d:%d", containerId or 0, slotIndex or 0)
end

-- Get slot information with pagination support
local function getSlotInfo(container, slotIndex)
    if not container then return slotIndex, slotIndex end
    local firstIndex = 0
    if container.getFirstIndex then
        firstIndex = container:getFirstIndex() or 0
    end
    local absoluteSlot = firstIndex + (slotIndex - 1)  -- Convert 1-based to 0-based
    return slotIndex, absoluteSlot
end

-- ============================================================================
-- CLIENT SERVICE HELPERS (Cross-client compatibility)
-- ============================================================================
local function getClient()
  return ClientService
end

-- Request container queue sync (OpenTibiaBR feature for accuracy)
local function requestContainerSync()
  local Client = getClient()
  if Client and Client.requestContainerQueue then
    pcall(function() Client.requestContainerQueue() end)
  end
end

-- Refresh a single container (OpenTibiaBR feature)
local function refreshContainer(container)
  local Client = getClient()
  if Client and Client.refreshContainer then
    return pcall(function() Client.refreshContainer(container) end)
  end
  return false
end

-- Check if using enhanced APIs
local function hasEnhancedAPIs()
  local Client = getClient()
  return Client and Client.isOpenTibiaBR and Client.isOpenTibiaBR()
end

-- ============================================================================
-- CONTAINER TRACKER (SRP - Tracks opened containers)
-- FIXED v12.2: Track by itemId+containerId instead of just slot position
-- This prevents infinite loops when containers shift positions
-- ============================================================================
local ContainerTracker = {
    openedSlots = {},        -- slotKey -> timestamp (when opened)
    pendingSlots = {},       -- slotKey -> { timestamp, itemId }
    openedItemIds = {},      -- itemId -> timestamp (track by item ID to prevent re-opens)
    openedContainerIds = {}, -- containerId -> true (containers that are currently open)
    graceMs = 8000,          -- Grace period to prevent re-opening (increased from 4000)
    pendingTimeoutMs = 3500, -- Timeout for pending opens (increased from 2500)
}

function ContainerTracker.reset()
    ContainerTracker.openedSlots = {}
    ContainerTracker.pendingSlots = {}
    ContainerTracker.openedItemIds = {}
    ContainerTracker.openedContainerIds = {}
end

function ContainerTracker.markOpened(slotKey, itemId)
    ContainerTracker.openedSlots[slotKey] = getNow()
    ContainerTracker.pendingSlots[slotKey] = nil
    -- Also track by itemId to prevent re-opening same container type
    if itemId then
        ContainerTracker.openedItemIds[itemId] = (ContainerTracker.openedItemIds[itemId] or 0) + 1
    end
end

function ContainerTracker.markContainerOpen(containerId)
    if containerId then
        ContainerTracker.openedContainerIds[containerId] = true
    end
end

function ContainerTracker.markContainerClosed(containerId)
    if containerId then
        ContainerTracker.openedContainerIds[containerId] = nil
    end
end

function ContainerTracker.isContainerOpen(containerId)
    return ContainerTracker.openedContainerIds[containerId] == true
end

function ContainerTracker.markPending(slotKey, itemId)
    ContainerTracker.pendingSlots[slotKey] = { 
        timestamp = getNow(),
        itemId = itemId 
    }
end

function ContainerTracker.isRecentlyOpened(slotKey)
    local timestamp = ContainerTracker.openedSlots[slotKey]
    if not timestamp then return false end
    return (getNow() - timestamp) < ContainerTracker.graceMs
end

function ContainerTracker.isPending(slotKey)
    local entry = ContainerTracker.pendingSlots[slotKey]
    if not entry then return false end
    local elapsed = getNow() - entry.timestamp
    if elapsed > ContainerTracker.pendingTimeoutMs then
        ContainerTracker.pendingSlots[slotKey] = nil
        return false
    end
    return true
end

-- Check if an item type has been opened too many times (prevents infinite loop)
function ContainerTracker.getItemOpenCount(itemId)
    return ContainerTracker.openedItemIds[itemId] or 0
end

-- Maximum times we'll open the same container type per session
local MAX_OPENS_PER_ITEM_TYPE = 20

function ContainerTracker.canOpen(slotKey, itemId)
    -- Check if slot was recently opened
    if ContainerTracker.isRecentlyOpened(slotKey) then return false end
    -- Check if pending
    if ContainerTracker.isPending(slotKey) then return false end
    -- Check if we've opened this item type too many times (infinite loop protection)
    if itemId and ContainerTracker.getItemOpenCount(itemId) >= MAX_OPENS_PER_ITEM_TYPE then
        return false
    end
    return true
end

-- Clear expired entries (call periodically)
function ContainerTracker.cleanup()
    local currentTime = getNow()
    for key, timestamp in pairs(ContainerTracker.openedSlots) do
        if (currentTime - timestamp) > ContainerTracker.graceMs * 2 then
            ContainerTracker.openedSlots[key] = nil
        end
    end
end

-- ============================================================================
-- CONTAINER QUEUE (SRP - Manages the BFS queue)
-- FIXED v12.2: Track itemId for infinite loop protection
-- ============================================================================
local ContainerQueue = {
    items = {},          -- Array of { item, containerId, slotIndex, slotKey, itemId }
    inQueue = {},        -- slotKey -> true (for O(1) lookup)
    queuedItemIds = {},  -- itemId -> count (track how many of each type queued)
}

function ContainerQueue.reset()
    ContainerQueue.items = {}
    ContainerQueue.inQueue = {}
    ContainerQueue.queuedItemIds = {}
end

function ContainerQueue.add(item, containerId, slotIndex, front)
    local _, absoluteSlot = getSlotInfo(g_game.getContainer(containerId), slotIndex)
    local slotKey = makeSlotKey(containerId, absoluteSlot)
    
    -- Get item ID for tracking
    local itemId = nil
    if item and item.getId then
        pcall(function() itemId = item:getId() end)
    end
    
    -- Skip if already in queue or recently opened
    if ContainerQueue.inQueue[slotKey] then return false end
    if not ContainerTracker.canOpen(slotKey, itemId) then return false end
    
    -- Additional check: limit same item type in queue
    if itemId then
        local queuedCount = ContainerQueue.queuedItemIds[itemId] or 0
        if queuedCount >= 10 then return false end  -- Max 10 of same container type in queue
        ContainerQueue.queuedItemIds[itemId] = queuedCount + 1
    end
    
    ContainerQueue.inQueue[slotKey] = true
    local entry = {
        item = item,
        containerId = containerId,
        slotIndex = slotIndex,
        slotKey = slotKey,
        itemId = itemId,
    }
    
    if front then
        table.insert(ContainerQueue.items, 1, entry)
    else
        table.insert(ContainerQueue.items, entry)
    end
    return true
end

function ContainerQueue.pop()
    if #ContainerQueue.items == 0 then return nil end
    local entry = table.remove(ContainerQueue.items, 1)
    if entry then
        ContainerQueue.inQueue[entry.slotKey] = nil
        -- Decrement queued item count
        if entry.itemId then
            local count = ContainerQueue.queuedItemIds[entry.itemId] or 0
            ContainerQueue.queuedItemIds[entry.itemId] = math.max(0, count - 1)
        end
    end
    return entry
end

function ContainerQueue.isEmpty()
    return #ContainerQueue.items == 0
end

function ContainerQueue.size()
    return #ContainerQueue.items
end

-- ============================================================================
-- CONTAINER SCANNER (SRP - Scans containers for nested items)
-- FIXED v12.2: Track already-open containers to prevent re-scanning
-- ============================================================================
local ContainerScanner = {
    scannedPages = {},      -- containerId -> { pageIndex -> true }
    scannedContainers = {}, -- containerId -> timestamp (prevent re-scanning same container)
    scanCooldownMs = 1000,  -- Minimum time between scans of same container
}

function ContainerScanner.reset()
    ContainerScanner.scannedPages = {}
    ContainerScanner.scannedContainers = {}
end

-- Check if container was recently scanned
function ContainerScanner.wasRecentlyScanned(containerId)
    local timestamp = ContainerScanner.scannedContainers[containerId]
    if not timestamp then return false end
    return (getNow() - timestamp) < ContainerScanner.scanCooldownMs
end

-- Mark container as scanned
function ContainerScanner.markScanned(containerId)
    ContainerScanner.scannedContainers[containerId] = getNow()
end

-- Scan a container for nested containers and add them to queue
function ContainerScanner.scan(container, prioritizeItemId)
    if not container then return 0 end
    
    local containerName = container:getName() or ""
    if isExcludedContainer(containerName) then return 0 end
    
    local containerId = container:getId()
    
    -- Skip if recently scanned (prevent over-scanning)
    if ContainerScanner.wasRecentlyScanned(containerId) then return 0 end
    ContainerScanner.markScanned(containerId)
    
    local items = container:getItems()
    local foundCount = 0
    
    for slotIndex, item in ipairs(items) do
        if item and item:isContainer() then
            local itemId = item:getId()
            -- Prioritize same-type containers (for nested backpack opening)
            local shouldPrioritize = prioritizeItemId and itemId == prioritizeItemId
            if ContainerQueue.add(item, containerId, slotIndex, shouldPrioritize) then
                foundCount = foundCount + 1
            end
        end
    end
    
    return foundCount
end

-- Scan all currently open containers
function ContainerScanner.scanAll(prioritizeItemId)
    -- OpenTibiaBR: Sync container state first for accuracy
    requestContainerSync()
    
    local containers = g_game.getContainers()
    local totalFound = 0
    
    for _, container in pairs(containers) do
        -- Mark as open in tracker
        ContainerTracker.markContainerOpen(container:getId())
        
        -- OpenTibiaBR: Refresh each container before scanning
        if hasEnhancedAPIs() then
            refreshContainer(container)
        end
        totalFound = totalFound + ContainerScanner.scan(container, prioritizeItemId)
    end
    
    return totalFound
end

-- Handle paged containers (OTClient pagination API)
function ContainerScanner.handlePages(container, onPageLoaded)
    if not container or not container.hasPages or not container:hasPages() then return end
    
    local containerId = container:getId()
    local capacity = container:getCapacity()
    local totalSize = container:getSize()
    local firstIndex = container:getFirstIndex()
    
    if capacity <= 0 or totalSize <= capacity then return end
    
    local currentPage = math.floor(firstIndex / capacity)
    local totalPages = math.ceil(totalSize / capacity)
    
    -- Initialize page tracking
    ContainerScanner.scannedPages[containerId] = ContainerScanner.scannedPages[containerId] or {}
    ContainerScanner.scannedPages[containerId][currentPage] = true
    
    -- Find next unvisited page
    for pageIdx = 0, totalPages - 1 do
        if not ContainerScanner.scannedPages[containerId][pageIdx] then
            local targetIndex = pageIdx * capacity
            schedule(150, function()
                g_game.seekInContainer(containerId, targetIndex)
                schedule(200, function()
                    local c = g_game.getContainer(containerId)
                    if c and onPageLoaded then
                        onPageLoaded(c)
                    end
                end)
            end)
            return true  -- Processing a page
        end
    end
    
    return false  -- All pages scanned
end

-- ============================================================================
-- CONTAINER OPENER (Orchestrator - Main Controller)
-- FIXED v12.2: Added lastPendingEntry for accurate open tracking
-- ============================================================================
local ContainerOpener = {
    -- State
    isProcessing = false,
    isPaused = false,
    
    -- Timing configuration
    openDelayMs = 200,      -- Delay between opens (increased from 180)
    lastOpenTime = 0,
    settleDelayMs = 6000,   -- Time to keep scanning after last activity (reduced from 8000)
    activeUntil = 0,        -- Timestamp until which we keep scanning
    
    -- Stability tracking
    emptyQueueCount = 0,
    requiredEmptyCount = 3, -- How many empty scans before finishing
    
    -- Retry configuration  
    maxRetries = 3,         -- Reduced from 4 to fail faster
    retryCount = {},        -- slotKey -> count
    
    -- Pending entry tracking (for matching opened containers)
    lastPendingEntry = nil,
    
    -- Callbacks
    onComplete = nil,
}

-- Reset all state
function ContainerOpener.reset()
    ContainerOpener.isProcessing = false
    ContainerOpener.isPaused = false
    ContainerOpener.lastOpenTime = 0
    ContainerOpener.activeUntil = 0
    ContainerOpener.emptyQueueCount = 0
    ContainerOpener.retryCount = {}
    ContainerOpener.lastPendingEntry = nil
    ContainerOpener.onComplete = nil
    
    -- Reset sub-modules
    ContainerQueue.reset()
    ContainerTracker.reset()
    ContainerScanner.reset()
end

-- Extend active period (called when new activity detected)
function ContainerOpener.extendActiveTime()
    ContainerOpener.activeUntil = getNow() + ContainerOpener.settleDelayMs
    ContainerOpener.emptyQueueCount = 0
end

-- Check if still in active scanning period
function ContainerOpener.isActive()
    return ContainerOpener.isProcessing or getNow() < ContainerOpener.activeUntil
end

-- Queue a container item for opening (public interface)
function ContainerOpener.queueItem(item, containerId, slotIndex, prioritize)
    if not item or not item:isContainer() then return false end
    return ContainerQueue.add(item, containerId, slotIndex, prioritize)
end

-- Mark a container as dirty for rescanning
function ContainerOpener.markDirty(container)
    if not container then return end
    -- Immediate rescan for active processing
    if ContainerOpener.isActive() then
        ContainerScanner.scan(container)
    end
end

-- Schedule delayed rescans to catch late-loaded items
local rescanTimers = {}
function ContainerOpener.scheduleRescan(containerId)
    if not containerId or rescanTimers[containerId] then return end
    rescanTimers[containerId] = true
    
    local delays = { 200, 500, 1000 }
    for _, delay in ipairs(delays) do
        schedule(delay, function()
            local container = g_game.getContainer(containerId)
            if container and ContainerOpener.isActive() then
                ContainerScanner.scan(container)
                ContainerScanner.handlePages(container, function(c)
                    ContainerScanner.scan(c)
                    if ContainerOpener.isProcessing then
                        schedule(50, ContainerOpener.processNext)
                    end
                end)
            end
        end)
    end
    
    schedule(1100, function()
        rescanTimers[containerId] = nil
    end)
end

-- ============================================================================
-- PROCESS NEXT (Clean OTClient implementation)
-- ============================================================================
function ContainerOpener.processNext()
    if not ContainerOpener.isProcessing then return end
    if ContainerOpener.isPaused then return end
    
    local currentTime = getNow()
    
    -- Respect timing delay between opens
    local elapsed = currentTime - ContainerOpener.lastOpenTime
    if elapsed < ContainerOpener.openDelayMs then
        schedule(ContainerOpener.openDelayMs - elapsed + 20, ContainerOpener.processNext)
        return
    end
    
    -- Check if queue is empty
    if ContainerQueue.isEmpty() then
        -- Rescan all containers to find any new nested containers
        local found = ContainerScanner.scanAll()
        
        if ContainerQueue.isEmpty() then
            ContainerOpener.emptyQueueCount = ContainerOpener.emptyQueueCount + 1
            
            -- Keep scanning during settle period or until stable
            if currentTime < ContainerOpener.activeUntil or 
               ContainerOpener.emptyQueueCount < ContainerOpener.requiredEmptyCount then
                schedule(200, ContainerOpener.processNext)
                return
            end
            
            -- All done - finish up
            ContainerOpener.finish()
            return
        end
        
        -- Found new items, reset stability counter
        ContainerOpener.emptyQueueCount = 0
    end
    
    -- Get next entry from queue
    local entry = ContainerQueue.pop()
    if not entry then
        schedule(50, ContainerOpener.processNext)
        return
    end
    
    -- Verify parent container still exists
    local parentContainer = g_game.getContainer(entry.containerId)
    if not parentContainer then
        -- Parent closed, skip this entry
        schedule(50, ContainerOpener.processNext)
        return
    end
    
    -- Get fresh item reference from the slot
    local items = parentContainer:getItems()
    local item = items[entry.slotIndex]
    
    -- Validate item is still a container at that slot
    if not item or not item:isContainer() then
        -- Item moved or changed, try to find it
        for idx, candidate in ipairs(items) do
            if candidate and candidate:isContainer() then
                local _, absSlot = getSlotInfo(parentContainer, idx)
                local candidateKey = makeSlotKey(entry.containerId, absSlot)
                if ContainerTracker.canOpen(candidateKey) then
                    item = candidate
                    entry.slotIndex = idx
                    entry.slotKey = candidateKey
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
    
    -- Final check if this slot was recently opened
    if not ContainerTracker.canOpen(entry.slotKey, entry.itemId) then
        schedule(50, ContainerOpener.processNext)
        return
    end
    
    -- Check retry limit
    local retries = ContainerOpener.retryCount[entry.slotKey] or 0
    if retries >= ContainerOpener.maxRetries then
        ContainerTracker.markOpened(entry.slotKey, entry.itemId)  -- Give up on this slot
        schedule(50, ContainerOpener.processNext)
        return
    end
    ContainerOpener.retryCount[entry.slotKey] = retries + 1
    
    -- Mark as pending and record timing (with itemId)
    ContainerTracker.markPending(entry.slotKey, entry.itemId)
    ContainerOpener.lastOpenTime = currentTime
    
    -- Store the pending entry for matching when container opens
    ContainerOpener.lastPendingEntry = entry
    
    -- Open the container using OTClient API
    -- g_game.open(item, nil) opens in a new window
    local Client = getClient()
    if Client and Client.open then
        Client.open(item, nil)
    else
        g_game.open(item, nil)
    end
    
    -- OpenTibiaBR: Refresh parent container after opening nested
    if hasEnhancedAPIs() then
        schedule(100, function()
            refreshContainer(parentContainer)
        end)
    end
    
    -- Schedule next processing
    schedule(ContainerOpener.openDelayMs + 80, ContainerOpener.processNext)
end

-- ============================================================================
-- FINISH (Clean implementation)
-- ============================================================================
function ContainerOpener.finish()
    ContainerOpener.isProcessing = false
    ContainerOpener.lastPendingEntry = nil
    
    -- Cleanup tracker
    ContainerTracker.cleanup()
    
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
    
    -- Emit event for other modules
    if EventBus and EventBus.emit then
        EventBus.emit("containers:open_all_complete")
    end
end

-- ============================================================================
-- START (Clean implementation)
-- ============================================================================
function ContainerOpener.start(onComplete)
    ContainerOpener.reset()
    ContainerOpener.isProcessing = true
    ContainerOpener.onComplete = onComplete
    ContainerOpener.lastOpenTime = 0
    ContainerOpener.extendActiveTime()
    
    -- OpenTibiaBR: Request container queue sync for accuracy
    requestContainerSync()
    
    -- Initial scan of all open containers
    ContainerScanner.scanAll()
    
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
    if not ContainerOpener.isActive() then return end
    if not container then return end
    
    local containerId = container:getId()
    
    -- OpenTibiaBR: Refresh the newly opened container for accurate items
    if hasEnhancedAPIs() then
        refreshContainer(container)
    end
    
    -- Mark the container as open in tracker
    ContainerTracker.markContainerOpen(containerId)
    
    -- Mark the slot as successfully opened
    -- Use the stored pending entry for accurate matching
    local containerItem = container:getContainerItem()
    local openedItemId = containerItem and containerItem:getId() or nil
    
    if ContainerOpener.lastPendingEntry then
        local entry = ContainerOpener.lastPendingEntry
        ContainerTracker.markOpened(entry.slotKey, entry.itemId)
        ContainerOpener.lastPendingEntry = nil
    else
        -- Fallback: search for matching pending slot by itemId
        for slotKey, pendingInfo in pairs(ContainerTracker.pendingSlots) do
            if openedItemId and pendingInfo.itemId == openedItemId then
                ContainerTracker.markOpened(slotKey, openedItemId)
                break
            end
        end
        -- If still no match, mark the first pending slot
        for slotKey, pendingInfo in pairs(ContainerTracker.pendingSlots) do
            ContainerTracker.markOpened(slotKey, pendingInfo.itemId)
            break
        end
    end
    
    -- Scan the newly opened container for nested containers
    -- But only if we're actively processing (prevents loops during normal gameplay)
    if ContainerOpener.isProcessing then
        ContainerScanner.scan(container)
    end
    
    -- Handle paged containers
    ContainerScanner.handlePages(container, function(c)
        if ContainerOpener.isProcessing then
            ContainerScanner.scan(c)
            schedule(50, ContainerOpener.processNext)
        end
    end)
    
    -- Schedule rescans for late-loaded items (only when processing)
    if ContainerOpener.isProcessing then
        ContainerOpener.scheduleRescan(containerId)
    end
    
    -- Extend active time since we got a response
    ContainerOpener.extendActiveTime()
    
    -- Trigger processing immediately
    if ContainerOpener.isProcessing then
        schedule(50, ContainerOpener.processNext)
    end
end

-- Verify a container is properly open and synced (OpenTibiaBR enhanced)
function ContainerOpener.verifyContainer(containerId)
    local container = g_game.getContainer(containerId)
    if not container then return false end
    
    -- OpenTibiaBR: Request refresh and verify item count
    if hasEnhancedAPIs() then
        refreshContainer(container)
        -- Re-fetch after refresh
        container = g_game.getContainer(containerId)
        if not container then return false end
    end
    
    local items = container:getItems()
    local capacity = container:getCapacity()
    
    -- Container is valid if we can read its properties
    return items ~= nil and capacity > 0
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

    -- Apply minimize based on config entry or global auto-minimize
    -- FIXED v12.2: Always minimize when autoMinimize is enabled (not just during processing)
    -- This ensures main backpack gets minimized too
    local shouldMinimize = false
    if entry and entry.minimize then
        shouldMinimize = true
    elseif config.autoMinimize then
        -- Always minimize when auto-minimize is enabled (fixes main BP not minimizing)
        shouldMinimize = true
    end
    
    if shouldMinimize then
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
    if ContainerOpener.isActive() and entry and entry.openNested then
        local containerId = container:getId()
        for slotIndex, item in ipairs(container:getItems()) do
            if item:isContainer() and item:getId() == itemId then
                -- Queue with priority (front of queue)
                ContainerQueue.add(item, containerId, slotIndex, true)
            end
        end
        if ContainerOpener.isProcessing then
            schedule(20, ContainerOpener.processNext)
        end
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
                -- FIXED v12.2: getContainers() returns a map, not array - use pairs to count
                local containerCount = 0
                for _ in pairs(g_game.getContainers()) do containerCount = containerCount + 1 end
                
                if containerCount > 0 then
                    startContainerBFS()
                    -- Open quiver with longer delay to ensure main BP is processed
                    schedule(400, function() openQuiverWithRetry(5) end)
                elseif attempts < 12 then
                    -- retry a few times (~1.8s total)
                    schedule(150, waitForMain)
                else
                    -- Fallback: start anyway after retries
                    startContainerBFS()
                    schedule(400, function() openQuiverWithRetry(5) end)
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
        
        -- Always open quiver (default behavior) - with more retries
        schedule(400, function() openQuiverWithRetry(5) end)
        
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

-- Helper: Check if a container with the given itemId is already open
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

-- Pure function: Open container from configured list
-- FIXED: Prevents infinite loop by checking if already open and using cooldown
local function openConfiguredContainer(itemId)
    -- Skip if already open (prevents toggle behavior)
    if isContainerOpen(itemId) then
        return false
    end
    
    -- Skip if we already tried this recently (prevents rapid cycling)
    if not ForceOpenTracker.canAttempt(itemId) then
        return false
    end
    
    -- Skip if we already opened this during the current macro cycle
    if ForceOpenTracker.wasOpenedThisCycle(itemId) then
        return false
    end
    
    -- Check equipment slots first
    local slots = {getBack(), getAmmo(), getFinger(), getNeck(), getLeft(), getRight()}
    for _, slotItem in ipairs(slots) do
        if slotItem and slotItem:getId() == itemId then
            ForceOpenTracker.markAttempt(itemId)
            g_game.open(slotItem)
            return true
        end
    end
    
    -- Check in open containers
    for _, container in pairs(g_game.getContainers()) do
        for _, item in ipairs(container:getItems()) do
            if item:isContainer() and item:getId() == itemId then
                ForceOpenTracker.markAttempt(itemId)
                g_game.open(item)
                return true
            end
        end
    end
    
    -- Try to find anywhere
    local item = findItem(itemId)
    if item then
        ForceOpenTracker.markAttempt(itemId)
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
    
    -- Start a new cycle for ForceOpenTracker
    ForceOpenTracker.startCycle()
    
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
        
        -- Force open purse (already has protection via openConfiguredContainer pattern)
        if config.purse then
            local purseContainer = getContainerByItem(PURSE_ITEM_ID)
            if not purseContainer and not isContainerOpen(PURSE_ITEM_ID) then
                if ForceOpenTracker.canAttempt(PURSE_ITEM_ID) then
                    local purseItem = getPurse()
                    if purseItem then
                        ForceOpenTracker.markAttempt(PURSE_ITEM_ID)
                        use(purseItem)
                        return
                    end
                end
            end
        end
        
        -- Force open loot bag (with protection)
        if config.lootBag then
            local lootBagContainer = getContainerByItem(LOOT_BAG_ITEM_ID)
            if not lootBagContainer and not isContainerOpen(LOOT_BAG_ITEM_ID) then
                if ForceOpenTracker.canAttempt(LOOT_BAG_ITEM_ID) then
                    local lootBag = findItem(LOOT_BAG_ITEM_ID)
                    if lootBag then
                        local purseContainer = getContainerByItem(PURSE_ITEM_ID)
                        if purseContainer then
                            ForceOpenTracker.markAttempt(LOOT_BAG_ITEM_ID)
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
    
    -- Turn off if nothing to do
    m:setOff()
end)

-- Event handlers to trigger sorting
onAddItem(function(container, slot, item, oldItem)
    -- If a container item is added into an open container, queue it for opening
    if item and item:isContainer() and ContainerOpener.isActive() then
        local containerId = container and container:getId() or 0
        local containerName = container and container:getName() or ""
        
        if not isExcludedContainer(containerName) then
            -- Queue the new container for opening (slot is 0-based, convert to 1-based)
            local slotIndex = (slot or 0) + 1
            if ContainerQueue.add(item, containerId, slotIndex, true) then
                -- Trigger processing if not already running
                if not ContainerOpener.isProcessing then
                    ContainerOpener.isProcessing = true
                    ContainerOpener.extendActiveTime()
                end
                schedule(10, ContainerOpener.processNext)
            end
        end
    end

    -- Mark container for rescan
    if container then
        ContainerOpener.markDirty(container)
    end

    if sortingMacro and (config.sortEnabled or config.forceOpen) then
        sortingMacro:setOn()
    end
end)

onRemoveItem(function(container, slot, item)
    if container then
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
    if container then
        local containerId = container:getId()
        
        -- Clean up page tracking for closed container
        if ContainerScanner and ContainerScanner.scannedPages then
            ContainerScanner.scannedPages[containerId] = nil
        end
        -- Also clean scanned container tracking
        if ContainerScanner and ContainerScanner.scannedContainers then
            ContainerScanner.scannedContainers[containerId] = nil
        end
        -- Mark container as closed in tracker
        if ContainerTracker and ContainerTracker.markContainerClosed then
            ContainerTracker.markContainerClosed(containerId)
        end
    end
    
    if container and not container.lootContainer then
        if sortingMacro and (config.sortEnabled or config.forceOpen) then
            sortingMacro:setOn()
        end
    end
end)
