--[[
  NexBot Path Predictor
  Pattern recognition for common routes using ML-style algorithms
  
  Author: NexBot Team
  Version: 1.0.0
]]

local PathPredictor = {
  recordedRoutes = {},
  routePatterns = {},
  frequencyThreshold = 2
}

function PathPredictor:new()
  local instance = {
    recordedRoutes = {},
    routePatterns = {},
    frequencyThreshold = 2
  }
  setmetatable(instance, { __index = self })
  return instance
end

function PathPredictor:recordRoute(waypoints, routeName)
  if not routeName then
    routeName = string.format("Route_%d", os.time())
  end
  
  local route = {
    name = routeName,
    waypoints = waypoints,
    recordedAt = os.time(),
    completed = false
  }
  
  table.insert(self.recordedRoutes, route)
  self:updatePatterns()
  
  return route
end

function PathPredictor:updatePatterns()
  local routeMap = {}
  
  for _, route in ipairs(self.recordedRoutes) do
    local routeSignature = self:getRouteSignature(route.waypoints)
    
    if not routeMap[routeSignature] then
      routeMap[routeSignature] = 0
    end
    
    routeMap[routeSignature] = routeMap[routeSignature] + 1
  end
  
  self.routePatterns = {}
  
  for signature, frequency in pairs(routeMap) do
    if frequency >= self.frequencyThreshold then
      table.insert(self.routePatterns, {
        signature = signature,
        frequency = frequency
      })
    end
  end
end

function PathPredictor:getRouteSignature(waypoints)
  if #waypoints < 2 then return "" end
  
  local signature = ""
  
  for i = 1, #waypoints - 1 do
    local p1 = waypoints[i]
    local p2 = waypoints[i + 1]
    
    local dx = p2.x - p1.x
    local dy = p2.y - p1.y
    
    local dir = self:quantizeDirection(dx, dy)
    signature = signature .. dir
  end
  
  return signature
end

function PathPredictor:quantizeDirection(dx, dy)
  local angle = math.atan2(dy, dx)
  local direction = math.floor((angle + math.pi) / (math.pi / 4))
  
  return tostring(direction % 8)
end

function PathPredictor:predictNextWaypoint(currentWaypoint, previousWaypoint)
  if not previousWaypoint then return nil end
  
  local vx = currentWaypoint.x - previousWaypoint.x
  local vy = currentWaypoint.y - previousWaypoint.y
  
  local predictedPos = {
    x = currentWaypoint.x + vx,
    y = currentWaypoint.y + vy,
    z = currentWaypoint.z or 7
  }
  
  return self:snapToWalkable(predictedPos)
end

function PathPredictor:snapToWalkable(pos)
  if not g_map then return pos end
  
  local searchRadius = 5
  
  for r = 0, searchRadius do
    for x = pos.x - r, pos.x + r do
      for y = pos.y - r, pos.y + r do
        local tile = g_map.getTile({x = x, y = y, z = pos.z})
        
        if tile and tile:isWalkable() then
          return {x = x, y = y, z = pos.z}
        end
      end
    end
  end
  
  return pos
end

function PathPredictor:getSimilarRoutes(waypoints)
  local signature = self:getRouteSignature(waypoints)
  local similar = {}
  
  for _, route in ipairs(self.recordedRoutes) do
    local routeSig = self:getRouteSignature(route.waypoints)
    
    if self:signaturesSimilar(signature, routeSig) then
      table.insert(similar, route)
    end
  end
  
  return similar
end

function PathPredictor:signaturesSimilar(sig1, sig2)
  if #sig1 ~= #sig2 then return false end
  if #sig1 == 0 then return true end
  
  local matches = 0
  
  for i = 1, #sig1 do
    if string.sub(sig1, i, i) == string.sub(sig2, i, i) then
      matches = matches + 1
    end
  end
  
  local similarity = matches / #sig1
  
  return similarity >= 0.8
end

function PathPredictor:getPatterns()
  return self.routePatterns
end

function PathPredictor:clearPatterns()
  self.recordedRoutes = {}
  self.routePatterns = {}
end

return PathPredictor
