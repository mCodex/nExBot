-- quiver.lua
-- Quiver detection and root lifecycle.  Owns: vocation check, quiver root identity.
-- Does NOT own: ammo refill, ammo indexing (those belong to Discovery/QuiverService).

local Quiver = {}

-- Paladin vocation IDs (base and promoted).
local PALADIN_VOCATIONS = { [2] = true, [12] = true }

-- Known quiver / arrow-slot item IDs.
-- Extend this list for server-specific quivers.
local QUIVER_ITEM_IDS = {
  [3003] = true, [3004] = true, [3005] = true, [3006] = true,
  [3007] = true, [3008] = true, [3009] = true, [3010] = true,
  [3031] = true, [3032] = true, [3033] = true, [3034] = true,
}

-- Inventory slot index for the ammo/arrow/quiver slot.
-- Tibia standard: 10 (SLOT_AMMO).  Override per server if needed.
local AMMO_SLOT = 10

-- Returns true when the current character is a Paladin.
function Quiver.isPaladin()
  local player = _G.player or (_G.g_game and _G.g_game.getLocalPlayer and _G.g_game.getLocalPlayer())
  if not player then return false end

  -- Try standard OTClient vocation API.
  local ok, voc = pcall(function() return player:getVocation() end)
  if ok and voc then
    return PALADIN_VOCATIONS[voc] == true
  end

  -- Fallback: try name-based detection from ACL / ClientService.
  if _G.getClient then
    local client = _G.getClient()
    if client and client.getVocation then
      local vname = client.getVocation()
      if type(vname) == "string" then
        local lower = vname:lower()
        return lower:find("paladin") ~= nil
      end
    end
  end

  return false
end

-- Returns true when the item at the ammo slot is a known quiver/container.
function Quiver.hasEquippedQuiver()
  local item = Quiver._getAmmoSlotItem()
  if not item then return false end
  return Quiver._isQuiverItem(item)
end

-- Returns a root descriptor for the equipped quiver, or nil.
-- { rootKind, identity, item, itemType, slotIndex }
function Quiver.discoverRoot()
  if not Quiver.isPaladin() then return nil end

  local item = Quiver._getAmmoSlotItem()
  if not item then return nil end
  if not Quiver._isQuiverItem(item) then return nil end

  local itemType = item:getId()
  return {
    rootKind   = "QUIVER",
    identity   = "quiver:" .. itemType .. ":" .. AMMO_SLOT,
    item       = item,
    itemType   = itemType,
    slotIndex  = AMMO_SLOT,
  }
end

-- Open the quiver through the ClientAdapter.
-- Returns true if an open was requested, false otherwise.
function Quiver.open()
  local root = Quiver.discoverRoot()
  if not root then return false end

  local ok, ClientAdapter = pcall(dofile, "core/containers/client_adapter.lua")
  if not ok or not ClientAdapter then return false end

  ClientAdapter.open(root.item)
  return true
end

-- Returns the item at the ammo/quiver slot, or nil.
function Quiver._getAmmoSlotItem()
  -- Prefer ACL ClientService if available.
  if _G.getClient then
    local client = _G.getClient()
    if client and client.getInventoryItem then
      return client.getInventoryItem(AMMO_SLOT)
    end
  end

  -- Fallback to raw g_game.
  if _G.g_game and _G.g_game.getInventoryItem then
    return _G.g_game.getInventoryItem(AMMO_SLOT)
  end

  return nil
end

-- Returns true when item is a known quiver item type and is a container.
function Quiver._isQuiverItem(item)
  if not item then return false end
  local ok, id = pcall(function() return item:getId() end)
  if not ok then return false end
  -- Check item ID against known quiver IDs.
  if QUIVER_ITEM_IDS[id] then return true end
  -- Fallback: any item in the ammo slot that is a container (for custom servers).
  local okC, isC = pcall(function() return item.isContainer and item:isContainer() end)
  return okC and isC == true
end

return Quiver

