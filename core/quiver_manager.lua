--[[
  Quiver Manager - Optimized for nExBot v1.0.0
  
  Automatically manages ammunition in quiver:
  - Moves correct ammo type (arrows/bolts) into quiver based on equipped weapon
  - Clears wrong ammo from quiver
  - Uses O(1) lookups and smart cooldowns for performance
  - Only works with open containers (no auto-opening)
  - Uses EventBus equipment:change for reactive weapon detection
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
    
    -- Find ammo item in OPEN containers only (simple and reliable)
    local function findAmmoItem(ammoIds)
        for _, container in pairs(g_game.getContainers()) do
            local cname = container:getName():lower()
            if not cname:find("quiver") then
                for _, item in ipairs(container:getItems()) do
                    local itemId = item:getId()
                    for _, ammoId in ipairs(ammoIds) do
                        if itemId == ammoId then
                            return item, ammoId
                        end
                    end
                end
            end
        end
        return nil, nil
    end
    
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

    -- Main quiver management logic (only uses open containers)
    local function manageQuiver(isBowEquipped, quiverContainer)
        local ammoLookup = isBowEquipped and arrowLookup or boltLookup
        local ammoList = isBowEquipped and arrows or bolts
        
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

        -- Second pass: Fill quiver if not full (only from open containers)
        if not containerIsFull(quiverContainer) then
            local ammoItem, ammoId = findAmmoItem(ammoList)
            if ammoItem then
                local pos = quiverContainer:getSlotPosition(quiverContainer:getItemsCount())
                g_game.move(ammoItem, pos, ammoItem:getCount())
                return false -- Moved something, not done yet
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
    
    -- EventBus integration for equipment changes (reactive weapon detection)
    if EventBus and EventBus.on then
        EventBus.on("equipment:change", function(slotId, slotName, currentId, lastId, item)
            -- React to weapon or shield slot changes
            if slotName == "left" or slotName == "right" then
                needsCheck = true
                -- Clear cached equipment to force recalculation
                cachedLeftId = nil
                cachedRightId = nil
            end
        end)
    end
    
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
        end
        
        -- Always try to get the quiver container (it may have been opened since last check)
        if cachedWeaponType then
            cachedQuiverContainer = getContainerByItem(cachedRightId)
        end
        
        return cachedWeaponType ~= nil and cachedQuiverContainer ~= nil
    end
    
    -- Main macro - runs less frequently, with cooldown protection
    local quiverManagerMacro = macro(300, "Quiver Manager", function()
        -- Skip if nothing changed
        if not needsCheck then return end
        
        -- Cooldown between moves
        local currentTime = now
        if (currentTime - lastMoveTime) < MOVE_COOLDOWN then return end
        
        -- Check if we have a bow/xbow equipped
        local leftItem = getLeft()
        local rightItem = getRight()
        
        if not leftItem or not rightItem then
            needsCheck = false
            return
        end
        
        local leftId = leftItem:getId()
        
        -- Determine weapon type
        local weaponType = nil
        if bowLookup[leftId] then
            weaponType = 1 -- bow
        elseif xbowLookup[leftId] then
            weaponType = 2 -- xbow
        end
        
        if not weaponType then
            needsCheck = false
            return
        end
        
        -- Check if right hand is a quiver (container)
        if not rightItem:isContainer() then
            needsCheck = false
            return
        end
        
        -- Try to get the quiver container (only works if quiver is open)
        local quiverContainer = getContainerByItem(rightItem:getId())
        
        -- If quiver is not open, skip (user must open it manually)
        if not quiverContainer then
            return -- Quiver not open, wait for user to open it
        end
        
        -- Manage the quiver
        local isBowEquipped = weaponType == 1
        local done = manageQuiver(isBowEquipped, quiverContainer)
        
        if done then
            needsCheck = false -- Nothing more to do
        else
            lastMoveTime = currentTime -- Just moved something, apply cooldown
        end
    end)
    BotDB.registerMacro(quiverManagerMacro, "quiverManager")
end
