--[[
  NexBot Corpse Looting System
  Automatic looting from killed creatures
  
  Author: NexBot Team
  Version: 1.0.0
]]

local CorpseLoot = {
  enabled = false,
  lootList = {},
  lootDistance = 3,
  lastLootTime = 0,
  lootCooldown = 500,
  lootGold = true,
  lootAll = false
}

-- Common valuable items to auto-loot
local DEFAULT_LOOT = {
  3031, -- gold coin
  3035, -- platinum coin
  3043, -- crystal coin
  3577, -- meat
  3582, -- ham
  3583, -- dragon ham
  3286, -- mace
  3264, -- sword
}

function CorpseLoot:new()
  local instance = {
    enabled = false,
    lootList = {},
    lootDistance = 3,
    lastLootTime = 0,
    lootCooldown = 500,
    lootGold = true,
    lootAll = false
  }
  
  -- Add default loot items
  for _, itemId in ipairs(DEFAULT_LOOT) do
    instance.lootList[itemId] = true
  end
  
  setmetatable(instance, { __index = self })
  return instance
end

function CorpseLoot:addToLootList(itemId)
  self.lootList[itemId] = true
end

function CorpseLoot:removeFromLootList(itemId)
  self.lootList[itemId] = nil
end

function CorpseLoot:isInLootList(itemId)
  if self.lootAll then return true end
  if self.lootGold and (itemId == 3031 or itemId == 3035 or itemId == 3043) then
    return true
  end
  return self.lootList[itemId] == true
end

function CorpseLoot:findNearbyCorpses()
  local corpses = {}
  local playerPos = pos()
  if not playerPos then return corpses end
  
  -- Get tiles in range
  if not g_map then return corpses end
  
  for x = playerPos.x - self.lootDistance, playerPos.x + self.lootDistance do
    for y = playerPos.y - self.lootDistance, playerPos.y + self.lootDistance do
      local tile = g_map.getTile({x = x, y = y, z = playerPos.z})
      
      if tile then
        local topThing = tile:getTopUseThing()
        
        if topThing and topThing:isContainer() then
          -- Check if it's a corpse (has items inside)
          local distance = math.sqrt(
            math.pow(playerPos.x - x, 2) +
            math.pow(playerPos.y - y, 2)
          )
          
          if distance <= self.lootDistance then
            table.insert(corpses, {
              item = topThing,
              pos = {x = x, y = y, z = playerPos.z},
              distance = distance
            })
          end
        end
      end
    end
  end
  
  -- Sort by distance
  table.sort(corpses, function(a, b)
    return a.distance < b.distance
  end)
  
  return corpses
end

function CorpseLoot:lootFromCorpse(corpseInfo)
  if not corpseInfo or not corpseInfo.item then return 0 end
  
  -- Open corpse
  g_game.open(corpseInfo.item)
  
  -- Wait briefly for container to open
  local itemsLooted = 0
  
  -- Find the opened container
  local containers = getContainers()
  if not containers then return 0 end
  
  for _, container in pairs(containers) do
    local items = container:getItems()
    
    for _, item in ipairs(items) do
      if self:isInLootList(item:getId()) then
        -- Move to player inventory
        local targetContainer = self:getFirstLootContainer()
        
        if targetContainer then
          g_game.move(item, targetContainer:getSlotPosition(targetContainer:getItemsCount()), item:getCount())
          itemsLooted = itemsLooted + 1
        end
      end
    end
  end
  
  return itemsLooted
end

function CorpseLoot:getFirstLootContainer()
  local containers = getContainers()
  if not containers then return nil end
  
  for _, container in pairs(containers) do
    if container:getItemsCount() < container:getCapacity() then
      return container
    end
  end
  
  return nil
end

function CorpseLoot:lootAllNearbyCorpses()
  if not self.enabled then return 0 end
  
  local currentTime = now or os.time() * 1000
  if (currentTime - self.lastLootTime) < self.lootCooldown then
    return 0
  end
  
  local corpses = self:findNearbyCorpses()
  local totalLooted = 0
  
  for _, corpse in ipairs(corpses) do
    local looted = self:lootFromCorpse(corpse)
    totalLooted = totalLooted + looted
    
    if looted > 0 then
      self.lastLootTime = currentTime
      break -- Loot one corpse per cycle to avoid spam
    end
  end
  
  return totalLooted
end

function CorpseLoot:setLootDistance(tiles)
  self.lootDistance = math.max(1, math.min(10, tiles))
end

function CorpseLoot:toggle()
  self.enabled = not self.enabled
  return self.enabled
end

function CorpseLoot:setLootGold(enabled)
  self.lootGold = enabled
end

function CorpseLoot:setLootAll(enabled)
  self.lootAll = enabled
end

function CorpseLoot:getLootListCount()
  local count = 0
  for _ in pairs(self.lootList) do
    count = count + 1
  end
  return count
end

function CorpseLoot:clearLootList()
  self.lootList = {}
end

return CorpseLoot
