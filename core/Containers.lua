--[[
  Container Panel - Simplified BFS Deep Search
  
  Features:
  - Open BPs: Opens all nested containers using BFS
  - Reopen: Closes all and reopens from back slot
  - Close: Closes all open containers
  - Min: Minimizes all open containers  
  - Max: Maximizes all open containers
  
  All operations use BFS (Breadth-First Search) to find nested containers.
]]

setDefaultTab("Tools")
local panelName = "containerPanel"

-- Simple config - just purse setting
if type(storage[panelName]) ~= "table" then
    storage[panelName] = {
        purse = true
    }
end

local config = storage[panelName]

UI.Separator()
local containerUI = setupUI([[
Panel
  height: 55

  Label
    text-align: center
    text: Container Panel
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    font: verdana-11px-rounded

  Button
    id: openBPs
    !text: tr('Open BPs')
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 3
    width: 60
    height: 17
    tooltip: Open all nested backpacks (BFS deep search)
    font: verdana-11px-rounded

  Button
    id: reopenAll
    !text: tr('Reopen')
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 2
    width: 50
    height: 17
    tooltip: Close and reopen all backpacks from back slot
    font: verdana-11px-rounded

  Button
    id: closeAll
    !text: tr('Close')
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 2
    width: 40
    height: 17
    tooltip: Close all containers
    font: verdana-11px-rounded

  Button
    id: minimizeAll
    !text: tr('Min')
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 2
    width: 30
    height: 17
    tooltip: Minimize all containers
    font: verdana-11px-rounded

  Button
    id: maximizeAll
    !text: tr('Max')
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 2
    width: 30
    height: 17
    tooltip: Maximize all containers
    font: verdana-11px-rounded

  BotSwitch
    id: purseSwitch
    anchors.top: openBPs.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    text-align: center
    !text: tr('Open Purse on Reopen')
    tooltip: Also open the purse when reopening backpacks
    font: verdana-11px-rounded
  ]])
containerUI:setId(panelName)

--[[
  Container Opening System - BFS (Breadth-First Search)
  
  Algorithm:
  1. Track containers by their slot index
  2. Open containers one at a time with proper delays
  3. After each open, rescan for new nested containers
  4. Opens each container in a NEW window (not cascading)
]]

-- Container opening state
local isProcessingQueue = false
local processedContainerSlots = {}
local containersToOpen = {}
local lastOpenTime = 0
local OPEN_DELAY = 350 -- ms between container opens

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
        info("[Container Panel] BFS Complete - All containers opened")
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
    
    info("[Container Panel] Starting BFS Deep Search...")
    schedule(200, processContainerQueue)
end

-- Hook into container open events to continue BFS
onContainerOpen(function(container, previousContainer)
    if not container then return end
    
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
containerUI.openBPs.onClick = function(widget)
    info("[Container Panel] Opening all nested backpacks...")
    startContainerBFS()
end

containerUI.reopenAll.onClick = function(widget)
    info("[Container Panel] Reopening all backpacks...")
    reopenBackpacks()
end

containerUI.closeAll.onClick = function(widget)
    info("[Container Panel] Closing all containers...")
    for _, container in pairs(g_game.getContainers()) do
        g_game.close(container)
    end
end

containerUI.minimizeAll.onClick = function(widget)
    for _, container in pairs(g_game.getContainers()) do
        if container.window then
            container.window:minimize()
        end
    end
end

containerUI.maximizeAll.onClick = function(widget)
    for _, container in pairs(g_game.getContainers()) do
        if container.window then
            container.window:maximize()
        end
    end
end

-- Purse switch
containerUI.purseSwitch:setOn(config.purse)
containerUI.purseSwitch.onClick = function(widget)
    config.purse = not config.purse
    widget:setOn(config.purse)
end
