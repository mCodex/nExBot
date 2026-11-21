IntelligenceCaveBotRouteState = {}
IntelligenceCaveBotRouteState.__index = IntelligenceCaveBotRouteState

function IntelligenceCaveBotRouteState.new()
  return setmetatable({
    state = "idle",
    generation = 0,
    waypoints = {},
    waypointIndex = 0,
  }, IntelligenceCaveBotRouteState)
end

function IntelligenceCaveBotRouteState:start(waypoints)
  assert(type(waypoints) == "table" and #waypoints > 0, "route requires waypoints")
  self.generation = self.generation + 1
  self.waypoints = {}
  for index, waypoint in ipairs(waypoints) do self.waypoints[index] = waypoint end
  self.waypointIndex = 1
  self.state = "running"
  self.pauseReason = nil
  return self.generation
end

function IntelligenceCaveBotRouteState:currentWaypoint()
  return self.waypoints[self.waypointIndex]
end

function IntelligenceCaveBotRouteState:pause(reason)
  if self.state ~= "running" and self.state ~= "recovering" then return false end
  self.state = "paused"
  self.pauseReason = reason
  return true
end

function IntelligenceCaveBotRouteState:resume()
  if self.state ~= "paused" then return false end
  self.state = "running"
  self.pauseReason = nil
  return true
end

function IntelligenceCaveBotRouteState:applyOutcome(generation, outcome)
  if generation ~= self.generation then return false, "stale_route_generation" end

  if outcome == "waypoint_reached" and self.state == "running" then
    self.waypointIndex = self.waypointIndex + 1
    self.state = self.waypointIndex > #self.waypoints and "completed" or "running"
    return true
  end
  if outcome == "path_failed" and self.state == "running" then
    self.state = "recovering"
    return true
  end
  if outcome == "recovery_succeeded" and self.state == "recovering" then
    self.state = "running"
    return true
  end
  if outcome == "recovery_failed" and self.state == "recovering" then
    self.state = "paused"
    self.pauseReason = "recovery_failed"
    return true
  end
  return false, "invalid_route_transition"
end

return IntelligenceCaveBotRouteState
