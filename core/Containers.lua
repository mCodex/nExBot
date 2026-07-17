
setDefaultTab("Tools")
local panelName = "containerPanel"

local PURSE_ITEM_ID = 23396
local LOOT_BAG_ITEM_ID = 23721

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

local deepClone = nExBot.Shared.deepClone


local _configData = nil
local _saveTimer = nil

local function scheduleSave()
    if not CharacterDB or not CharacterDB.isReady or not CharacterDB.isReady() then return end
    if not _configData then return end
    if _saveTimer then removeEvent(_saveTimer) end
    _saveTimer = schedule(300, function()
        _saveTimer = nil
        CharacterDB.setModule("containers", _configData)
    end)
end

local function initConfig()
    local cfg = {}
    
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
        cfg = CharacterDB.getModule("containers") or {}
        
        if not cfg._migrated and storage[panelName] then
            local legacy = storage[panelName]
            if legacy.containerList and #legacy.containerList > 0 then
                cfg = deepClone(legacy)
            end
            cfg._migrated = true
            CharacterDB.setModule("containers", cfg)
        end
    else
        if storage[panelName] and type(storage[panelName]) == "table" then
            cfg = storage[panelName]
        end
    end
    
    for key, defaultValue in pairs(DEFAULT_CONFIG) do
        if cfg[key] == nil then
            cfg[key] = type(defaultValue) == "table" and deepClone(defaultValue) or defaultValue
        end
    end
    
    _configData = cfg
    return cfg
end

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

initConfig()
local config = createConfigProxy()

local function saveConfig()
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() and _configData then
        CharacterDB.setModule("containers", _configData)
    end
end

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

containerUI.openAll:setTooltip("When enabled, automatically opens all containers on re-login\n(Toggle ON to enable auto-open on each login)")
containerUI.setupBtn:setTooltip("Configure container names, sorting rules, and behavior")
containerUI.reopenAll:setTooltip("Close all containers and reopen from back slot")
containerUI.closeAll:setTooltip("Close all open containers")
containerUI.minimizeAll:setTooltip("Minimize all container windows")
containerUI.maximizeAll:setTooltip("Maximize all container windows")
containerUI.purseSwitch:setTooltip("Also open the purse when reopening")
containerUI.autoMinSwitch:setTooltip("Automatically minimize containers after opening")

syncUIWithConfig = function()
    if containerUI then
        containerUI.openAll:setOn(config.autoOpenOnLogin == true)
        containerUI.purseSwitch:setOn(config.purse == true)
        containerUI.autoMinSwitch:setOn(config.autoMinimize ~= false)
    end
end

syncUIWithConfig()

schedule(500, function()
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
        initConfig()
        syncUIWithConfig()
        if setupWindow then
            if refreshContainerList then refreshContainerList() end
            setupWindow.sortEnabled:setChecked(config.sortEnabled == true)
            setupWindow.forceOpen:setChecked(config.forceOpen == true)
            setupWindow.renameEnabled:setChecked(config.renameEnabled == true)
            setupWindow.lootBag:setChecked(config.lootBag == true)
        end
    end
end)

do
  local path = nExBot.paths.base .. "/core/Containers.otui"
  local content = nil
  if g_resources and g_resources.readFileContents then
    content = g_resources.readFileContents(path)
  end
  if content then
    g_ui.loadUIFromString(content)
  else
    warn("[Containers] Failed to load Containers.otui from " .. path)
  end
end

local setupWindow = nil
local selectedContainerIndex = nil

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

local function findContainerByItemId(list, itemId)
    for index, entry in ipairs(list) do
        if entry.itemId == itemId then
            return index, entry
        end
    end
    return nil, nil
end

