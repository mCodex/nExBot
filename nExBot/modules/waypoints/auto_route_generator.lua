--[[
  NexBot Auto Route Generator
  Complete auto-generation pipeline for routes
  
  Author: NexBot Team
  Version: 1.0.0
]]

local WaypointRecorder = dofile("/NexBot/modules/waypoints/waypoint_recorder.lua")
local AutoDiscovery = dofile("/NexBot/modules/waypoints/auto_discovery.lua")
local RouteOptimizer = dofile("/NexBot/modules/waypoints/route_optimizer.lua")
local PathPredictor = dofile("/NexBot/modules/waypoints/path_predictor.lua")
local WaypointClustering = dofile("/NexBot/modules/waypoints/waypoint_clustering.lua")

local AutoRouteGenerator = {
  recorder = nil,
  discovery = nil,
  optimizer = nil,
  predictor = nil,
  clustering = nil,
  autoRouteName = "AutoRoute",
  isRecording = false,
  generatedRoutes = {}
}

function AutoRouteGenerator:new()
  local instance = {
    recorder = WaypointRecorder:new(),
    discovery = AutoDiscovery:new(),
    optimizer = RouteOptimizer:new(),
    predictor = PathPredictor:new(),
    clustering = WaypointClustering:new(),
    autoRouteName = "AutoRoute",
    isRecording = false,
    generatedRoutes = {}
  }
  setmetatable(instance, { __index = self })
  return instance
end

function AutoRouteGenerator:startAutoRecording()
  self.recorder.recordingEnabled = true
  self.recorder:clearRecording()
  self.isRecording = true
  
  if logInfo then
    logInfo("[AutoRoute] Recording started - walk your route")
  end
  
  return true
end

function AutoRouteGenerator:stopAutoRecording()
  self.isRecording = false
  
  if logInfo then
    logInfo("[AutoRoute] Recording stopped - generating route...")
  end
  
  return self:generateRouteFromRecording()
end

function AutoRouteGenerator:generateRouteFromRecording()
  local rawPoints = self.recorder:getRecordedPoints()
  
  if #rawPoints < 5 then
    if logInfo then
      logInfo("[AutoRoute] Need at least 5 waypoints!")
    end
    return nil
  end
  
  if logInfo then
    logInfo(string.format("[AutoRoute] Processing %d recorded points...", #rawPoints))
  end
  
  -- Step 1: Cluster raw points
  local clusters = self.clustering:clusterByLocation(rawPoints, math.min(10, math.ceil(#rawPoints / 5)))
  
  if logInfo then
    logInfo(string.format("[AutoRoute] Clustered into %d areas", #clusters))
  end
  
  -- Step 2: Extract representative waypoints
  local clusterWaypoints = self.clustering:extractClusterWaypoints(clusters)
  
  if logInfo then
    logInfo(string.format("[AutoRoute] Extracted %d representative waypoints", #clusterWaypoints))
  end
  
  -- Step 3: Optimize route (smooth, simplify)
  local optimized = self.optimizer:optimizeRoute(clusterWaypoints)
  
  if logInfo then
    logInfo(string.format("[AutoRoute] Optimized to %d waypoints", #optimized))
  end
  
  -- Step 4: Merge close points
  local final = self.optimizer:mergeClosePoints(optimized)
  
  if logInfo then
    logInfo(string.format("[AutoRoute] Final route: %d waypoints", #final))
  end
  
  -- Step 5: Record pattern for learning
  self.predictor:recordRoute(final, self.autoRouteName)
  
  -- Store generated route
  table.insert(self.generatedRoutes, {
    name = self.autoRouteName .. "_" .. os.time(),
    waypoints = final,
    createdAt = os.time()
  })
  
  return final
end

function AutoRouteGenerator:analyzeAndRecommend()
  local rawPoints = self.recorder:getRecordedPoints()
  
  if #rawPoints == 0 then
    return {recommendations = {}}
  end
  
  local analysis = self.discovery:discoverFromWaypoints(rawPoints)
  local recommendations = {
    safeZones = #analysis.safe_zones,
    chokepoints = #analysis.chokepoints,
    dangerAreas = #analysis.danger_areas,
    recommendations = {}
  }
  
  if #analysis.danger_areas > 0 then
    table.insert(recommendations.recommendations,
      string.format("⚠️ Found %d danger zones - consider avoiding", #analysis.danger_areas))
  end
  
  if #analysis.safe_zones > 0 then
    table.insert(recommendations.recommendations,
      string.format("✓ Found %d safe zones for efficient farming", #analysis.safe_zones))
  end
  
  if #analysis.chokepoints > 0 then
    table.insert(recommendations.recommendations,
      string.format("⏱ Found %d chokepoints where you stopped frequently", #analysis.chokepoints))
  end
  
  return recommendations
end

function AutoRouteGenerator:predictiveUpdate()
  local points = self.recorder:getRecordedPoints()
  
  if #points < 2 then return nil end
  
  local current = points[#points]
  local previous = points[#points - 1]
  
  return self.predictor:predictNextWaypoint(current, previous)
end

function AutoRouteGenerator:resetRecording()
  self.recorder:clearRecording()
  self.isRecording = false
end

function AutoRouteGenerator:getRecordedPointCount()
  return self.recorder:getPointCount()
end

function AutoRouteGenerator:getRecordingDuration()
  return self.recorder:getRecordingDuration()
end

function AutoRouteGenerator:isCurrentlyRecording()
  return self.isRecording
end

function AutoRouteGenerator:getGeneratedRoutes()
  return self.generatedRoutes
end

function AutoRouteGenerator:getLastRoute()
  if #self.generatedRoutes > 0 then
    return self.generatedRoutes[#self.generatedRoutes]
  end
  return nil
end

function AutoRouteGenerator:update()
  if self.isRecording then
    self.recorder:recordPoint()
  end
end

return AutoRouteGenerator
