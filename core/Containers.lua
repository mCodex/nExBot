
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
    windowHeight = 260
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

local function getContainerWindow(container)
    if container.window then return container.window end
    local containerId = container:getId()
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

local function applyRename(container)
    local item = container:getContainerItem()
    local rule = config.renameEnabled and item and getContainerConfig(item:getId())
    if not rule and not container.nexBotOriginalTitle then return end

    local window = getContainerWindow(container)
    if not window then return end
    local title = window:getChildById("miniwindowTitle") or window
    if rule and rule.name and rule.name ~= "" then
        container.nexBotOriginalTitle = container.nexBotOriginalTitle or title:getText()
        title:setText(rule.name)
    elseif container.nexBotOriginalTitle then
        title:setText(container.nexBotOriginalTitle)
        container.nexBotOriginalTitle = nil
    end
end

local function refreshOpenTitles()
    for _, container in pairs(g_game.getContainers()) do
        applyRename(container)
    end
end

local function isLootLocked()
    return TargetBot and TargetBot.Looting and TargetBot.Looting.isActive and TargetBot.Looting.isActive()
end

local setupWindow
-- The bot executor's dofile discards module return values.
local function loadContainerModule(name, ...)
    local path = nExBot.paths.core .. "/containers/" .. name .. ".lua"
    return assert(load(g_resources.readFileContents(path), path))(...)
end
local Reopen = loadContainerModule("reopen", loadContainerModule("queue"))

local syncUIWithConfig
local refreshContainerList

UI.Separator()
local containerUI = UI.createWidget("NexBotContainerPanel")
containerUI:setId(panelName)

containerUI.openAll:setTooltip("When enabled, automatically opens all containers on re-login\n(Toggle ON to enable auto-open on each login)")
containerUI.setupBtn:setTooltip("Configure container names, sorting rules, and behavior")
containerUI.reopenAll:setTooltip("Reopen all equipped containers and their nested bags")
containerUI.closeAll:setTooltip("Close all open containers")
containerUI.minimizeAll:setTooltip("Minimize all container windows")
containerUI.maximizeAll:setTooltip("Maximize all container windows")
containerUI.purseSwitch:setTooltip("Also open the purse when reopening")
containerUI.autoMinSwitch:setTooltip("Automatically minimize containers after opening")

syncUIWithConfig = function()
    if containerUI then
        containerUI.openAll:setChecked(config.autoOpenOnLogin == true)
        containerUI.purseSwitch:setChecked(config.purse == true)
        containerUI.autoMinSwitch:setChecked(config.autoMinimize ~= false)
        refreshOpenTitles()
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
        label.caption:setText(entry.name or "Container")
        label:setTooltip(label.caption:getText())
        label.enabled:setChecked(entry.enabled)
        
        label.minimize:setColor(entry.minimize and '#00FF00' or '#FF6666')
        label.minimize:setTooltip(entry.minimize and 'Opens Minimized' or 'Opens Normal')
        
        label.nested:setColor(entry.openNested and '#00FF00' or '#FF6666')
        label.nested:setTooltip(entry.openNested and 'Prioritize nested bags during Reopen All' or 'Use normal order during Reopen All')
        
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
            refreshOpenTitles()
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
                        local window = getContainerWindow(container)
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
            label.nested:setTooltip(entry.openNested and 'Prioritize nested bags during Reopen All' or 'Use normal order during Reopen All')
            saveConfig()  -- Persist to CharacterDB
        end
        
        label.remove.onClick = function()
            table.remove(config.containerList, index)
            refreshOpenTitles()
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
    
    setupWindow:setHeight(math.max(240, tonumber(config.windowHeight) or 260))
    setupWindow.onGeometryChange = function(widget)
        local height = widget:getHeight()
        if height >= 240 and height ~= config.windowHeight then
            config.windowHeight = height
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
        refreshOpenTitles()
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
        
        selectedContainerIndex = nil
        refreshOpenTitles()
        setupWindow.containerId:setItemId(0)
        setupWindow.containerName:setText("")
        setupWindow.itemsList:setItems({})
        
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

local function applyMinimize(container)
    if not container then return end
    local containerItem = container:getContainerItem()
    local itemId = containerItem and containerItem:getId() or 0
    local entry = getContainerConfig(itemId)
    local shouldMinimize = (entry and entry.minimize) or config.autoMinimize
    if shouldMinimize then
        schedule(50, function()
            minimizeWindow(getContainerWindow(container))
        end)
    end
end

