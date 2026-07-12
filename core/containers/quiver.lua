local Quiver = {}

local QUIVER_IDS = {
  [3003] = true, [3004] = true, [3005] = true, [3006] = true,
  [3007] = true, [3008] = true, [3009] = true, [3010] = true,
  [3031] = true, [3032] = true, [3033] = true, [3034] = true,
}

function Quiver.isPaladin()
  if not _G.player then return false end
  local voc = _G.player:getVocation()
  return voc == 2 or voc == 12
end

function Quiver.discoverRoot()
  if not Quiver.isPaladin() then return nil end

  if not _G.g_game then return nil end

  local slots = {5, 10}
  for _, slot in ipairs(slots) do
    local item = _G.g_game.getHeadSlot and _G.g_game.getHeadSlot(slot)
    if item and QUIVER_IDS[item:getId()] and item:isContainer() then
      return {
        rootKind = "quiver",
        identity = "quiver:" .. item:getId(),
        itemType = item:getId(),
        slotIndex = slot,
      }
    end
  end

  return nil
end

function Quiver.open()
  local root = Quiver.discoverRoot()
  if not root then return false end

  local ClientAdapter = dofile("core/containers/client_adapter.lua")
  local item = _G.g_game.getInventoryItem(root.slotIndex)
  if item then
    ClientAdapter.open(item)
    return true
  end
  return false
end

return Quiver
