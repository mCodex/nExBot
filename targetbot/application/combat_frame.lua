CombatFrameRecorder = {}
CombatFrameRecorder.__index = CombatFrameRecorder

local MAX_FRAMES = 256
local _frames = {}
local _frameCount = 0
local _writeIndex = 0
local _tickId = 0
local _currentFrame = nil

function CombatFrameRecorder.new()
  _frames = {}
  _frameCount = 0
  _writeIndex = 0
  _tickId = 0
  _currentFrame = nil
  return setmetatable({}, CombatFrameRecorder)
end

function CombatFrameRecorder:begin(context)
  _tickId = _tickId + 1
  _currentFrame = {
    tickId = _tickId,
    timestamp = context and context.timestamp or 0,
    playerState = context and context.playerState or nil,
    currentTarget = context and context.currentTarget or nil,
    targetCommitment = context and context.targetCommitment or nil,
    candidateTargets = {},
    reachabilityResults = {},
    attackStateBefore = context and context.attackStateBefore or nil,
    tacticalStates = context and context.tacticalStates or {},
    movementIntents = {},
    selectedTarget = nil,
    selectedMovementIntent = nil,
    attackStateAfter = nil,
    rejectedIntents = {},
    mlPredictions = {},
    reasonCodes = {},
    durationMs = 0,
  }
  return _currentFrame
end

function CombatFrameRecorder:record(key, value)
  if not _currentFrame then return end
  if key == "candidate" then
    _currentFrame.candidateTargets[#_currentFrame.candidateTargets + 1] = value
  elseif key == "reachability" then
    _currentFrame.reachabilityResults[#_currentFrame.reachabilityResults + 1] = value
  elseif key == "movementIntent" then
    _currentFrame.movementIntents[#_currentFrame.movementIntents + 1] = value
  elseif key == "rejectedIntent" then
    _currentFrame.rejectedIntents[#_currentFrame.rejectedIntents + 1] = value
  elseif key == "mlPrediction" then
    _currentFrame.mlPredictions[#_currentFrame.mlPredictions + 1] = value
  elseif key == "reasonCode" then
    _currentFrame.reasonCodes[#_currentFrame.reasonCodes + 1] = value
  else
    _currentFrame[key] = value
  end
end

function CombatFrameRecorder:finish(context)
  if not _currentFrame then return nil end
  if context then
    if context.selectedTarget then _currentFrame.selectedTarget = context.selectedTarget end
    if context.selectedMovementIntent then _currentFrame.selectedMovementIntent = context.selectedMovementIntent end
    if context.attackStateAfter then _currentFrame.attackStateAfter = context.attackStateAfter end
    if context.durationMs then _currentFrame.durationMs = context.durationMs end
  end
  _writeIndex = (_writeIndex % MAX_FRAMES) + 1
  _frames[_writeIndex] = _currentFrame
  if _frameCount < MAX_FRAMES then _frameCount = _frameCount + 1 end
  local frame = _currentFrame
  _currentFrame = nil
  return frame
end

function CombatFrameRecorder:getRecent(n)
  n = math.min(n or 10, _frameCount)
  local result = {}
  for i = 0, n - 1 do
    local idx = ((_writeIndex - 1 - i + MAX_FRAMES) % MAX_FRAMES) + 1
    if _frames[idx] then result[#result + 1] = _frames[idx] end
  end
  return result
end

function CombatFrameRecorder:getCount()
  return _frameCount
end

function CombatFrameRecorder:reset()
  _frames = {}
  _frameCount = 0
  _writeIndex = 0
  _tickId = 0
  _currentFrame = nil
end

return CombatFrameRecorder
