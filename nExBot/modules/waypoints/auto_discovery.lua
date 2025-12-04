--[[
  nExBot Auto Discovery
  Intelligent route discovery and area analysis
  
  Author: nExBot Team
  Version: 1.0.0
]]

local AutoDiscovery = {
  discoveredAreas = {},
  exploredTiles = {},
  frontierTiles = {},
  areaThreshold = 10,
  maxExplorationRadius = 30
}

function AutoDiscovery:new()
  local instance = {
    discoveredAreas = {},
    exploredTiles = {},
    frontierTiles = {},
    areaThreshold = 10,
    maxExplorationRadius = 30
  }
  setmetatable(instance, { __index = self })
  return instance
end

function AutoDiscovery:discoverFromWaypoints(waypoints)
  local analysis = {
    safe_zones = {},
    chokepoints = {},
    danger_areas = {}
  }
  
  if #waypoints < 3 then return analysis end
  
  local clusters = self:clusterWaypoints(waypoints)
  
  for _, cluster in ipairs(clusters) do
    local info = self:analyzeCluster(cluster)
    
    if info then
      if info.isDangerous then
        table.insert(analysis.danger_areas, info)
      elseif info.isChokepoint then
        table.insert(analysis.chokepoints, info)
      else
        table.insert(analysis.safe_zones, info)
      end
    end
  end
  
  return analysis
end

function AutoDiscovery:clusterWaypoints(waypoints)
  local clusters = {}
  local used = {}
  
  for i, point in ipairs(waypoints) do
    if not used[i] then
      local cluster = {point}
      used[i] = true
      
      for j = i + 1, #waypoints do
        if not used[j] then
          local dist = self:distance(point, waypoints[j])
          
          if dist <= self.areaThreshold then
            table.insert(cluster, waypoints[j])
            used[j] = true
          end
        end
      end
      
      table.insert(clusters, cluster)
    end
  end
  
  return clusters
end

function AutoDiscovery:analyzeCluster(cluster)
  if #cluster == 0 then return nil end
  
  local centerX, centerY, centerZ = 0, 0, 0
  
  for _, point in ipairs(cluster) do
    centerX = centerX + point.x
    centerY = centerY + point.y
    centerZ = centerZ + (point.z or 7)
  end
  
  centerX = centerX / #cluster
  centerY = centerY / #cluster
  centerZ = centerZ / #cluster
  
  local spread = 0
  for _, point in ipairs(cluster) do
    local dist = math.sqrt(
      math.pow(point.x - centerX, 2) +
      math.pow(point.y - centerY, 2)
    )
    spread = spread + dist
  end
  spread = spread / #cluster
  
  local hasDanger = self:checkAreaForDanger({x = centerX, y = centerY, z = centerZ})
  local timeSpent = self:calculateTimeInCluster(cluster)
  local isChokepoint = timeSpent > 5000
  
  return {
    center = {x = centerX, y = centerY, z = centerZ},
    radius = spread,
    pointCount = #cluster,
    isDangerous = hasDanger,
    isChokepoint = isChokepoint,
    timeSpent = timeSpent
  }
end

function AutoDiscovery:distance(p1, p2)
  return math.sqrt(
    math.pow(p1.x - p2.x, 2) +
    math.pow(p1.y - p2.y, 2)
  )
end

function AutoDiscovery:calculateTimeInCluster(cluster)
  if #cluster < 2 then return 0 end
  
  local firstTime = cluster[1].timestamp or 0
  local lastTime = cluster[#cluster].timestamp or 0
  
  return lastTime - firstTime
end

function AutoDiscovery:checkAreaForDanger(areaCenter)
  if not getSpectators then return false end
  
  local specs = getSpectators()
  if not specs then return false end
  
  for _, creature in ipairs(specs) do
    if creature:isMonster() then
      local creaturePos = creature:getPosition()
      local dist = math.sqrt(
        math.pow(areaCenter.x - creaturePos.x, 2) +
        math.pow(areaCenter.y - creaturePos.y, 2)
      )
      
      if dist <= 10 then
        return true
      end
    end
  end
  
  return false
end

function AutoDiscovery:exploreFrontier(currentPos, maxRadius)
  local frontier = {}
  maxRadius = maxRadius or self.maxExplorationRadius
  
  for x = currentPos.x - maxRadius, currentPos.x + maxRadius do
    for y = currentPos.y - maxRadius, currentPos.y + maxRadius do
      local testPos = {x = x, y = y, z = currentPos.z}
      
      if not self:isPointExplored(testPos) then
        if self:isPointPromising(testPos) then
          table.insert(frontier, testPos)
        end
      end
    end
  end
  
  return frontier
end

function AutoDiscovery:isPointExplored(pos)
  local key = string.format("%d_%d_%d", pos.x, pos.y, pos.z or 7)
  return self.exploredTiles[key] ~= nil
end

function AutoDiscovery:isPointPromising(pos)
  if not g_map then return false end
  
  local tile = g_map.getTile(pos)
  if not tile then return false end
  if not tile:isWalkable() then return false end
  
  local closeToExplored = false
  for x = pos.x - 2, pos.x + 2 do
    for y = pos.y - 2, pos.y + 2 do
      if self:isPointExplored({x = x, y = y, z = pos.z}) then
        closeToExplored = true
        break
      end
    end
    if closeToExplored then break end
  end
  
  return closeToExplored
end

function AutoDiscovery:markExplored(pos)
  local key = string.format("%d_%d_%d", pos.x, pos.y, pos.z or 7)
  self.exploredTiles[key] = true
end

return AutoDiscovery
