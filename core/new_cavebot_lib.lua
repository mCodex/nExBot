CaveBot = {} -- global namespace

-------------------------------------------------------------------
-- CaveBot lib 1.0 - Optimized version
-- Contains a universal set of functions to be used in CaveBot

----------------------[[ basic assumption ]]-----------------------
-- in general, functions cannot be slowed from within, only externally, by event calls, delays etc.
-- considering that and the fact that there is no while loop, every function return action
-- thus, functions will need to be verified outside themselfs or by another function
-- overall tips to creating extension:
--   - functions return action(nil) or true(done)
--   - extensions are controlled by retries var
-------------------------------------------------------------------

-- Pre-built lookup tables for O(1) access
local LOCKERS_LIST = {3497, 3498, 3499, 3500}
local LOCKERS_SET = { [3497] = true, [3498] = true, [3499] = true, [3500] = true }
local LOCKER_ACCESSTILE_MODIFIERS = {
    [3497] = {0,-1},
    [3498] = {1,0},
    [3499] = {0,1},
    [3500] = {-1,0}
}

-- Cache for config parsing to avoid repeated file reads
local configCache = {
    data = nil,
    name = nil,
    lastParse = 0
}
local CONFIG_CACHE_TTL = 5000  -- 5 seconds

local function CaveBotConfigParse()
    local configs = storage["_configs"]
    if not configs or not configs["targetbot_configs"] then
        return nil
    end
    
    local name = configs["targetbot_configs"]["selected"]
    if not name then 
        return warn("[nExBot] Please create a new TargetBot config and reset bot")
    end
    
    -- Use cache if valid
    if configCache.name == name and now - configCache.lastParse < CONFIG_CACHE_TTL then
        return configCache.data
    end
    
    local file = configDir .. "/targetbot_configs/" .. name .. ".json"
    local data = g_resources.readFileContents(file)
    local parsed = Config.parse(data)
    
    if parsed then
        configCache.data = parsed['looting']
        configCache.name = name
        configCache.lastParse = now
        return configCache.data
    end
    
    return nil
end

-- Pre-computed direction offsets (same as vlib but local for this module)
local NEAR_DIRS = {
    {-1, 1}, {0, 1}, {1, 1}, {-1, 0}, {1, 0}, {-1, -1}, {0, -1}, {1, -1}
}
local NEAR_DIRS_COUNT = 8
local nearTilePos = { x = 0, y = 0, z = 0 }

local function getNearTiles(pos)
    if type(pos) ~= "table" then
        pos = pos:getPosition()
    end

    local tiles = {}
    local tileCount = 0
    local baseX, baseY, baseZ = pos.x, pos.y, pos.z
    
    for i = 1, NEAR_DIRS_COUNT do
        local dir = NEAR_DIRS[i]
        nearTilePos.x = baseX - dir[1]
        nearTilePos.y = baseY - dir[2]
        nearTilePos.z = baseZ
        
        local tile = g_map.getTile(nearTilePos)
        if tile then
            tileCount = tileCount + 1
            tiles[tileCount] = tile
        end
    end

    return tiles
end

-- ##################### --
-- [[ Information class ]] --
-- ##################### --

--- global variable to reflect current CaveBot status
CaveBot.Status = "waiting"

-- Cache for loot items to avoid repeated parsing
local lootItemsCache = nil
local lootItemsCacheTime = 0
local LOOT_CACHE_TTL = 3000

--- Parses config and extracts loot list.
-- @return table
function CaveBot.GetLootItems()
    -- Use cache if valid
    if lootItemsCache and now - lootItemsCacheTime < LOOT_CACHE_TTL then
        return lootItemsCache
    end
    
    local t = CaveBotConfigParse()
    local items = t and t["items"] or nil

    local returnTable = {}
    local count = 0
    if type(items) == "table" then
        for i, item in pairs(items) do
            count = count + 1
            returnTable[count] = item["id"]
        end
    end
    
    lootItemsCache = returnTable
    lootItemsCacheTime = now

    return returnTable
end

-- Pre-built lookup set for O(1) loot item check
local lootItemsSet = nil
local lootItemsSetTime = 0

local function getLootItemsSet()
    if lootItemsSet and now - lootItemsSetTime < LOOT_CACHE_TTL then
        return lootItemsSet
    end
    
    lootItemsSet = {}
    for _, id in ipairs(CaveBot.GetLootItems()) do
        lootItemsSet[id] = true
    end
    lootItemsSetTime = now
    return lootItemsSet
