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

-- Initialize config from CharacterDB with migration from legacy storage
local function initConfig()
    local cfg
    
    -- Try to load from CharacterDB first
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
        cfg = CharacterDB.getModule("containers")
        
        -- Migration: if CharacterDB is empty but legacy storage has data
        if (not cfg.containerList or #cfg.containerList == 0) and storage[panelName] then
            local legacy = storage[panelName]
            if legacy.containerList and #legacy.containerList > 0 then
                -- Migrate from legacy storage
                cfg = deepClone(legacy)
                CharacterDB.setModule("containers", cfg)
            end
        end
    else
        -- Fallback to legacy storage (CharacterDB not ready yet)
        if type(storage[panelName]) ~= "table" then
            storage[panelName] = deepClone(DEFAULT_CONFIG)
        end
        cfg = storage[panelName]
    end
    
    -- Ensure all required fields exist (migration for old configs)
    for key, defaultValue in pairs(DEFAULT_CONFIG) do
        if cfg[key] == nil then
            cfg[key] = type(defaultValue) == "table" and deepClone(defaultValue) or defaultValue
        end
    end
    
    return cfg
end

-- Create a proxy that auto-saves to CharacterDB on changes
local function createConfigProxy(initialConfig)
    local _data = initialConfig
    local _saveTimer = nil
    
    local function scheduleSave()
        if not CharacterDB or not CharacterDB.isReady or not CharacterDB.isReady() then return end
        if _saveTimer then removeEvent(_saveTimer) end
        _saveTimer = scheduleEvent(function()
            _saveTimer = nil
            CharacterDB.setModule("containers", _data)
        end, 300)
    end
    
    return setmetatable({}, {
        __index = function(t, k)
            return _data[k]
        end,
        __newindex = function(t, k, v)
            _data[k] = v
            scheduleSave()
        end,
        __pairs = function(t) return pairs(_data) end,
        __ipairs = function(t) return ipairs(_data) end,
    })
end

local config = createConfigProxy(initConfig())

-- Force save function (call after modifying nested tables like containerList)
local function saveConfig()
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
        CharacterDB.setModule("containers", {
            purse = config.purse,
            autoMinimize = config.autoMinimize,
            autoOpenOnLogin = config.autoOpenOnLogin,
            sortEnabled = config.sortEnabled,
            forceOpen = config.forceOpen,
            renameEnabled = config.renameEnabled,
            lootBag = config.lootBag,
            containerList = config.containerList,
            windowHeight = config.windowHeight
        })
    end
end

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
            if entry.enabled and entry.openNested and entry.itemId then
                for _, container in pairs(g_game.getContainers()) do
                    local containerItem = container:getContainerItem()
                    if containerItem and containerItem:getId() == entry.itemId then
                        for _, item in ipairs(container:getItems()) do
                            if item:isContainer() and item:getId() == entry.itemId then
                                g_game.open(item)
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
        -- Trigger immediate sorting when enabled
        if config.sortEnabled and sortingMacro then
            sortingMacro:setOn()
        end
    end
    
    setupWindow.forceOpen:setChecked(config.forceOpen)
    setupWindow.forceOpen.onClick = function(widget)
        config.forceOpen = not config.forceOpen
        widget:setChecked(config.forceOpen)
        -- Trigger immediate check when enabled
        if config.forceOpen and sortingMacro then
            sortingMacro:setOn()
        end
    end
    
    setupWindow.renameEnabled:setChecked(config.renameEnabled)
    setupWindow.renameEnabled.onClick = function(widget)
        config.renameEnabled = not config.renameEnabled
        widget:setChecked(config.renameEnabled)
    end
    
    setupWindow.lootBag:setChecked(config.lootBag)
    setupWindow.lootBag.onClick = function(widget)
        config.lootBag = not config.lootBag
        widget:setChecked(config.lootBag)
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

--[[
  Container Opening System v4 - Slot-Based Tracking
  
  Key Fix: Track opened containers by (parentContainerId, slotIndex) pairs.
  This uniquely identifies each nested container and prevents reopening loops.
  
  Algorithm:
  1. Maintain a set of "opened slots" as "containerId_slot" strings
  2. When scanning, skip any container item at a slot we've already opened
  3. When we successfully open, mark that slot as opened
  4. Reset the set when starting a new open-all operation
]]

-- ============================================================================
-- BFS CONTAINER OPENING STATE
-- ============================================================================
local isProcessing = false
local lastOpenTime = 0
local openedSlots = {}              -- "containerId_slot" -> true (tracks what we've opened)
local pendingSlotKey = nil          -- The slot we're currently trying to open
local openAttempts = 0
local MAX_ATTEMPTS = 2
local initialContainerCount = 0

-- Timing
local OPEN_DELAY = 250              -- ms between opens
local WAIT_FOR_OPEN = 400           -- ms to wait for container to appear

-- ============================================================================
-- PURE HELPER FUNCTIONS
-- ============================================================================

-- Pure function: Get container window from game_containers module
-- Uses multiple fallback methods for better compatibility
local function getContainerWindow(containerId)
    -- Method 1: Try the standard game_containers module
    local gameContainers = modules.game_containers
    if gameContainers then
        -- Try getContainerWindow function
        if gameContainers.getContainerWindow then
            local window = gameContainers.getContainerWindow(containerId)
            if window then return window end
        end
        
        -- Try containerWindows table directly (some OTClient versions)
        if gameContainers.containerWindows and gameContainers.containerWindows[containerId] then
            return gameContainers.containerWindows[containerId]
        end
    end
    
    -- Method 2: Try finding by widget ID in the root
    local rootWidget = g_ui.getRootWidget()
    if rootWidget then
        -- Try common container window naming patterns
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

-- Pure function: Check if container name should be excluded from operations
local function isExcludedContainer(containerName)
    if not containerName then return false end
    local name = containerName:lower()
    return name:find("depot") or name:find("inbox") or name:find("quiver")
end

-- Pure function: Get configured entry for a container by its item ID
local function getContainerConfig(itemId)
    for _, entry in ipairs(config.containerList) do
        if entry.enabled and entry.itemId == itemId then
            return entry
        end
    end
    return nil
end

-- ============================================================================
-- CONTAINER OPERATIONS
-- ============================================================================

-- Open equipped quiver from right hand slot if available (always runs)
local function openQuiver()
    local rightItem = getRight()
    if rightItem and rightItem:isContainer() then
        g_game.open(rightItem)
        return true
    end
    return false
end

-- Minimize a container window
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

-- Maximize a container window
local function maximizeContainer(container)
    if not container then return end
    
    local window = getContainerWindow(container:getId())
    if window then
        if window.maximize then
            window:maximize()
        elseif window.setOn then
            window:setOn(true)
        elseif window.minimizeButton then
            window.minimizeButton:onClick()
        end
    end
end

-- Rename a container window based on config
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

-- Count open containers
local function countContainers()
    local count = 0
    for _ in pairs(g_game.getContainers()) do
        count = count + 1
    end
    return count
end

-- Find the first unopened nested container
-- Returns: item, slotKey or nil if none found
local function findNextContainer()
    for containerId, container in pairs(g_game.getContainers()) do
        local items = container:getItems()
        for slot, item in ipairs(items) do
            if item and item:isContainer() then
                local slotKey = containerId .. "_" .. slot
                -- Only return if we haven't already opened this slot
                if not openedSlots[slotKey] then
                    return item, slotKey, containerId, slot
                end
            end
        end
    end
    return nil
end

-- ============================================================================
-- MAIN PROCESSOR
-- ============================================================================
local function processNext()
    if not isProcessing then return end
    
    -- Respect timing
    local elapsed = now - lastOpenTime
    if elapsed < OPEN_DELAY then
        schedule(OPEN_DELAY - elapsed + 10, processNext)
        return
    end
    
    -- Find next container to open
    local item, slotKey, parentId, slot = findNextContainer()
    
    if not item then
        -- No more containers to open - we're done!
        isProcessing = false
        pendingSlotKey = nil
        
        -- Final minimize pass
        if config.autoMinimize then
            schedule(100, function()
                for _, container in pairs(g_game.getContainers()) do
                    minimizeContainer(container)
                end
            end)
        end
        return
    end
    
    -- Mark this slot as being opened (prevent re-attempts)
    openedSlots[slotKey] = true
    pendingSlotKey = slotKey
    lastOpenTime = now
    openAttempts = 0
    
    local countBefore = countContainers()
    
    -- Open the container
    g_game.open(item, nil)
    
    -- Wait and verify
    schedule(WAIT_FOR_OPEN, function()
        if not isProcessing then return end
        
        local countAfter = countContainers()
        
        if countAfter > countBefore then
            -- Success! Continue to next
            pendingSlotKey = nil
            schedule(50, processNext)
        else
            -- Failed - but slot is already marked, so we won't retry this one
            -- Just move on to the next
            pendingSlotKey = nil
            openAttempts = openAttempts + 1
            
            if openAttempts < MAX_ATTEMPTS then
                -- Try to re-fetch and open again
                local parentContainer = g_game.getContainer(parentId)
                if parentContainer then
                    local items = parentContainer:getItems()
                    local freshItem = items[slot]
                    if freshItem and freshItem:isContainer() then
                        g_game.open(freshItem, nil)
                        schedule(WAIT_FOR_OPEN, processNext)
                        return
                    end
                end
            end
            
            -- Move on
            schedule(50, processNext)
        end
    end)
end

-- ============================================================================
-- EVENT HANDLER
-- ============================================================================
onContainerOpen(function(container, previousContainer)
    if not container then return end
    
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
                elseif window.minimizeButton then
                    window.minimizeButton:onClick()
                end
            end
        end)
    elseif isProcessing and config.autoMinimize then
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
    
    -- Open nested containers if configured
    if entry and entry.openNested then
        schedule(300, function()
            for _, item in ipairs(container:getItems()) do
                if item:isContainer() and item:getId() == itemId then
                    g_game.open(item)
                    break  -- Only open one at a time
                end
            end
        end)
    end
    
    -- Trigger sorting macro
    if sortingMacro then
        sortingMacro:setOn()
    end
end)

-- ============================================================================
-- PUBLIC API
-- ============================================================================
local function startContainerBFS()
    -- Reset all state
    isProcessing = true
    lastOpenTime = 0
    openedSlots = {}                -- Clear the opened slots tracker
    pendingSlotKey = nil
    openAttempts = 0
    initialContainerCount = countContainers()
    
    -- Start processing
    schedule(100, processNext)
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
            -- Wait for main BP to open, then start BFS
            schedule(400, function()
                startContainerBFS()
                -- Open quiver after a small delay
                schedule(200, openQuiver)
            end)
        else
            warn("[Container Panel] No backpack in back slot!")
        end
    else
        -- Main backpack already open, start BFS directly
        startContainerBFS()
        -- Also try to open quiver
        schedule(200, openQuiver)
    end
end

-- Reopen all backpacks from back slot
function reopenBackpacks()
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
        schedule(350, openQuiver)
        
        -- Start BFS after a small delay to let main backpack open
        schedule(500, function()
            startContainerBFS()
        end)
    end)
