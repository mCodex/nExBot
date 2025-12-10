--[[
  BotCore: Items Module
  
  High-performance item utility functions.
  Consolidates item operations from HealBot, AttackBot, and TargetBot.
  
  Features:
    - Hotkey-style item usage (works without open backpack)
    - Unified useItemLikeHotkey for self and target
    - Container utilities
    - Item equip detection (active/inactive rings/amulets)
]]

local Items = {}
BotCore.Items = Items

-- ============================================================================
-- HOTKEY-STYLE ITEM USAGE
-- ============================================================================

-- Use item on self (like pressing a hotkey) - works without open backpack
-- @param itemId: item ID to use
-- @return boolean success
function Items.useSelf(itemId)
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return false end
  
  -- Method 1: Use inventory item with player (works without open backpack - like hotkeys)
  if g_game.useInventoryItemWith then
    g_game.useInventoryItemWith(itemId, localPlayer)
    return true
  end
  
  -- Method 2: Fallback - find item in open containers and use WITH player
  local item = findItem(itemId)
  if item then
    g_game.useWith(item, localPlayer)
    return true
  end
  
  -- Method 3: Try simple inventory use (some items don't need target)
  if g_game.useInventoryItem then
    g_game.useInventoryItem(itemId)
    return true
  end
  
  return false
end

-- Use item on target creature/tile (like pressing a hotkey) - works without open backpack
-- @param itemId: item ID to use
-- @param target: creature or tile to use item on
-- @param subType: optional subType (for fluids)
-- @return boolean success
function Items.useOn(itemId, target, subType)
  if not target then return false end
  
  -- Determine subType based on client version
  local thing = g_things.getThingType(itemId)
  if not thing or not thing:isFluidContainer() then
    subType = g_game.getClientVersion() >= 860 and 0 or 1
  end
  
  -- Method 1: Modern clients (780+) - use inventory item directly (like hotkey)
  if g_game.getClientVersion() >= 780 then
    if g_game.useInventoryItemWith then
      g_game.useInventoryItemWith(itemId, target, subType)
      return true
    end
  end
  
  -- Method 2: Legacy clients - find item and use with target
  local tmpItem = g_game.findPlayerItem(itemId, subType)
  if tmpItem then
    g_game.useWith(tmpItem, target, subType)
    return true
  end
  
  -- Method 3: Use findItem as fallback
  local item = findItem(itemId)
  if item then
    g_game.useWith(item, target, subType)
    return true
  end
  
  return false
end

-- ============================================================================
-- ITEM COUNT AND FINDING
-- ============================================================================

-- Get item count in inventory and containers
-- @param itemId: item ID to count
-- @return number
function Items.count(itemId)
  return player:getItemsCount(itemId)
end

-- Check if player has item
-- @param itemId: item ID to check
-- @param minAmount: minimum amount required (default 1)
-- @return boolean
function Items.has(itemId, minAmount)
  minAmount = minAmount or 1
  return Items.count(itemId) >= minAmount
end

-- ============================================================================
-- CONTAINER UTILITIES
-- ============================================================================

-- Get container by name
-- @param name: container name
-- @param notFull: if true, only return if container is not full
-- @return container or nil
function Items.getContainerByName(name, notFull)
  if type(name) ~= "string" then return nil end
  
  for _, c in pairs(getContainers()) do
    local containerName = c:getName():lower()
    if containerName == name:lower() then
      if not notFull or c:getCapacity() > #c:getItems() then
        return c
      end
    end
  end
  return nil
end

-- Get container by item ID
-- @param itemId: container item ID
-- @param notFull: if true, only return if container is not full
-- @return container or nil
function Items.getContainerById(itemId, notFull)
  if type(itemId) ~= "number" then return nil end
  
  for _, c in pairs(getContainers()) do
    if c:getContainerItem():getId() == itemId then
      if not notFull or c:getCapacity() > #c:getItems() then
        return c
      end
    end
  end
  return nil
end

-- Check if container is full
-- @param container: container object
-- @return boolean
function Items.isContainerFull(container)
  if not container then return false end
  return container:getCapacity() <= #container:getItems()
end

-- ============================================================================
-- EQUIP STATE DETECTION
-- ============================================================================

-- Mapping of inactive -> active item IDs (rings, amulets, etc.)
local INACTIVE_TO_ACTIVE = {
  [3049] = 3086,   -- Stealth ring
  [3050] = 3087,   -- Time ring
  [3051] = 3088,   -- Might ring
  [3052] = 3089,   -- Life ring
  [3053] = 3090,   -- Ring of healing
  [3091] = 3094,   -- Protection amulet
  [3092] = 3095,   -- Dragon necklace
  [3093] = 3096,   -- Elven amulet
  [3097] = 3099,   -- Stone skin amulet
  [3098] = 3100,   -- Bronze amulet
  [16114] = 16264, -- Prismatic ring
  [23531] = 23532, -- Werewolf amulet
  [23533] = 23534, -- Werewolf helmet
  [23544] = 23528, -- Ferumbras' amulet
  [23529] = 23530, -- Ferumbras' amulet (ek)
  [30343] = 30342, -- Sleep Shawl
  [30344] = 30345, -- Enchanted Pendulet
  [30403] = 30402, -- Enchanted Theurgic Amulet
  [31621] = 31616, -- Blister Ring
  [32621] = 32635  -- Ring of Souls
}

-- Reverse mapping: active -> inactive
local ACTIVE_TO_INACTIVE = {}
for inactive, active in pairs(INACTIVE_TO_ACTIVE) do
  ACTIVE_TO_INACTIVE[active] = inactive
end

-- Get active (equipped) item ID from inactive ID
-- @param itemId: inactive item ID
-- @return active item ID or same ID if not applicable
function Items.getActiveId(itemId)
  return INACTIVE_TO_ACTIVE[itemId] or itemId
end

-- Get inactive (unequipped) item ID from active ID
-- @param itemId: active item ID
-- @return inactive item ID or same ID if not applicable
function Items.getInactiveId(itemId)
  return ACTIVE_TO_INACTIVE[itemId] or itemId
end

-- Check if item is equipped (comparing both active and inactive forms)
-- @param itemId: item ID (can be active or inactive form)
-- @return boolean
function Items.isEquipped(itemId)
  local activeId = Items.getActiveId(itemId)
  local inactiveId = Items.getInactiveId(itemId)
  
  -- Check ring slot
  local ring = player:getInventoryItem(InventorySlotFinger)
  if ring then
    local ringId = ring:getId()
    if ringId == itemId or ringId == activeId or ringId == inactiveId then
      return true
    end
  end
  
  -- Check amulet slot
  local amulet = player:getInventoryItem(InventorySlotNeck)
  if amulet then
    local amuletId = amulet:getId()
    if amuletId == itemId or amuletId == activeId or amuletId == inactiveId then
      return true
    end
  end
  
  return false
end

-- ============================================================================
-- GROUND ITEM UTILITIES
-- ============================================================================

-- Find item on ground (current floor)
-- @param itemId: item ID to find
-- @return item or nil
function Items.findOnGround(itemId)
  for _, tile in ipairs(g_map.getTiles(posz())) do
    for _, item in ipairs(tile:getItems()) do
      if item:getId() == itemId then
        return item
      end
    end
  end
  return nil
end

-- Use item on ground
-- @param itemId: item ID to find and use
-- @return boolean success
function Items.useGround(itemId)
  local item = Items.findOnGround(itemId)
  if item then
    use(item)
    return true
  end
  return false
end

-- Drop item on ground
-- @param itemIdOrObject: item ID or item object
-- @return boolean success
function Items.drop(itemIdOrObject)
  local item = itemIdOrObject
  if type(itemIdOrObject) == "number" then
    item = findItem(itemIdOrObject)
  end
  
  if not item then return false end
  
  g_game.move(item, pos(), item:getCount())
  return true
end

-- ============================================================================
-- TILE ITEM CHECKS
-- ============================================================================

-- Check if item is on a specific tile
-- @param itemId: item ID to find
-- @param tileOrPos: tile object or position
-- @return boolean
function Items.isOnTile(itemId, tileOrPos)
  if not itemId then return false end
  
  local tile
  if type(tileOrPos) == "table" then
    tile = g_map.getTile(tileOrPos)
  else
    tile = tileOrPos
  end
  
  if not tile then return false end
  
  for _, item in ipairs(tile:getItems()) do
    if item:getId() == itemId then
      return true
    end
  end
  
  return false
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

if logInfo then
  logInfo("[BotCore] Items module loaded")
end

return Items