end

--- Checks whether player has any visible items to be stashed
-- @return boolean
function CaveBot.HasLootItems()
    local lootSet = getLootItemsSet()
    if not next(lootSet) then return false end
    
    for _, container in pairs(getContainers()) do
        local name = container:getName():lower()
        -- Use plain string find for speed
        if not name:find("depot", 1, true) and not name:find("your inbox", 1, true) then
            local items = container:getItems()
            for i = 1, #items do
                local id = items[i]:getId()
                if lootSet[id] then
                    return true
                end
            end
        end
    end
end

--- Parses config and extracts loot containers.
-- @return table
-- Cache for loot containers
local lootContainersCache = nil
local lootContainersCacheTime = 0

function CaveBot.GetLootContainers()
    -- Use cache if valid
    if lootContainersCache and now - lootContainersCacheTime < LOOT_CACHE_TTL then
        return lootContainersCache
    end
    
    local t = CaveBotConfigParse()
    local containers = t and t["containers"] or nil

    local returnTable = {}
    local count = 0
    if type(containers) == "table" then
        for i, container in pairs(containers) do
            count = count + 1
            returnTable[count] = container["id"]
        end
    end
    
    lootContainersCache = returnTable
    lootContainersCacheTime = now

    return returnTable
end

-- Pre-built lookup set for O(1) container check
local lootContainersSet = nil
local lootContainersSetTime = 0

local function getLootContainersSet()
    if lootContainersSet and now - lootContainersSetTime < LOOT_CACHE_TTL then
        return lootContainersSet
    end
    
    lootContainersSet = {}
    for _, id in ipairs(CaveBot.GetLootContainers()) do
        lootContainersSet[id] = true
    end
    lootContainersSetTime = now
    return lootContainersSet
end

--- Information about open containers.
-- @param amount is boolean
-- @return table or integer
function CaveBot.GetOpenedLootContainers(containerTable)
    local containersSet = getLootContainersSet()

    local t = {}
    local count = 0
    for i, container in pairs(getContainers()) do
        local containerId = container:getContainerItem():getId()
        if containersSet[containerId] then
            count = count + 1
            t[count] = container
        end
    end

    return containerTable and t or count
end

--- Some actions needs to be additionally slowed down in case of high ping.
-- Maximum at 2000ms in case of lag spike.
-- @param multiplayer is integer
-- @return void
function CaveBot.PingDelay(multiplayer)
    multiplayer = multiplayer or 1
    local currentPing = ping()
    if currentPing and currentPing > 150 then
        local value = math.min(currentPing * multiplayer, 2000)
        return delay(value)
    end
end

-- ##################### --
-- [[ Container class ]] --
-- ##################### --

--- Closes any loot container that is open.
-- @return void or boolean
function CaveBot.CloseLootContainer()
    local containers = CaveBot.GetLootContainers()

    for i, container in pairs(getContainers()) do
        local containerId = container:getContainerItem():getId()
        if table.find(containers, containerId) then
            return g_game.close(container)
        end
    end

    return true
end

function CaveBot.CloseAllLootContainers()
    local containers = CaveBot.GetLootContainers()

    for i, container in pairs(getContainers()) do
        local containerId = container:getContainerItem():getId()
        if table.find(containers, containerId) then
            g_game.close(container)
        end
    end

    return true
end

--- Opens any loot container that isn't already opened.
-- @return void or boolean
function CaveBot.OpenLootContainer()
    local containers = CaveBot.GetLootContainers()

    local t = {}
    for i, container in pairs(getContainers()) do
        local containerId = container:getContainerItem():getId()
        table.insert(t, containerId)
    end

    for _, container in pairs(getContainers()) do
        for _, item in pairs(container:getItems()) do
            local id = item:getId()
            if table.find(containers, id) and not table.find(t, id) then
                return g_game.open(item)
            end
        end
    end

    return true
end

