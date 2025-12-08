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
        autoMinimize = true,
        autoOpenOnLogin = false
    }
end

local config = storage[panelName]
-- Ensure new config options exist for old configs
if config.autoOpenOnLogin == nil then
    config.autoOpenOnLogin = false
end

UI.Separator()
local containerUI = setupUI([[
Panel
  height: 122

  Label
    text-align: center
    text: Container Panel
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    font: verdana-11px-rounded

  BotSwitch
    id: openAll
    !text: tr('Auto Open Containers')
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 3
    text-align: center
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
containerUI.reopenAll:setTooltip("Close all containers and reopen from back slot")
containerUI.closeAll:setTooltip("Close all open containers")
containerUI.minimizeAll:setTooltip("Minimize all container windows")
containerUI.maximizeAll:setTooltip("Maximize all container windows")
containerUI.purseSwitch:setTooltip("Also open the purse when reopening")
containerUI.autoMinSwitch:setTooltip("Automatically minimize containers after opening")

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
-- STATE
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
-- HELPER FUNCTIONS
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
    
    local gameContainers = modules.game_containers
    if gameContainers and gameContainers.getContainerWindow then
        local window = gameContainers.getContainerWindow(container:getId())
        if window and window.minimize then
            window:minimize()
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
    
    -- Auto-minimize during processing
    if isProcessing and config.autoMinimize then
        schedule(50, function()
            minimizeContainer(container)
        end)
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
    if config.autoOpenOnLogin then
        info("[Container Panel] Auto-open on login: ENABLED")
    else
        info("[Container Panel] Auto-open on login: DISABLED")
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
            info("[Container Panel] Auto-opening containers on login...")
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