local function equippedRoots()
    local getters = {getHead, getNeck, getBack, getBody, getRight, getLeft, getLeg, getFeet, getFinger, getAmmo, getPurse}
    local function itemAt(slot)
        if slot == 11 and not nExBot.isOpenTibiaBR then return getPurse and getPurse() end
        local player = g_game.getLocalPlayer()
        if player and player.getInventoryItem then
            local item = player:getInventoryItem(slot)
            if item then return item end
        end
        local getter = getters[slot]
        return getter and getter()
    end

    local roots = {}
    local function add(slot, purse)
        local item = itemAt(slot)
        if not item or not item:isContainer() then return end
        roots[#roots + 1] = {purse = purse, root = function()
            local current = itemAt(slot)
            if current and current:isContainer() then return current end
        end}
    end

    add(3)
    if config.purse then add(11, true) end
    -- The OpenTibiaBR inventory has four extension slots after the purse.
    local last = nExBot.isOpenTibiaBR and 15 or 10
    for slot = 1, last do
        if slot ~= 3 and slot ~= 11 then add(slot) end
    end
    return roots
end

local function excludeNested(name, purse)
    if purse then return false end
    name = (name or ""):lower()
    if name:match("backpack$") or name:match("%f[%a]bag$") then return false end
    return isExcludedContainer(name)
end

local function getNow()
    if now then return now end
    if g_clock and g_clock.millis then return g_clock.millis() end
    return os.time() * 1000
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

onContainerOpen(function(container, previousContainer)
    if not container then return end

    Reopen.onOpen(container, previousContainer)

    applyMinimize(container)
    if config.renameEnabled then
        local id = container:getId()
        schedule(60, function()
            local current = g_game.getContainer(id)
            if current then applyRename(current) end
        end)
    end

    if sortingMacro and not isLootLocked() then sortingMacro:setOn() end

end)

onContainerClose(function(container)
    if container then Reopen.onClose(container) end

    if container and not container.lootContainer and not isLootLocked() then
        if sortingMacro and (config.sortEnabled or config.forceOpen) then
            sortingMacro:setOn()
        end
    end
end)

onAddItem(function(container, slot, item, oldItem)
    if container and slot and item then Reopen.onAdd(container, item, slot) end

    if sortingMacro and (config.sortEnabled or config.forceOpen) and not isLootLocked() then
        sortingMacro:setOn()
    end
end)

if onContainerUpdateItem then
    onContainerUpdateItem(function(container, slot, item, oldItem)
        if container and slot and item then Reopen.onUpdate(container, item, slot, oldItem) end
    end)
end

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
    local roots = {}
    if not Reopen.isActive() then
        roots = equippedRoots()
        if #roots == 0 then
            warn("[Container Panel] No equipped containers to reopen.")
            if onComplete then onComplete(false) end
            return
        end
    end
    Reopen.start(roots, excludeNested, getContainerConfig, onComplete)
end


containerUI.openAll.onClick = function(widget)
    config.autoOpenOnLogin = not config.autoOpenOnLogin
    widget:setChecked(config.autoOpenOnLogin)
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
    Reopen.cancel()
    for _, container in pairs(g_game.getContainers()) do
        g_game.close(container)
    end
end

containerUI.minimizeAll.onClick = function(widget)
    for _, container in pairs(g_game.getContainers()) do
        minimizeWindow(getContainerWindow(container))
    end
end

containerUI.maximizeAll.onClick = function(widget)
    for _, container in pairs(g_game.getContainers()) do
        maximizeWindow(getContainerWindow(container))
    end
end

containerUI.purseSwitch.onClick = function(widget)
    config.purse = not config.purse
    widget:setChecked(config.purse)
    saveConfig()
end

containerUI.autoMinSwitch.onClick = function(widget)
    config.autoMinimize = not config.autoMinimize
    widget:setChecked(config.autoMinimize)
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

local function indexSortingRules()
    local rules = {}
    for _, entry in ipairs(config.containerList) do
        if entry.enabled and entry.items then
            for _, id in ipairs(extractItemIds(entry.items)) do
                if not rules[id] then rules[id] = entry.itemId end
            end
        end
    end
    return rules
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

    if Reopen.isActive() then
        cachedContainers = nil
        return
    end

    if isLootLocked() then
        cachedContainers = nil
        return
    end

    if config.sortEnabled then
        local rules = indexSortingRules()
        local destinations = {}
        for _, container in pairs(getCachedContainers()) do
            local containerName = container:getName()
            if not isExcludedContainer(containerName) then
                local containerItemId = container:getContainerItem():getId()
                for _, item in ipairs(container:getItems()) do
                    local itemId = item:getId()
                    local bagId = rules[itemId]
                    if bagId and destinations[bagId] == nil then
                        destinations[bagId] = (getContainerByItem and getContainerByItem(bagId, true)) or false
                    end
                    local destination = bagId and destinations[bagId]
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