-- ##################### --
-- [[[ Position class ]] --
-- ##################### --

--- Compares distance between player position and given pos.
-- @param position is table
-- @param distance is integer
-- @return boolean
function CaveBot.MatchPosition(position, distance)
    local pPos = player:getPosition()
    distance = distance or 1
    return getDistanceBetween(pPos, position) <= distance
end

--- Stripped down to take less space.
-- Use only to safe position, like pz movement or reaching npc.
-- Needs to be called between 200-500ms to achieve fluid movement.
-- @param position is table
-- @param distance is integer
-- @return void
function CaveBot.GoTo(position, precision)
    if not precision then
        precision = 3
    end
    return CaveBot.walkTo(position, 20, {ignoreCreatures = true, precision = precision})
end

--- Finds position of npc by name and reaches its position.
-- @return void(acion) or boolean
function CaveBot.ReachNPC(name)
    name = name:lower()
    
    local npc = nil
    for i, spec in pairs(SafeCall.global("getSpectators") or {}) do
        if spec:isNpc() and spec:getName():lower() == name then
            npc = spec
        end
    end

    if not CaveBot.MatchPosition(npc:getPosition(), 3) then
        CaveBot.GoTo(npc:getPosition())
    else
        return true
    end
end

-- ##################### --
-- [[[[ Depot class ]]]] --
-- ##################### --

--- Reaches closest locker.
-- @return void(acion) or boolean

local depositerLockerTarget = nil
local depositerLockerReachRetries = 0
function CaveBot.ReachDepot()
    local pPos = player:getPosition()
    local tiles = getNearTiles(player:getPosition())

    for i, tile in pairs(tiles) do
        for i, item in pairs(tile:getItems()) do
            if table.find(LOCKERS_LIST, item:getId()) then
                depositerLockerTarget = nil
                depositerLockerReachRetries = 0
                return true -- if near locker already then return function
            end
        end
    end

    if depositerLockerReachRetries > 20 then
        depositerLockerTarget = nil
        depositerLockerReachRetries = 0
    end

    local candidates = {}

    if not depositerLockerTarget or distanceFromPlayer(depositerLockerTarget, pPos) > 12 then
        for i, tile in pairs(g_map.getTiles(posz())) do
            local tPos = tile:getPosition()
            for i, item in pairs(tile:getItems()) do
                if table.find(LOCKERS_LIST, item:getId()) then
                    local lockerTilePos = tile:getPosition()
                          lockerTilePos.x = lockerTilePos.x + LOCKER_ACCESSTILE_MODIFIERS[item:getId()][1]
                          lockerTilePos.y = lockerTilePos.y + LOCKER_ACCESSTILE_MODIFIERS[item:getId()][2]
                    local lockerTile = g_map.getTile(lockerTilePos)
                    local hasCreature = lockerTile and lockerTile.hasCreature and lockerTile:hasCreature()
                    if lockerTile and not hasCreature then
                        if findPath(pos(), tPos, 20, {ignoreNonPathable = false, precision = 1, ignoreCreatures = true}) then
                            local distance = getDistanceBetween(tPos, pPos)
                            table.insert(candidates, {pos=tPos, dist=distance})
                        end
                    end
                end
            end
        end

        if #candidates > 1 then
            table.sort(candidates, function(a,b) return a.dist < b.dist end)
        end
    end

    depositerLockerTarget = depositerLockerTarget or candidates[1].pos

    if depositerLockerTarget then
        if not CaveBot.MatchPosition(depositerLockerTarget) then
            depositerLockerReachRetries = depositerLockerReachRetries + 1
            return CaveBot.GoTo(depositerLockerTarget, 1)
        else
            depositerLockerReachRetries = 0
            depositerLockerTarget = nil
            return true
        end
    end
end

--- Opens locker item.
-- @return void(acion) or boolean
function CaveBot.OpenLocker()
    local pPos = player:getPosition()
    local tiles = getNearTiles(player:getPosition())

    local locker = getContainerByName("Locker")
    if not locker then
        for i, tile in pairs(tiles) do
            for i, item in pairs(tile:getItems()) do
                if table.find(LOCKERS_LIST, item:getId()) then
                    local topThing = tile:getTopUseThing()
                    if not topThing:isNotMoveable() then
                        g_game.move(topThing, pPos, topThing:getCount())
                    else
                        return g_game.open(item)
                    end
                end
            end
        end
    else
        return true
    end
end

--- Opens depot chest.
-- @return void(acion) or boolean
function CaveBot.OpenDepotChest()
    local depot = getContainerByName("Depot chest")
    if not depot then
        local locker = getContainerByName("Locker")
        if not locker then
            return CaveBot.OpenLocker()
        end
        for i, item in pairs(locker:getItems()) do
            if item:getId() == 3502 then
                return g_game.open(item, locker)
            end
        end
    else
        return true
    end
end

--- Opens inbox inside locker.
-- @return void(acion) or boolean
function CaveBot.OpenInbox()
    local inbox = getContainerByName("Your inbox")
    if not inbox then
        local locker = getContainerByName("Locker")
        if not locker then
            return CaveBot.OpenLocker()
        end
        for i, item in pairs(locker:getItems()) do
            if item:getId() == 12902 then
                return g_game.open(item)
            end
        end
    else
        return true
    end
end

--- Opens depot box of given number.
-- @param index is integer
-- @return void or boolean
function CaveBot.OpenDepotBox(index)
    local depot = getContainerByName("Depot chest")
    if not depot then
        return CaveBot.ReachAndOpenDepot()
    end

    local foundParent = false
    for i, container in pairs(getContainers()) do
        if container:getName():lower():find("depot box") then
            foundParent = container
            break
        end
    end
    if foundParent then return true end

    for i, container in pairs(depot:getItems()) do
        if i == index then
            return g_game.open(container)
        end
    end
end

--- Reaches and opens depot.
-- Combined for shorthand usage.
-- @return boolean whether succeed to reach and open depot
function CaveBot.ReachAndOpenDepot()
    if CaveBot.ReachDepot() and CaveBot.OpenDepotChest() then 
        return true 
    end
    return false
end

--- Reaches and opens imbox.
-- Combined for shorthand usage.
-- @return boolean whether succeed to reach and open depot
function CaveBot.ReachAndOpenInbox()
    if CaveBot.ReachDepot() and CaveBot.OpenInbox() then 
        return true 
    end
    return false
end

--- Stripped down function to stash item.
-- @param item is object
-- @param index is integer
-- @param destination is object
-- @return void
function CaveBot.StashItem(item, index, destination)
    destination = destination or getContainerByName("Depot chest")
    if not destination then return false end

    return g_game.move(item, destination:getSlotPosition(index), item:getCount())
end

--- Withdraws item from depot chest or mail inbox.
-- main function for depositer/withdrawer
-- @param id is integer
-- @param amount is integer
-- @param fromDepot is boolean or integer
-- @param destination is object
-- @return void
function CaveBot.WithdrawItem(id, amount, fromDepot, destination)
    if destination and type(destination) == "string" then
        destination = getContainerByName(destination)
    end
    local itemCount = itemAmount(id)
    local depot
    for i, container in pairs(getContainers()) do
        if container:getName():lower():find("depot box") or container:getName():lower():find("your inbox") then
            depot = container
            break
        end
    end
    if not depot then
        if fromDepot then
            if not CaveBot.OpenDepotBox(fromDepot) then return end
        else
            return CaveBot.ReachAndOpenInbox()
        end
        return
    end
    if not destination then
        for i, container in pairs(getContainers()) do
            if container:getCapacity() > #container:getItems() and not string.find(container:getName():lower(), "quiver") and not string.find(container:getName():lower(), "depot") and not string.find(container:getName():lower(), "loot") and not string.find(container:getName():lower(), "inbox") then
                destination = container
            end
        end
    end

    if itemCount >= amount then 
        return true 
    end

    local toMove = amount - itemCount
    for i, item in pairs(depot:getItems()) do
        if item:getId() == id then
            return g_game.move(item, destination:getSlotPosition(destination:getItemsCount()), math.min(toMove, item:getCount()))
        end
    end
end

-- ##################### --
-- [[[[[ Talk class ]]]] --
-- ##################### --

--- Controlled by event caller.
-- Simple way to build npc conversations instead of multiline overcopied code.
-- @return void
function CaveBot.Conversation(...)
    local expressions = {...}
    local delay = storage.extras.talkDelay or 1000

    local talkDelay = 0
    for i, expr in ipairs(expressions) do
        schedule(talkDelay, function() NPC.say(expr) end)
        talkDelay = talkDelay + delay
    end
end

--- Says hi trade to NPC.
-- Used as shorthand to open NPC trade window.
-- @return void
function CaveBot.OpenNpcTrade()
    return CaveBot.Conversation("hi", "trade")
end

--- Says hi destination yes to NPC.
-- Used as shorthand to travel.
-- @param destination is string
-- @return void
function CaveBot.Travel(destination)
    return CaveBot.Conversation("hi", destination, "yes")
end