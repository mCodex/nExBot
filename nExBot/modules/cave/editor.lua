--[[
  CaveBot Editor
  
  Visual waypoint editor for CaveBot.
  
  Author: nExBot Team
  Version: 1.0.0
]]

-- Editor state
local editorState = {
  recording = false,
  selectedWaypoint = nil,
  editMode = false
}

-- Editor UI
UI.Separator()
UI.Label("Waypoint Editor")

local editorPanel = setupUI([[
Panel
  height: 60

  Button
    id: record
    anchors.top: parent.top
    anchors.left: parent.left
    width: 60
    text: Record

  Button
    id: stop
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 3
    width: 50
    text: Stop

  Button
    id: clear
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 3
    width: 50
    text: Clear

  Label
    id: status
    anchors.top: prev.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    margin-top: 5
    text: Waypoints: 0

  Button
    id: addWalk
    anchors.top: prev.bottom
    anchors.left: parent.left
    margin-top: 5
    width: 50
    text: Walk

  Button
    id: addStand
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 3
    width: 50
    text: Stand

  Button
    id: addLabel
    anchors.top: prev.top
    anchors.left: prev.right
    margin-left: 3
    width: 50
    text: Label

]])

-- Update status
local function updateStatus()
  local count = CaveBot.getWaypointCount()
  editorPanel.status:setText("Waypoints: " .. count)
end
updateStatus()

-- Record button
editorPanel.record.onClick = function()
  editorState.recording = true
  editorPanel.record:setColor("green")
  logInfo("[CaveBot Editor] Recording started")
end

-- Stop button
editorPanel.stop.onClick = function()
  editorState.recording = false
  editorPanel.record:setColor("white")
  logInfo("[CaveBot Editor] Recording stopped")
end

-- Clear button
editorPanel.clear.onClick = function()
  CaveBot.clearWaypoints()
  updateStatus()
  logInfo("[CaveBot Editor] Waypoints cleared")
end

-- Add walk waypoint
editorPanel.addWalk.onClick = function()
  CaveBot.addWaypoint(CaveBot.WaypointTypes.WALK, {
    pos = player:getPosition()
  })
  updateStatus()
end

-- Add stand waypoint
editorPanel.addStand.onClick = function()
  CaveBot.addWaypoint(CaveBot.WaypointTypes.STAND, {
    pos = player:getPosition()
  })
  updateStatus()
end

-- Add label waypoint
editorPanel.addLabel.onClick = function()
  -- Simple prompt for label name
  local labelName = "label_" .. CaveBot.getWaypointCount()
  CaveBot.addWaypoint(CaveBot.WaypointTypes.LABEL, {
    pos = player:getPosition(),
    name = labelName
  })
  updateStatus()
end

-- Auto-record on walk
local lastRecordedPos = nil
macro(200, function()
  if not editorState.recording then return end
  
  local currentPos = player:getPosition()
  
  if not lastRecordedPos or 
     currentPos.x ~= lastRecordedPos.x or 
     currentPos.y ~= lastRecordedPos.y or 
     currentPos.z ~= lastRecordedPos.z then
    
    CaveBot.addWaypoint(CaveBot.WaypointTypes.WALK, {
      pos = currentPos
    })
    lastRecordedPos = currentPos
    updateStatus()
  end
end)

-- Editor public API
CaveBot.Editor = {
  isRecording = function()
    return editorState.recording
  end,
  
  startRecording = function()
    editorState.recording = true
    editorPanel.record:setColor("green")
  end,
  
  stopRecording = function()
    editorState.recording = false
    editorPanel.record:setColor("white")
  end,
  
  selectWaypoint = function(index)
    editorState.selectedWaypoint = index
  end,
  
  getSelectedWaypoint = function()
    return editorState.selectedWaypoint
  end
}