end

-- Auto Open switch (toggle for auto-open on login)
containerUI.openAll:setOn(config.autoOpenOnLogin)
containerUI.openAll.onClick = function(widget)
    config.autoOpenOnLogin = not config.autoOpenOnLogin
    widget:setOn(config.autoOpenOnLogin)
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
containerUI.purseSwitch:setOn(config.purse)
containerUI.purseSwitch.onClick = function(widget)
    config.purse = not config.purse
    widget:setOn(config.purse)
end

-- Auto minimize switch
containerUI.autoMinSwitch:setOn(config.autoMinimize ~= false)
containerUI.autoMinSwitch.onClick = function(widget)
    config.autoMinimize = not config.autoMinimize
    widget:setOn(config.autoMinimize)
end

--[[
  Auto-Open on Re-Login Detection
  
  Uses onPlayerHealthChange to detect when player logs back in.
  When health changes from 0 (or initial state) to a positive value,
  it indicates a new login session.
]]

local lastKnownHealth = 0
local hasTriggeredThisSession = false

-- Detect login by watching for health to appear
onPlayerHealthChange(function(healthPercent)
    -- Only proceed if auto-open is enabled
    if not config.autoOpenOnLogin then return end
    
    -- Detect fresh login: health was 0 (or we just loaded) and now it's positive
    if lastKnownHealth == 0 and healthPercent > 0 and not hasTriggeredThisSession then
        hasTriggeredThisSession = true
        
        -- Delay to let game fully load
        schedule(1500, function()
            -- Auto-opening containers on login
            openAllContainers()
        end)
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
                    return getContainerByItem(entry.itemId, true)
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
            local purseContainer = getContainerByItem(23396)
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
            local lootBagContainer = getContainerByItem(23721)
            if not lootBagContainer then
                local lootBag = findItem(23721)
                if lootBag then
                    local purseContainer = getContainerByItem(23396)
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
    if sortingMacro and (config.sortEnabled or config.forceOpen) then
        sortingMacro:setOn()
    end
end)

onRemoveItem(function(container, slot, item)
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
    if container and not container.lootContainer then
        if sortingMacro and (config.sortEnabled or config.forceOpen) then
            sortingMacro:setOn()
        end
    end
end)
