--[[
  NexBot Door Automation
  Automatic door detection and opening
  
  Author: NexBot Team
  Version: 1.0.0
]]

local DoorAutomation = {
  enabled = false,
  openedDoors = {},
  doorCooldown = {},
  maxCooldownTime = 2000,
  maxDistance = 5
}

-- Common door IDs
local DOOR_IDS = {
  -- Wooden doors
  1209, 1210, 1211, 1212, 1213, 1214, 1215, 1216, 1217, 1218,
  1219, 1220, 1221, 1222, 1223, 1224, 1225, 1226, 1227, 1228,
  -- Stone/metal doors
  1245, 1246, 1247, 1248, 1249, 1250, 1251, 1252, 1253, 1254,
  -- Quest doors
  3535, 3536, 3537, 3538, 3539, 3540, 3541, 3542, 3543, 3544,
  3545, 3546, 3547, 3548, 3549, 3550, 3551, 3552,
  -- Level doors
  1261, 1262, 1263, 1264, 1265, 1266, 1267, 1268, 1269, 1270,
  -- Key doors
  4913, 4914, 4915, 4916, 4917, 4918, 5098, 5099, 5100, 5101,
  5102, 5103, 5104, 5105, 5106, 5107, 5108, 5109, 5110, 5111,
  5112, 5113, 5114, 5115, 5116, 5117, 5118, 5119, 5120, 5121,
  -- Magic doors
  5645, 5646, 5647, 5648, 5649, 5650, 5651, 5652,
  -- Modern doors
  7033, 7034, 7035, 7036, 7037, 7038, 7039, 7040, 7041, 7042,
  7043, 7044, 7045, 7046, 7047, 7048, 7049, 7050, 7051, 7052,
  -- Gates
  9165, 9166, 9167, 9168, 9169, 9170, 9171, 9172, 9173, 9174,
  9175, 9176, 9177, 9178, 9179, 9180
}

function DoorAutomation:new()
  local instance = {
    enabled = false,
    openedDoors = {},
    doorCooldown = {},
    maxCooldownTime = 2000,
    maxDistance = 5
  }
  setmetatable(instance, { __index = self })
  return instance
end

function DoorAutomation:isDoorId(itemId)
  for _, id in ipairs(DOOR_IDS) do
    if itemId == id then
      return true
    end
  end
  return false
end

function DoorAutomation:findNearbyDoors()
  local doors = {}
  local playerPos = pos()
  if not playerPos or not g_map then return doors end
  
  for x = playerPos.x - self.maxDistance, playerPos.x + self.maxDistance do
    for y = playerPos.y - self.maxDistance, playerPos.y + self.maxDistance do
      local tile = g_map.getTile({x = x, y = y, z = playerPos.z})
      
      if tile then
        local items = tile:getItems()
        
        for _, item in ipairs(items) do
          if self:isDoorId(item:getId()) then
            table.insert(doors, {
              pos = {x = x, y = y, z = playerPos.z},
              item = item,
              itemId = item:getId()
            })
          end
        end
      end
    end
  end
  
  return doors
end

function DoorAutomation:isDoorBlocking(doorPos)
  if not g_map then return false end
  
  local tile = g_map.getTile(doorPos)
  if not tile then return false end
  
  local items = tile:getItems()
  for _, item in ipairs(items) do
    if self:isDoorId(item:getId()) then
      -- Check if door is closed (not walkable)
      if not tile:isWalkable() then
        return true
      end
    end
  end
  
  return false
end

function DoorAutomation:openDoor(doorPos)
  local key = string.format("%d_%d_%d", doorPos.x, doorPos.y, doorPos.z)
  local currentTime = now or os.time() * 1000
  
  -- Check cooldown
  if self.doorCooldown[key] then
    if (currentTime - self.doorCooldown[key]) < self.maxCooldownTime then
      return false
    end
  end
  
  if not g_map then return false end
  
  local tile = g_map.getTile(doorPos)
  if not tile then return false end
  
  local doorItem = nil
  local items = tile:getItems()
  
  for _, item in ipairs(items) do
    if self:isDoorId(item:getId()) then
      doorItem = item
      break
    end
  end
  
  if not doorItem then return false end
  
  -- Use door to open it
  use(doorItem)
  
  -- Set cooldown
  self.doorCooldown[key] = currentTime
  
  return true
end

function DoorAutomation:autoOpenDoorsOnPath(pathWaypoints)
  if not self.enabled then return 0 end
  
  local doorsOpened = 0
  
  for _, waypoint in ipairs(pathWaypoints) do
    if self:isDoorBlocking(waypoint) then
      if self:openDoor(waypoint) then
        doorsOpened = doorsOpened + 1
      end
    end
  end
  
  return doorsOpened
end

function DoorAutomation:autoOpenNearbyDoors()
  if not self.enabled then return false end
  
  local playerPos = pos()
  if not playerPos then return false end
  
  -- Check immediate surroundings (1 tile)
  for dx = -1, 1 do
    for dy = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        local checkPos = {
          x = playerPos.x + dx,
          y = playerPos.y + dy,
          z = playerPos.z
        }
        
        if self:isDoorBlocking(checkPos) then
          if self:openDoor(checkPos) then
            return true
          end
        end
      end
    end
  end
  
  return false
end

function DoorAutomation:toggle()
  self.enabled = not self.enabled
  return self.enabled
end

function DoorAutomation:setMaxDistance(tiles)
  self.maxDistance = math.max(1, math.min(10, tiles))
end

function DoorAutomation:setCooldown(ms)
  self.maxCooldownTime = math.max(500, ms)
end

function DoorAutomation:clearCooldowns()
  self.doorCooldown = {}
end

function DoorAutomation:getDoorCount()
  return #DOOR_IDS
end

return DoorAutomation