refreshContainerList = function()
    if not setupWindow then return end
    
    local list = setupWindow.containerList
    list:destroyChildren()
    
    for index, entry in ipairs(config.containerList) do
        local label = g_ui.createWidget("ContainerEntry", list)
        label:setText(entry.name or "Container")
        label.enabled:setChecked(entry.enabled)
        
        label.minimize:setColor(entry.minimize and '#00FF00' or '#FF6666')
        label.minimize:setTooltip(entry.minimize and 'Opens Minimized' or 'Opens Normal')
        
        label.nested:setColor(entry.openNested and '#00FF00' or '#FF6666')
        label.nested:setTooltip(entry.openNested and 'Opens Nested' or 'No Nested')
        
        label.onMouseRelease = function()
            selectedContainerIndex = index
            setupWindow.containerId:setItemId(entry.itemId or 0)
            setupWindow.containerName:setText(entry.name or "")
            setupWindow.itemsList:setItems(entry.items or {})
            list:focusChild(label)
        end
        
        label.enabled.onClick = function()
            entry.enabled = not entry.enabled
            label.enabled:setChecked(entry.enabled)
            saveConfig()  -- Persist to CharacterDB
            if entry.enabled and sortingMacro and (config.sortEnabled or config.forceOpen) and not isLootLocked() then
                sortingMacro:setOn()
            end
        end
        
        label.minimize.onClick = function()
            entry.minimize = not entry.minimize
            label.minimize:setColor(entry.minimize and '#00FF00' or '#FF6666')
            label.minimize:setTooltip(entry.minimize and 'Opens Minimized' or 'Opens Normal')
            saveConfig()  -- Persist to CharacterDB
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
        
        label.nested.onClick = function()
            entry.openNested = not entry.openNested
            label.nested:setColor(entry.openNested and '#00FF00' or '#FF6666')
            label.nested:setTooltip(entry.openNested and 'Opens Nested' or 'No Nested')
            saveConfig()  -- Persist to CharacterDB
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
        
        label.remove.onClick = function()
            table.remove(config.containerList, index)
            refreshContainerList()
            selectedContainerIndex = nil
            saveConfig()  -- Persist to CharacterDB
        end
    end
end

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
    
    local h = tonumber(config.windowHeight)
    if not h or h < 150 then h = 220 end
    setupWindow:setHeight(h)
    
    setupWindow.onGeometryChange = function(widget, old, new)
        if new.height >= 150 and old.height > 0 and new.height ~= old.height then
            config.windowHeight = new.height
        end
    end
    
    setupWindow:hide()
    
    setupWindow.closeBtn.onClick = function()
        setupWindow:hide()
    end
    
    setupWindow.sortEnabled:setChecked(config.sortEnabled)
    setupWindow.sortEnabled.onClick = function(widget)
        config.sortEnabled = not config.sortEnabled
        widget:setChecked(config.sortEnabled)
        saveConfig()  -- Persist to CharacterDB
        if config.sortEnabled and sortingMacro and not isLootLocked() then
            sortingMacro:setOn()
        end
    end
    
    setupWindow.forceOpen:setChecked(config.forceOpen)
    setupWindow.forceOpen.onClick = function(widget)
        config.forceOpen = not config.forceOpen
        widget:setChecked(config.forceOpen)
        saveConfig()  -- Persist to CharacterDB
        if config.forceOpen and sortingMacro and not isLootLocked() then
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
            config.containerList[existingIndex].name = name
            config.containerList[existingIndex].items = items
        else
            config.containerList[#config.containerList + 1] = {
                name = name,
                enabled = true,
                itemId = itemId,
                minimize = false,
                openNested = false,
                items = items
            }
        end
        
        setupWindow.containerId:setItemId(0)
        setupWindow.containerName:setText("")
        setupWindow.itemsList:setItems({})
        selectedContainerIndex = nil
        
        refreshContainerList()
        saveConfig()  -- Persist to CharacterDB
        
        if config.sortEnabled and sortingMacro and not isLootLocked() then
            sortingMacro:setOn()
        end
    end
    
    UI.Container(function()
        if selectedContainerIndex and config.containerList[selectedContainerIndex] then
            config.containerList[selectedContainerIndex].items = setupWindow.itemsList:getItems()
            saveConfig()  -- Persist to CharacterDB
            if config.sortEnabled and sortingMacro and not isLootLocked() then
                sortingMacro:setOn()
            end
        end
    end, true, nil, setupWindow.itemsList)
    
    refreshContainerList()
end


