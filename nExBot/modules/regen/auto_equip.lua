--[[
  Auto Equip Module
  
  Automatic equipment switching based on conditions.
  Based on classic OTClient bot equip patterns.
  
  Author: nExBot Team
  Version: 1.0.0
]]

setDefaultTab("Regen")

local scripts = 2 -- Number of auto equip panels

UI.Label("Auto Equip")

if type(storage.autoEquip) ~= "table" then
  storage.autoEquip = {}
end

-- Create panels
for i = 1, scripts do
  if not storage.autoEquip[i] then
    storage.autoEquip[i] = {
      on = false,
      title = "Auto Equip",
      item1 = i == 1 and 3052 or 0, -- Life ring by default for first
      item2 = i == 1 and 3089 or 0, -- Might ring by default for first
      slot = i == 1 and 9 or 0      -- Ring slot (9)
    }
  end
  
  UI.TwoItemsAndSlotPanel(storage.autoEquip[i], function(widget, newParams)
    storage.autoEquip[i] = newParams
  end)
end

-- Slot mapping
local slots = {
  [1] = "head",
  [4] = "armor",
  [5] = "shield",
  [6] = "legs",
  [8] = "feet",
  [9] = "ring",
  [10] = "ammo",
  [2] = "amulet"
}

-- Equipment swap macro
macro(250, function()
  local containers = g_game.getContainers()
  
  for index, autoEquip in ipairs(storage.autoEquip) do
    if autoEquip.on then
      local item1 = autoEquip.item1
      local item2 = autoEquip.item2
      local slot = autoEquip.slot
      
      if item1 > 0 and item2 > 0 and slot > 0 then
        -- Get current equipment in slot
        local equipped = getSlot(slot)
        local equippedId = equipped and equipped:getId() or 0
        
        -- Determine which item should be equipped
        -- Default logic: if in combat, use item2, otherwise item1
        local inCombat = target() ~= nil or hasCondition("Battle")
        local targetItem = inCombat and item2 or item1
        
        if equippedId ~= targetItem then
          -- Find the item to equip
          local foundItem = nil
          
          for _, container in pairs(containers) do
            for _, item in ipairs(container:getItems()) do
              if item:getId() == targetItem then
                foundItem = item
                break
              end
            end
            if foundItem then break end
          end
          
          if foundItem then
            g_game.move(foundItem, {x = 65535, y = slot, z = 0}, foundItem:getCount())
          end
        end
      end
    end
  end
end)

-- Get equipped item in slot
function getSlot(slotId)
  local inventory = player:getInventory and player:getInventory() or {}
  return inventory[slotId]
end

-- Manual equip function
local function equipItem(item, slotId)
  if item then
    g_game.move(item, {x = 65535, y = slotId, z = 0}, item:getCount())
    return true
  end
  return false
end

-- Find item in containers
local function findItemInContainers(itemId)
  local containers = g_game.getContainers()
  
  for _, container in pairs(containers) do
    for _, item in ipairs(container:getItems()) do
      if item:getId() == itemId then
        return item
      end
    end
  end
  
  return nil
end

-- Public API
AutoEquip = {
  addRule = function(item1, item2, slot)
    local newRule = {
      on = true,
      title = "Auto Equip",
      item1 = item1 or 0,
      item2 = item2 or 0,
      slot = slot or 9
    }
    table.insert(storage.autoEquip, newRule)
    return #storage.autoEquip
  end,
  
  removeRule = function(index)
    if storage.autoEquip[index] then
      table.remove(storage.autoEquip, index)
      return true
    end
    return false
  end,
  
  setRuleEnabled = function(index, enabled)
    if storage.autoEquip[index] then
      storage.autoEquip[index].on = enabled
      return true
    end
    return false
  end,
  
  getRules = function()
    return storage.autoEquip
  end,
  
  forceEquip = function(itemId, slotId)
    local item = findItemInContainers(itemId)
    if item then
      return equipItem(item, slotId)
    end
    return false
  end
}
