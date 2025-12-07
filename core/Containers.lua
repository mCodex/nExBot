--[[
  Container Panel - Simplified BFS Deep Search
  
  Features:
  - Open All: Opens main BP + all nested containers (auto-minimized)
  - Reopen: Closes all and reopens from back slot
  - Close All: Closes all open containers
  - Min/Max: Minimizes/Maximizes all containers
  
  All operations use BFS (Breadth-First Search) to find nested containers.
  Containers are auto-minimized after opening for cleaner UI.
]]

setDefaultTab("Tools")
local panelName = "containerPanel"

-- Config storage
if type(storage[panelName]) ~= "table" then
    storage[panelName] = {
        purse = true,
        autoMinimize = true
    }
end

local config = storage[panelName]

UI.Separator()
local containerUI = setupUI([[
Panel
  height: 150

  Label
    text-align: center
    text: Container Panel
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    font: verdana-11px-rounded

  Button
    id: openAll
    !text: tr('Open All Containers')
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
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
containerUI.openAll:setTooltip("Open main backpack and all nested containers\n(Auto-minimizes if enabled)")
containerUI.reopenAll:setTooltip("Close all containers and reopen from back slot")
containerUI.closeAll:setTooltip("Close all open containers")
containerUI.minimizeAll:setTooltip("Minimize all container windows")
containerUI.maximizeAll:setTooltip("Maximize all container windows")
containerUI.purseSwitch:setTooltip("Also open the purse when reopening")
containerUI.autoMinSwitch:setTooltip("Automatically minimize containers after opening")

--[[
  Container Opening System - BFS (Breadth-First Search)
  
  Algorithm:
  1. Open main backpack from back slot first
  2. Track containers by their slot index
  3. Open containers one at a time with proper delays
  4. After each open, rescan for new nested containers
  5. Opens each container in a NEW window (not cascading)
  6. Auto-minimize each container after opening (if enabled)
]]

-- Container opening state
local isProcessingQueue = false
local processedContainerSlots = {}
local containersToOpen = {}
local lastOpenTime = 0
local OPEN_DELAY = 350 -- ms between container opens

-- Minimize a container window using OTClient API
local function minimizeContainer(container)
    if not config.autoMinimize then return end
    if not container then return end
    
    -- OTClient stores container windows with getContainerWindow or getWindow
    local containerWindow = nil
    
    -- Try different methods to get the container window
    if container.getWindow then
        containerWindow = container:getWindow()
    elseif container.window then
        containerWindow = container.window
    end
    
    -- If we have a window, minimize it
    if containerWindow then
        if containerWindow.minimize then
            containerWindow:minimize()
        elseif containerWindow.setHeight then
            -- Alternative: collapse to header only
            containerWindow:setHeight(20)
        end
    else
        -- Fallback: find window by container index in UI
        local containers = modules.game_containers
        if containers then
            local window = containers.getContainerWindow(container:getId())
            if window and window.minimize then
                window:minimize()
            end
        end
    end
end

-- Scan all open containers for nested containers we haven't opened yet
local function scanForNestedContainers()
    local found = {}
    local containers = g_game.getContainers()
    
    for containerIndex, container in pairs(containers) do
        local items = container:getItems()
        for itemIndex, item in ipairs(items) do
            if item and item:isContainer() then
                local slotKey = containerIndex .. "_" .. itemIndex
                if not processedContainerSlots[slotKey] then
                    processedContainerSlots[slotKey] = true
                    table.insert(found, {
                        item = item,
                        containerIndex = containerIndex,
                        itemIndex = itemIndex
                    })
                end
            end
        end
    end
    
    return found
end

-- Process the container opening queue
local function processContainerQueue()
    if not isProcessingQueue then return end
    
    -- Scan for new containers to open
    local newContainers = scanForNestedContainers()
    for _, entry in ipairs(newContainers) do
        table.insert(containersToOpen, entry)
    end
    
    -- Check if we have anything to open
    if #containersToOpen == 0 then
        isProcessingQueue = false
        -- Final minimize pass for all containers
        if config.autoMinimize then
            for _, container in pairs(g_game.getContainers()) do
                minimizeContainer(container)
            end
        end
        return
    end
    
    -- Cooldown check
    if (now - lastOpenTime) < OPEN_DELAY then
        schedule(OPEN_DELAY - (now - lastOpenTime) + 50, processContainerQueue)
        return
    end
    
    -- Get next container to open
    local entry = table.remove(containersToOpen, 1)
    if not entry or not entry.item then
        schedule(100, processContainerQueue)
        return
    end
    
    -- Verify the item is still valid and is a container
    local item = entry.item
    if not item or not item:isContainer() then
        schedule(100, processContainerQueue)
        return
    end
    
    lastOpenTime = now
    
    -- Open the container in a NEW WINDOW
    g_game.open(item, nil)
    
    -- Continue processing after delay
    schedule(OPEN_DELAY + 100, processContainerQueue)
end

-- Start the BFS container opening process
local function startContainerBFS()
    containersToOpen = {}
    processedContainerSlots = {}
    isProcessingQueue = true
    lastOpenTime = 0
    
    schedule(200, processContainerQueue)
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
            end)
        else
            warn("[Container Panel] No backpack in back slot!")
        end
    else
        -- Main backpack already open, start BFS directly
        startContainerBFS()
    end
end

-- Hook into container open events to continue BFS and auto-minimize
onContainerOpen(function(container, previousContainer)
    if not container then return end
    
    -- Auto-minimize new containers during BFS
    if isProcessingQueue and config.autoMinimize then
        schedule(100, function()
            minimizeContainer(container)
        end)
    end
    
    -- If BFS is active, trigger rescan
    if isProcessingQueue then
        schedule(150, processContainerQueue)
    end
end)

-- Reopen all backpacks from back slot
function reopenBackpacks()
    -- Close all containers first
    for _, container in pairs(g_game.getContainers()) do 
        g_game.close(container) 
    end
    
    -- Open main backpack from back slot
    local bpItem = getBack()
    if bpItem then
        g_game.open(bpItem)
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
    
    -- Start BFS after a small delay to let main backpack open
    schedule(600, function()
        startContainerBFS()
    end)
end

-- Button handlers
containerUI.openAll.onClick = function(widget)
    openAllContainers()
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
    local containers = modules.game_containers
    if containers and containers.getContainerWindow then
        for _, container in pairs(g_game.getContainers()) do
            local window = containers.getContainerWindow(container:getId())
            if window and window.minimize then
                window:minimize()
            end
        end
    else
        -- Fallback
        for _, container in pairs(g_game.getContainers()) do
            if container.window and container.window.minimize then
                container.window:minimize()
            end
        end
    end
end

containerUI.maximizeAll.onClick = function(widget)
    local containers = modules.game_containers
    if containers and containers.getContainerWindow then
        for _, container in pairs(g_game.getContainers()) do
            local window = containers.getContainerWindow(container:getId())
            if window and window.maximize then
                window:maximize()
            end
        end
    else
        -- Fallback
        for _, container in pairs(g_game.getContainers()) do
            if container.window and container.window.maximize then
                container.window:maximize()
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