local function isExcludedContainer(containerName)
    if not containerName then return false end
    local name = containerName:lower()
    return name:find("depot") or name:find("inbox") or name:find("quiver")
        or name:find("dead") or name:find("remains") or name:find("body of")
end

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

local function getContainerConfig(itemId)
    for _, entry in ipairs(config.containerList) do
        if entry.enabled and entry.itemId == itemId then
            return entry
        end
    end
    return nil
end


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

local ContainerBFS

local function schedulePendingTimeout(pending, stateGuard, onTimeoutFn)
    schedule(ContainerBFS.SAFETY_TIMEOUT, function()
        if ContainerBFS.pendingOpen ~= pending then return end
        if ContainerBFS.state ~= stateGuard then return end
        if onTimeoutFn then onTimeoutFn() end
    end)
end


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

local function getQuiverItem()
    local player = g_game.getLocalPlayer()
    if not player then return nil, nil end

    -- Right hand slot (quiver is equipped here for paladins)
    -- OTClient: InventorySlotRight = 5 (not 6 — slot 6 is left hand)
    local rightSlot = 5
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

    -- Ammo slot (some quiver types go here)
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

    -- Fallback: scan all inventory slots for quiver by item ID range
    local QUIVER_IDS = { [35847]=true, [35848]=true, [35849]=true, [35850]=true,
        [35851]=true, [35852]=true, [35853]=true, [35854]=true,
        [35855]=true, [35856]=true, [35857]=true, [35858]=true,
        [35859]=true, [35860]=true }
    if player.getInventoryItem then
        for slot = 0, 10 do
            local ok, item = pcall(function() return player:getInventoryItem(slot) end)
            if ok and item then
                local okId, itemId = pcall(function() return item:getId() end)
                if okId and QUIVER_IDS[itemId] then
                    return item, "slot_" .. slot
                end
            end
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


local MAX_OPEN_CONTAINERS = 19  -- server limit is typically 20

