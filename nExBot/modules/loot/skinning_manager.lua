--[[
  NexBot Skinning Manager
  Improved skinning with pathability and LOS checks
  
  Author: NexBot Team
  Version: 1.0.0
]]

local SkinningManager = {
  enabled = false,
  skinnableCreatures = {},
  lastSkinTime = 0,
  skinCooldown = 1000,
  maxDistance = 3,
  skinningKnifeId = 5908
}

-- Default skinnable creatures
local DEFAULT_SKINNABLE = {
  "minotaur",
  "minotaur archer",
  "minotaur guard",
  "minotaur mage",
  "dragon",
  "dragon lord",
  "behemoth",
  "demon"
}

function SkinningManager:new()
  local instance = {
    enabled = false,
    skinnableCreatures = {},
    lastSkinTime = 0,
    skinCooldown = 1000,
    maxDistance = 3,
    skinningKnifeId = 5908
  }
  
  -- Add default skinnable creatures
  for _, name in ipairs(DEFAULT_SKINNABLE) do
    instance.skinnableCreatures[name:lower()] = true
  end
  
  setmetatable(instance, { __index = self })
  return instance
end

function SkinningManager:addSkinnableCreature(creatureName)
  self.skinnableCreatures[creatureName:lower()] = true
end

function SkinningManager:removeSkinnableCreature(creatureName)
  self.skinnableCreatures[creatureName:lower()] = nil
end

function SkinningManager:isSkinnableCreature(creatureName)
  return self.skinnableCreatures[creatureName:lower()] == true
end

function SkinningManager:canReachCorpse(corpsePos)
  local playerPos = pos()
  if not playerPos then return false end
  
  -- Check distance
  local distance = math.sqrt(
    math.pow(playerPos.x - corpsePos.x, 2) +
    math.pow(playerPos.y - corpsePos.y, 2)
  )
  
  if distance > self.maxDistance then
    return false
  end
  
  -- Check if corpse position is walkable
  if g_map then
    local tile = g_map.getTile(corpsePos)
    if not tile or not tile:isWalkable() then
      return false
    end
  end
  
  -- Check line of sight
  if not self:hasLineOfSight(playerPos, corpsePos) then
    return false
  end
  
  return true
end

function SkinningManager:hasLineOfSight(fromPos, toPos)
  if not g_map then return true end
  
  -- Bresenham line algorithm for LOS
  local dx = math.abs(toPos.x - fromPos.x)
  local dy = math.abs(toPos.y - fromPos.y)
  local sx = fromPos.x < toPos.x and 1 or -1
  local sy = fromPos.y < toPos.y and 1 or -1
  local err = dx - dy
  
  local x, y = fromPos.x, fromPos.y
  
  while true do
    if x == toPos.x and y == toPos.y then
      return true
    end
    
    local tile = g_map.getTile({x = x, y = y, z = fromPos.z})
    
    if tile then
      -- Check for blocking items
      local topThing = tile:getTopThing()
      if topThing and not topThing:isCreature() and not tile:isWalkable() then
        return false
      end
    end
    
    local e2 = 2 * err
    if e2 > -dy then
      err = err - dy
      x = x + sx
    end
    if e2 < dx then
      err = err + dx
      y = y + sy
    end
  end
end

function SkinningManager:findSkinnableCorpses()
  local corpses = {}
  local playerPos = pos()
  if not playerPos or not g_map then return corpses end
  
  for x = playerPos.x - self.maxDistance, playerPos.x + self.maxDistance do
    for y = playerPos.y - self.maxDistance, playerPos.y + self.maxDistance do
      local tile = g_map.getTile({x = x, y = y, z = playerPos.z})
      
      if tile then
        local items = tile:getItems()
        
        for _, item in ipairs(items) do
          -- Check if item is a corpse (typically containers with specific IDs)
          if item:isContainer() then
            local itemName = item:getName():lower()
            
            -- Check if any skinnable creature name is in the corpse name
            for creatureName, _ in pairs(self.skinnableCreatures) do
              if itemName:find(creatureName) then
                local corpsePos = {x = x, y = y, z = playerPos.z}
                
                if self:canReachCorpse(corpsePos) then
                  table.insert(corpses, {
                    item = item,
                    pos = corpsePos,
                    name = itemName
                  })
                end
                break
              end
            end
          end
        end
      end
    end
  end
  
  return corpses
end

function SkinningManager:findSkinningKnife()
  local knife = findItem(self.skinningKnifeId)
  return knife
end

function SkinningManager:skinCorpse(corpseInfo)
  if not corpseInfo then return false end
  if not self:canReachCorpse(corpseInfo.pos) then return false end
  
  local knife = self:findSkinningKnife()
  if not knife then return false end
  
  -- Use knife on corpse
  useWith(knife, corpseInfo.item)
  
  self.lastSkinTime = now or os.time() * 1000
  
  return true
end

function SkinningManager:shouldSkin()
  if not self.enabled then return false end
  
  local currentTime = now or os.time() * 1000
  if (currentTime - self.lastSkinTime) < self.skinCooldown then
    return false
  end
  
  -- Check if we have skinning knife
  if not self:findSkinningKnife() then
    return false
  end
  
  return true
end

function SkinningManager:attemptSkinning()
  if not self:shouldSkin() then
    return false
  end
  
  local corpses = self:findSkinnableCorpses()
  
  if #corpses > 0 then
    return self:skinCorpse(corpses[1])
  end
  
  return false
end

function SkinningManager:toggle()
  self.enabled = not self.enabled
  return self.enabled
end

function SkinningManager:setMaxDistance(tiles)
  self.maxDistance = math.max(1, math.min(5, tiles))
end

function SkinningManager:setSkinningKnifeId(itemId)
  self.skinningKnifeId = itemId
end

function SkinningManager:getSkinnableCount()
  local count = 0
  for _ in pairs(self.skinnableCreatures) do
    count = count + 1
  end
  return count
end

return SkinningManager
