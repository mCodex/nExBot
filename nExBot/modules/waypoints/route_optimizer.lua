--[[
  NexBot Route Optimizer
  Path smoothing and optimization using Douglas-Peucker and Catmull-Rom
  
  Author: NexBot Team
  Version: 1.0.0
]]

local RouteOptimizer = {
  smoothingFactor = 0.7,
  maxWaypointDistance = 8,
  minWaypointDistance = 2,
  simplificationTolerance = 1.0
}

function RouteOptimizer:new()
  local instance = {
    smoothingFactor = 0.7,
    maxWaypointDistance = 8,
    minWaypointDistance = 2,
    simplificationTolerance = 1.0
  }
  setmetatable(instance, { __index = self })
  return instance
end

function RouteOptimizer:optimizeRoute(waypoints)
  if #waypoints < 2 then return waypoints end
  
  -- Step 1: Remove collinear points (Douglas-Peucker simplification)
  local simplified = self:simplifyRoute(waypoints)
  
  -- Step 2: Smooth the path (Catmull-Rom splines)
  local smoothed = self:smoothPath(simplified)
  
  -- Step 3: Validate path is walkable
  local validated = self:validatePath(smoothed)
  
  -- Step 4: Merge close points
  local merged = self:mergeClosePoints(validated)
  
  return merged
end

function RouteOptimizer:simplifyRoute(waypoints)
  if #waypoints <= 2 then return waypoints end
  
  local dmax = 0
  local index = 0
  
  for i = 2, #waypoints - 1 do
    local d = self:perpendicularDistance(waypoints[i], waypoints[1], waypoints[#waypoints])
    
    if d > dmax then
      index = i
      dmax = d
    end
  end
  
  if dmax > self.simplificationTolerance then
    local left = self:simplifyRoute(self:tableSlice(waypoints, 1, index))
    local right = self:simplifyRoute(self:tableSlice(waypoints, index, #waypoints))
    
    local result = {}
    for _, p in ipairs(left) do table.insert(result, p) end
    for i = 2, #right do table.insert(result, right[i]) end
    
    return result
  else
    return {waypoints[1], waypoints[#waypoints]}
  end
end

function RouteOptimizer:perpendicularDistance(point, lineStart, lineEnd)
  local dx = lineEnd.x - lineStart.x
  local dy = lineEnd.y - lineStart.y
  
  if dx == 0 and dy == 0 then
    return math.sqrt(
      math.pow(point.x - lineStart.x, 2) +
      math.pow(point.y - lineStart.y, 2)
    )
  end
  
  local t = ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) /
            (dx * dx + dy * dy)
  
  t = math.max(0, math.min(1, t))
  
  local nearestX = lineStart.x + t * dx
  local nearestY = lineStart.y + t * dy
  
  return math.sqrt(
    math.pow(point.x - nearestX, 2) +
    math.pow(point.y - nearestY, 2)
  )
end

function RouteOptimizer:smoothPath(waypoints)
  if #waypoints < 4 then return waypoints end
  
  local smoothed = {waypoints[1]}
  
  for i = 2, #waypoints - 2 do
    local p0 = waypoints[i - 1]
    local p1 = waypoints[i]
    local p2 = waypoints[i + 1]
    local p3 = waypoints[i + 2]
    
    for t = 0, 1, 0.5 do
      local x = self:catmullRom(p0.x, p1.x, p2.x, p3.x, t)
      local y = self:catmullRom(p0.y, p1.y, p2.y, p3.y, t)
      
      table.insert(smoothed, {
        x = math.floor(x + 0.5),
        y = math.floor(y + 0.5),
        z = p1.z or 7
      })
    end
  end
  
  table.insert(smoothed, waypoints[#waypoints])
  
  return smoothed
end

function RouteOptimizer:catmullRom(p0, p1, p2, p3, t)
  local t2 = t * t
  local t3 = t2 * t
  
  return 0.5 * (
    2 * p1 +
    (-p0 + p2) * t +
    (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
    (-p0 + 3 * p1 - 3 * p2 + p3) * t3
  )
end

function RouteOptimizer:validatePath(waypoints)
  local validated = {}
  
  for _, waypoint in ipairs(waypoints) do
    local isValid = true
    
    if g_map then
      local tile = g_map.getTile(waypoint)
      isValid = tile and tile:isWalkable()
    end
    
    if isValid then
      table.insert(validated, waypoint)
    end
  end
  
  return validated
end

function RouteOptimizer:mergeClosePoints(waypoints)
  local merged = {}
  
  for _, point in ipairs(waypoints) do
    if #merged == 0 then
      table.insert(merged, point)
    else
      local lastPoint = merged[#merged]
      local dist = math.sqrt(
        math.pow(point.x - lastPoint.x, 2) +
        math.pow(point.y - lastPoint.y, 2)
      )
      
      if dist >= self.minWaypointDistance then
        table.insert(merged, point)
      end
    end
  end
  
  return merged
end

function RouteOptimizer:tableSlice(tbl, first, last)
  local sliced = {}
  for i = first, last do
    if tbl[i] then
      table.insert(sliced, tbl[i])
    end
  end
  return sliced
end

function RouteOptimizer:setTolerance(tolerance)
  self.simplificationTolerance = math.max(0.5, tolerance)
end

function RouteOptimizer:setMinDistance(distance)
  self.minWaypointDistance = math.max(1, distance)
end

return RouteOptimizer