ContainerBFS = {
    state = "IDLE",
    queue = {},             -- array of {parentId, slot, itemId}
    queueIdx = 1,           -- index into queue for O(1) pops (replaces table.remove(queue,1))
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
    ContainerBFS.queueIdx = 1
    ContainerBFS.opened = {}
    ContainerBFS.openedTypes = {}
    ContainerBFS.pendingOpen = nil
    ContainerBFS.lastOpenTime = 0
    ContainerBFS.onCompleteCallback = nil
end

function ContainerBFS.isActive()
    return ContainerBFS.state ~= "IDLE"
end

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

function ContainerBFS.openNext()
    if ContainerBFS.state ~= "RUNNING" then return end

    local t = getNow()
    local elapsed = t - ContainerBFS.lastOpenTime
    if elapsed < ContainerBFS.OPEN_DELAY then
        schedule(ContainerBFS.OPEN_DELAY - elapsed + 20, ContainerBFS.openNext)
        return
    end

    local openCount = 0
    for _ in pairs(g_game.getContainers()) do openCount = openCount + 1 end
    if openCount >= MAX_OPEN_CONTAINERS then
        ContainerBFS.state = "PAUSED"
        return
    end

    while ContainerBFS.queueIdx <= #ContainerBFS.queue do
        local entry = ContainerBFS.queue[ContainerBFS.queueIdx]
        ContainerBFS.queueIdx = ContainerBFS.queueIdx + 1
        local parent = g_game.getContainer(entry.parentId)
        if parent then
            local items = parent:getItems()
            local item = items[entry.slot]

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
                local pending = { entry = entry, ts = getNow() }
                ContainerBFS.pendingOpen = pending
                ContainerBFS.lastOpenTime = getNow()

                local Client = getClient()
                if Client and Client.open then
                    Client.open(item, nil)
                else
                    g_game.open(item, nil)
                end

                if hasEnhancedAPIs() then
                    schedule(100, function() refreshContainer(parent) end)
                end

                schedule(ContainerBFS.SAFETY_TIMEOUT, function()
                    if ContainerBFS.pendingOpen ~= pending then return end
                    ContainerBFS.pendingOpen = nil
                    local stillOpen = g_game.getContainer(entry.parentId)
                    if stillOpen then
                        for idx, candidate in ipairs(stillOpen:getItems()) do
                            if candidate and candidate:isContainer() and candidate:getId() == entry.itemId then
                                local key = entry.parentId .. ":" .. idx
                                if not ContainerBFS.opened[key] then
                                    local retry = { parentId = entry.parentId, slot = idx, itemId = entry.itemId }
                                    ContainerBFS.queue[#ContainerBFS.queue + 1] = retry
                                end
                            end
                        end
                        ContainerBFS.scanContainer(stillOpen)
                    end
                    ContainerBFS.openNext()
                end)
                return  -- Wait for onContainerOpen or safety timeout
            end
        end
    end

    ContainerBFS.finish()
end

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
            local parent = g_game.getContainer(pending.entry.parentId)
            if parent then ContainerBFS.scanContainer(parent) end
            ContainerBFS.openNext()
        end
    end
end

function ContainerBFS.finish()
    local prevState = ContainerBFS.state
    ContainerBFS.state = "IDLE"
    ContainerBFS.pendingOpen = nil

    if prevState == "IDLE" then return end

    if config.autoMinimize then
        schedule(100, function()
            for _, c in pairs(g_game.getContainers()) do
                applyMinimize(c)
            end
        end)
    end

    if config.renameEnabled then
        schedule(150, function()
            for _, c in pairs(g_game.getContainers()) do
                applyRename(c)
            end
        end)
    end

    local cb = ContainerBFS.onCompleteCallback
    ContainerBFS.onCompleteCallback = nil
    if cb then schedule(50, cb) end

    if EventBus and EventBus.emit then
        EventBus.emit("containers:open_all_complete")
    end
end

function ContainerBFS.start(onComplete)
    ContainerBFS.reset()
    ContainerBFS.onCompleteCallback = onComplete
    requestContainerSync()

    for _, c in pairs(g_game.getContainers()) do
        if hasEnhancedAPIs() then refreshContainer(c) end
        ContainerBFS.scanContainer(c)
    end

    if #ContainerBFS.queue > 0 then
        ContainerBFS.state = "RUNNING"
        ContainerBFS.openNext()
    else
        ContainerBFS.state = "IDLE"
        if onComplete then schedule(50, onComplete) end
        if EventBus and EventBus.emit then
            EventBus.emit("containers:open_all_complete")
        end
    end
end

function ContainerBFS.stop()
    ContainerBFS.state = "IDLE"
    ContainerBFS.pendingOpen = nil
end


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


local function isLootLocked()
    return TargetBot and TargetBot.Looting and TargetBot.Looting.isActive and TargetBot.Looting.isActive()
end

onContainerOpen(function(container, previousContainer)
    if not container then return end

    ContainerBFS.onContainerOpened(container)

    applyMinimize(container)
    applyRename(container)

    if sortingMacro and not isLootLocked() then sortingMacro:setOn() end

    -- When BFS is opening main backpack, try quiver once backpack is confirmed open
    if ContainerBFS.isActive() and ContainerBFS.state == "OPENING_MAIN" then
        if not isQuiverOpen() then
            schedule(100, function() openQuiverWithRetry(3) end)
        end
    end

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
    if ContainerBFS.state == "PAUSED" then
        ContainerBFS.state = "RUNNING"
        schedule(50, function() ContainerBFS.openNext() end)
    end

    if container and not container.lootContainer and not isLootLocked() then
        if sortingMacro and (config.sortEnabled or config.forceOpen) then
            sortingMacro:setOn()
        end
    end
end)

onAddItem(function(container, slot, item, oldItem)
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


function reopenBackpacks(onComplete)
    if EventBus and EventBus.emit then
        EventBus.emit("containers:close_all")
    end

    for _, container in pairs(g_game.getContainers()) do
        g_game.close(container)
    end

    schedule(300, function()
        local bpItem = getBack()
        if not bpItem then
            warn("[Container Panel] No backpack in back slot!")
            if onComplete then onComplete() end
            return
        end
        g_game.open(bpItem)

        if config.purse then
            schedule(300, function()
                local purseItem = getPurse()
                if purseItem then use(purseItem) end
            end)
        end

        schedule(600, function() openQuiverWithRetry(5) end)

        ContainerBFS.reset()
        ContainerBFS.state = "OPENING_MAIN"
        ContainerBFS.onCompleteCallback = onComplete
        local pending = {}
        ContainerBFS.pendingOpen = pending
        schedulePendingTimeout(pending, "OPENING_MAIN", function()
            ContainerBFS.finish()
        end)
    end)
end


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
    if healthPercent == 0 then
        hasTriggeredThisSession = false
        lastKnownHealth = 0
        return
    end
    if not config.autoOpenOnLogin then return end
    if lastKnownHealth == 0 and healthPercent > 0 and not hasTriggeredThisSession then
        hasTriggeredThisSession = true
        triggerAutoOpen()
    end
    lastKnownHealth = healthPercent
end)

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

local cachedContainers = nil
local function getCachedContainers()
    if not cachedContainers then cachedContainers = g_game.getContainers() end
    return cachedContainers
end

local function isContainerOpen(itemId)
    if not itemId then return false end
    for _, container in pairs(getCachedContainers()) do
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

    for _, container in pairs(getCachedContainers()) do
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


sortingMacro = macro(300, function(m)
    cachedContainers = nil  -- reset per-tick cache

    if not config.sortEnabled and not config.forceOpen then
        m:setOff()
        cachedContainers = nil
        return
    end

    if ContainerBFS.isActive() then
        cachedContainers = nil
        return
    end

    if isLootLocked() then
        cachedContainers = nil
        return
    end

    if config.sortEnabled then
        for _, container in pairs(getCachedContainers()) do
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

    m:setOff()
    cachedContainers = nil
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Discovery Service Bridge
-- Wires the modular core/containers/discovery.lua into the legacy Containers.lua
-- lifecycle events and native container callbacks.
-- ─────────────────────────────────────────────────────────────────────────────
do
  local ok, Discovery = pcall(dofile, "core/containers/discovery.lua")
  if not ok then
    warn("[nExBot/Containers] Failed to load discovery module: " .. tostring(Discovery))
    Discovery = nil
  end

  if Discovery then
    -- Singleton discovery instance exposed globally for diagnostics.
    nExBot.ContainerDiscovery = Discovery.new()
    local disc = nExBot.ContainerDiscovery

    -- Sync configuration from legacy config into the new discovery instance.
    disc:setConfig({
      autoOpen                 = config.autoOpenOnLogin or false,
      pauseTargetBotOnRecovery = true,
      pauseCaveBotOnRecovery   = true,
    })

    -- Forward game lifecycle events.
    if EventBus then
      EventBus.on("player:login", function()
        disc:setConfig({ autoOpen = config.autoOpenOnLogin or false })
        disc:onGameStart()
      end, 100)

      EventBus.on("player:logout", function()
        disc:onGameEnd()
      end, 100)
    end

    -- Hook into native container-open callback.
    onContainerOpen(function(container, previousContainer)
      if not container then return end

      -- Build event from the opened container.
      local itemType = 0
      local ci = container.getContainerItem and container:getContainerItem()
      if ci then pcall(function() itemType = ci:getId() end) end

      local items = {}
      pcall(function() items = container:getItems() or {} end)

      disc:onContainerOpened({
        containerId = container:getId(),
        itemType    = itemType,
        items       = items,
        itemCount   = #items,
      })

      -- Also fire item indexing.
      disc:onContainerItems({
        identity    = disc.bfs.inFlight and disc.bfs.inFlight.identity or ("open:" .. tostring(container:getId())),
        containerId = container:getId(),
        items       = items,
        pageIndex   = 0,
      })
    end)

    -- Expose readiness check for other modules.
    nExBot.isContainerReady = function(level)
      return disc:isReadyFor(level or "COMBAT_READY")
    end

    nExBot.getContainerReadiness = function()
      return disc:getReadiness()
    end

    nExBot.getContainerMetrics = function()
      return disc:getMetrics()
    end
  end
end
