--[[
  NexBot Waypoint Recorder
  Passive movement tracking for route learning
  
  Author: NexBot Team
  Version: 1.0.0
]]

local WaypointRecorder = {
  recordingEnabled = true,
  recordedPoints = {},
  lastRecordedPos = nil,
  minDistanceBetweenPoints = 1,
  recordingInterval = 500,
  lastRecordTime = 0
}

function WaypointRecorder:new()
  local instance = {
    recordingEnabled = true,
    recordedPoints = {},
    lastRecordedPos = nil,
    minDistanceBetweenPoints = 1,
    recordingInterval = 500,
    lastRecordTime = 0
  }
  setmetatable(instance, { __index = self })
  return instance
end

function WaypointRecorder:shouldRecordPoint()
  local currentTime = now or os.time() * 1000
  if (currentTime - self.lastRecordTime) < self.recordingInterval then
    return false
  end
  
  local playerPos = pos()
  if not playerPos then return false end
  
  if not self.lastRecordedPos then
    self.lastRecordedPos = playerPos
    return true
  end
  
  local distance = math.sqrt(
    math.pow(playerPos.x - self.lastRecordedPos.x, 2) +
    math.pow(playerPos.y - self.lastRecordedPos.y, 2)
  )
  
  return distance >= self.minDistanceBetweenPoints
end

function WaypointRecorder:recordPoint()
  if not self.recordingEnabled then return false end
  if not self:shouldRecordPoint() then return false end
  
  local playerPos = pos()
  if not playerPos then return false end
  
  local currentTime = now or os.time() * 1000
  
  table.insert(self.recordedPoints, {
    x = playerPos.x,
    y = playerPos.y,
    z = playerPos.z,
    timestamp = currentTime
  })
  
  self.lastRecordedPos = playerPos
  self.lastRecordTime = currentTime
  
  return true
end

function WaypointRecorder:getRecordedPoints()
  return self.recordedPoints
end

function WaypointRecorder:clearRecording()
  self.recordedPoints = {}
  self.lastRecordedPos = nil
end

function WaypointRecorder:getRecordingDuration()
  if #self.recordedPoints < 2 then return 0 end
  
  local firstPoint = self.recordedPoints[1]
  local lastPoint = self.recordedPoints[#self.recordedPoints]
  
  return (lastPoint.timestamp - firstPoint.timestamp) / 1000
end

function WaypointRecorder:getPointCount()
  return #self.recordedPoints
end

function WaypointRecorder:setMinDistance(distance)
  self.minDistanceBetweenPoints = math.max(1, distance)
end

function WaypointRecorder:setRecordingInterval(interval)
  self.recordingInterval = math.max(100, interval)
end

function WaypointRecorder:toggle()
  self.recordingEnabled = not self.recordingEnabled
  return self.recordingEnabled
end

return WaypointRecorder
