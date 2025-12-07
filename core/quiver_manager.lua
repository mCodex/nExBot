--[[
  Quiver Manager - Optimized for nExBot v1.0.0
  
  Automatically manages ammunition in quiver:
  - Moves correct ammo type (arrows/bolts) into quiver based on equipped weapon
  - Clears wrong ammo from quiver
  - Uses O(1) lookups and smart cooldowns for performance
]]

if voc() == 2 or voc() == 12 then
    -- Weapon and ammo definitions
    local bows = { 3350, 31581, 27455, 8027, 20082, 36664, 7438, 28718, 36665, 14246, 19362, 35518, 34150, 29417, 9378, 16164, 22866, 12733, 8029, 20083, 20084, 8026, 8028, 34088 }
    local xbows = { 30393, 3349, 27456, 20085, 16163, 5947, 8021, 14247, 22867, 8023, 22711, 19356, 20086, 20087, 34089 }
    local arrows = { 16143, 763, 761, 7365, 3448, 762, 21470, 7364, 14251, 3447, 3449, 15793, 25757, 774, 35901 }
    local bolts = { 6528, 7363, 3450, 16141, 25758, 14252, 3446, 16142, 35902 }
    
    -- Build O(1) lookup tables
    local bowLookup = {}
    local xbowLookup = {}
    local arrowLookup = {}
    local boltLookup = {}
    
    for _, id in ipairs(bows) do bowLookup[id] = true end
    for _, id in ipairs(xbows) do xbowLookup[id] = true end
    for _, id in ipairs(arrows) do arrowLookup[id] = true end
    for _, id in ipairs(bolts) do boltLookup[id] = true end
    
    -- State management
    local needsCheck = true
    local lastMoveTime = 0
    local MOVE_COOLDOWN = 300 -- ms between moves to prevent spam
    local lastQuiverId = nil
    
    -- Only reset check flag when relevant containers change
    local function onContainerChange(container)
        if not container then 
            needsCheck = true
            return 
        end
        
        local name = container:getName():lower()
        -- Only trigger recheck if it's a quiver or backpack change
        if name:find("quiver") or name:find("backpack") or name:find("bag") then
            needsCheck = true
        end
        
        -- Also check if equipped quiver changed
        local rightItem = getRight()
        if rightItem and rightItem:isContainer() then
            local currentId = rightItem:getId()
            if currentId ~= lastQuiverId then
                lastQuiverId = currentId
                needsCheck = true
            end
        end
    end
    
    onContainerOpen(function(container, previousContainer)
        onContainerChange(container)
    end)

    onContainerClose(function(container)
        onContainerChange(container)
    end)
    
    onAddItem(function(container, slot, item, oldItem)
        onContainerChange(container)
    end)

    onRemoveItem(function(container, slot, item)
        onContainerChange(container)
    end)

    onContainerUpdateItem(function(container, slot, item, oldItem)
        onContainerChange(container)
    end)

    -- Find a valid destination container for wrong ammo
    local function findDestContainer(quiverContainer)
        for _, container in pairs(g_game.getContainers()) do
            if container ~= quiverContainer and not containerIsFull(container) then
                local cname = container:getName():lower()
                if not cname:find("loot") and not cname:find("quiver") and 
                   (cname:find("backpack") or cname:find("bag") or cname:find("chess")) then
                    return container
                end
            end
        end
        return nil
    end

    -- Main quiver management logic
    local function manageQuiver(isBowEquipped, quiverContainer)
        local ammoLookup = isBowEquipped and arrowLookup or boltLookup
        
        -- First pass: Clear wrong ammo from quiver
        local destContainer = nil
        for _, item in ipairs(quiverContainer:getItems()) do
            local itemId = item:getId()
            if not ammoLookup[itemId] then
                -- Wrong ammo found, need to move it out
                if not destContainer then
                    destContainer = findDestContainer(quiverContainer)
                end
                if destContainer then
                    local pos = destContainer:getSlotPosition(destContainer:getItemsCount())
                    g_game.move(item, pos, item:getCount())
                    return false -- Moved something, not done yet
                end
            end
        end

        -- Second pass: Fill quiver if not full
        if not containerIsFull(quiverContainer) then
            for _, container in pairs(g_game.getContainers()) do
                if container ~= quiverContainer then
                    for _, item in ipairs(container:getItems()) do
                        local itemId = item:getId()
                        if ammoLookup[itemId] then
                            local pos = quiverContainer:getSlotPosition(quiverContainer:getItemsCount())
                            g_game.move(item, pos, item:getCount())
                            return false -- Moved something, not done yet
                        end
                    end
                end
            end
        end
        
        return true -- Nothing to do
    end

    UI.Separator()
    
    -- Pre-cached equipment check to avoid repeated calls
    local cachedLeftId = nil
    local cachedRightId = nil
    local cachedWeaponType = nil -- 1 = bow, 2 = xbow, nil = none
    local cachedQuiverContainer = nil
    
    -- Update equipment cache (called less frequently)
    local function updateEquipmentCache()
        local leftItem = getLeft()
        local rightItem = getRight()
        
        if not leftItem or not rightItem then
            cachedWeaponType = nil
            cachedQuiverContainer = nil
            return false
        end
        
        local leftId = leftItem:getId()
        local rightId = rightItem:getId()
        
        -- Only recalculate if equipment changed
        if leftId ~= cachedLeftId or rightId ~= cachedRightId then
            cachedLeftId = leftId
            cachedRightId = rightId
            
            if not rightItem:isContainer() then
                cachedWeaponType = nil
                cachedQuiverContainer = nil
                return false
            end
            
            if bowLookup[leftId] then
                cachedWeaponType = 1
            elseif xbowLookup[leftId] then
                cachedWeaponType = 2
            else
                cachedWeaponType = nil
            end
            
            cachedQuiverContainer = getContainerByItem(rightId)
        end
        
        return cachedWeaponType ~= nil and cachedQuiverContainer ~= nil
    end
    
    -- Main macro - runs less frequently, with cooldown protection
    macro(300, "Quiver Manager", function()
        -- Skip if nothing changed
        if not needsCheck then return end
        
        -- Cooldown between moves
        local currentTime = now
        if (currentTime - lastMoveTime) < MOVE_COOLDOWN then return end
        
        -- Quick equipment check with caching
        if not updateEquipmentCache() then
            needsCheck = false
            return
        end
        
        -- Manage the quiver
        local isBowEquipped = cachedWeaponType == 1
        local done = manageQuiver(isBowEquipped, cachedQuiverContainer)
        
        if done then
            needsCheck = false -- Nothing more to do
        else
            lastMoveTime = currentTime -- Just moved something, apply cooldown
        end
    end)
end
