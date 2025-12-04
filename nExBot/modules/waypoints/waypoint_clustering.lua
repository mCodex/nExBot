--[[
  NexBot Waypoint Clustering
  K-Means style clustering for smart waypoint grouping
  
  Author: NexBot Team
  Version: 1.0.0
]]

local WaypointClustering = {
  clusterRadius = 5,
  minPointsPerCluster = 3
}

function WaypointClustering:new()
  local instance = {
    clusterRadius = 5,
    minPointsPerCluster = 3
  }
  setmetatable(instance, { __index = self })
  return instance
end

function WaypointClustering:clusterByLocation(waypoints, k)
  if #waypoints < self.minPointsPerCluster then
    return {waypoints}
  end
  
  k = k or 3
  local clusters = {}
  
  -- K-Means++ initialization
  local seeds = self:selectSeeds(waypoints, k)
  
  for _, seed in ipairs(seeds) do
    table.insert(clusters, {seed})
  end
  
  -- Assign remaining points to nearest cluster
  for _, point in ipairs(waypoints) do
    if not self:tableContains(seeds, point) then
      local nearestCluster = 1
      local minDistance = math.huge
      
      for ci, cluster in ipairs(clusters) do
        local center = self:getClusterCenter(cluster)
        local distance = self:distance(point, center)
        
        if distance < minDistance then
          minDistance = distance
          nearestCluster = ci
        end
      end
      
      table.insert(clusters[nearestCluster], point)
    end
  end
  
  return clusters
end

function WaypointClustering:selectSeeds(waypoints, k)
  if #waypoints == 0 then return {} end
  
  local seeds = {waypoints[1]}
  
  for i = 1, k - 1 do
    local farthest = nil
    local maxMinDist = -1
    
    for _, point in ipairs(waypoints) do
      if not self:tableContains(seeds, point) then
        local minDist = math.huge
        
        for _, seed in ipairs(seeds) do
          local dist = self:distance(point, seed)
          minDist = math.min(minDist, dist)
        end
        
        if minDist > maxMinDist then
          maxMinDist = minDist
          farthest = point
        end
      end
    end
    
    if farthest then
      table.insert(seeds, farthest)
    end
  end
  
  return seeds
end

function WaypointClustering:getClusterCenter(cluster)
  if #cluster == 0 then return nil end
  
  local centerX, centerY, centerZ = 0, 0, 0
  
  for _, point in ipairs(cluster) do
    centerX = centerX + point.x
    centerY = centerY + point.y
    centerZ = centerZ + (point.z or 7)
  end
  
  return {
    x = centerX / #cluster,
    y = centerY / #cluster,
    z = centerZ / #cluster
  }
end

function WaypointClustering:distance(p1, p2)
  return math.sqrt(
    math.pow(p1.x - p2.x, 2) +
    math.pow(p1.y - p2.y, 2)
  )
end

function WaypointClustering:extractClusterWaypoints(clusters)
  local representatives = {}
  
  for _, cluster in ipairs(clusters) do
    local center = self:getClusterCenter(cluster)
    
    if center then
      table.insert(representatives, {
        x = math.floor(center.x + 0.5),
        y = math.floor(center.y + 0.5),
        z = math.floor(center.z + 0.5)
      })
    end
  end
  
  return representatives
end

function WaypointClustering:tableContains(tbl, value)
  for _, v in ipairs(tbl) do
    if v == value then
      return true
    end
  end
  return false
end

function WaypointClustering:setClusterRadius(radius)
  self.clusterRadius = math.max(2, radius)
end

function WaypointClustering:setMinPoints(minPoints)
  self.minPointsPerCluster = math.max(2, minPoints)
end

return WaypointClustering
