--[[
  navigation/recorder.lua — Auto Recorder (T3).

  Records acknowledged positions into a route graph as the player walks under
  session control. Direction-change / max-distance / floor-change anchors
  mirror the v2 recorder, but the OUTPUT is a strict route graph (nodes +
  edges) for the Session — never a raw goto stream.

  Consumption: Session emits acknowledged movement (position + optional
  turn/floorChange signal); Recorder.record(pos, opts) appends and may emit a
  new route when a corner or transition is reached.

  Pure Lua; no OTClient globals.
]]

local RouteGraph = require("navigation.route_graph")
local D = require("navigation.domain")

local Recorder = {}

local CONFIG = {
  maxStraightDist = 15,
  minRecordDist = 3,
  turnConfirmSteps = 1,
  collinearTolerance = 0.15,
}

local function euclideanDist(a, b)
  local dx, dy = a.x - b.x, a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function stepDirection(fromPos, toPos)
  local dx, dy = toPos.x - fromPos.x, toPos.y - fromPos.y
  local nx = dx == 0 and 0 or (dx > 0 and 1 or -1)
  local ny = dy == 0 and 0 or (dy > 0 and 1 or -1)
  return nx .. "," .. ny
end

local function new()
  local self = setmetatable({}, { __index = Recorder })
  self.waypoints = {}       -- list of "x,y,z[,marker]" strings (legacy shape)
  self.prevRecorded = nil
  self.lastPos = nil
  self.prevStepPos = nil
  self.prevDirection = nil
  self.stepsSinceLast = 0
  self.pendingCorner = nil
  self.pendingTurnDir = nil
  self.pendingTurnCount = 0
  self.lastRoute = nil
  return self
end
Recorder.new = new

function Recorder:_push(pos, marker)
  local wp = pos.x .. "," .. pos.y .. "," .. pos.z
  if marker then wp = wp .. "," .. marker end
  self.waypoints[#self.waypoints + 1] = wp
  self.prevRecorded = self.lastPos and D.copyPos(self.lastPos) or nil
  self.lastPos = D.copyPos(pos)
  self.stepsSinceLast = 0
end

-- Record an acknowledged position. opts:
--   * floorChange (bool)  -> record an anchor on the new floor (transition).
--   * turn signal derived from direction change against prevStepPos.
function Recorder:record(pos, opts)
  opts = opts or {}
  if not pos or not pos.x then return nil end

  -- Floor change / teleport: record immediately on the new floor.
  if opts.floorChange then
    self:_push(pos, "stairs")
    self.prevStepPos = D.copyPos(pos)
    self.prevDirection = nil
    return self:route()
  end

  -- Turn detection: record at the LAST position before a confirmed turn.
  local dir = self.prevStepPos and stepDirection(self.prevStepPos, pos) or nil
  if self.prevDirection and dir then
    if self.pendingTurnDir then
      -- Mid-turn: waiting for turnConfirmSteps steps in the new direction.
      if dir == self.pendingTurnDir then
        self.pendingTurnCount = self.pendingTurnCount + 1
        if self.pendingTurnCount >= CONFIG.turnConfirmSteps then
          self:_push(self.pendingCorner)
          self.pendingTurnDir, self.pendingTurnCount, self.pendingCorner = nil, 0, nil
        end
      else
        self.pendingTurnDir, self.pendingTurnCount, self.pendingCorner = nil, 0, nil
      end
    elseif dir ~= self.prevDirection then
      self.pendingCorner = D.copyPos(self.prevStepPos)
      self.pendingTurnDir = dir
      self.pendingTurnCount = 0
    end
  end
  self.prevDirection = dir
  self.prevStepPos = D.copyPos(pos)

  -- Max straight distance.
  if self.lastPos then
    if euclideanDist(self.lastPos, pos) >= CONFIG.maxStraightDist then
      self:_push(pos)
    end
  else
    self:_push(pos)
  end

  return self:route()
end

function Recorder:route()
  if #self.waypoints < 2 then return nil end
  local built = RouteGraph.fromWaypoints(self.waypoints)
  if built then
    built.id = "recorded-" .. (self.revision or 0)
    self.lastRoute = built
    self.revision = (self.revision or 0) + 1
  end
  return self.lastRoute
end

function Recorder:reset()
  self.waypoints = {}
  self.prevRecorded = nil
  self.lastPos = nil
  self.prevStepPos = nil
  self.prevDirection = nil
  self.stepsSinceLast = 0
  self.pendingCorner = nil
  self.pendingTurnDir = nil
  self.pendingTurnCount = 0
  self.lastRoute = nil
end

function Recorder:snapshot()
  return {
    waypointCount = #self.waypoints,
    lastPos = self.lastPos and D.copyPos(self.lastPos) or nil,
    revision = self.revision or 0,
  }
end

if nExBot and nExBot.Nav then nExBot.Nav["navigation.recorder"] = Recorder end
return Recorder