local StateMachine = dofile("core/containers/state_machine.lua")
local Registry = dofile("core/containers/registry.lua")
local BFS = dofile("core/containers/bfs.lua")
local Scheduler = dofile("core/containers/scheduler.lua")
local Quiver = dofile("core/containers/quiver.lua")
local Readiness = dofile("core/containers/readiness.lua")
local ClientAdapter = dofile("core/containers/client_adapter.lua")

local Discovery = {}

function Discovery.new()
  return setmetatable({
    stateMachine = StateMachine.new(),
    registry = Registry.new(),
    bfs = nil,
    scheduler = Scheduler.new(),
    readiness = nil,
    inFlightCount = 0,
  }, { __index = Discovery })
end

function Discovery:start()
  self.stateMachine:transition("waitingForSession")
  self:discoverRoots()
end

function Discovery:discoverRoots()
  self.stateMachine:transition("discoveringRoots")
  
  local roots = {}
  
  local mainBP = self:findMainBackpack()
  if mainBP then
    roots[#roots + 1] = mainBP
  end
  
  local quiverRoot = Quiver.discoverRoot()
  if quiverRoot then
    roots[#roots + 1] = quiverRoot
  end
  
  self.stateMachine:transition("reconciling")
  self:reconcileRoots(roots)
end

function Discovery:findMainBackpack()
  local containers = ClientAdapter.getContainers()
  if containers and #containers > 0 then
    local main = containers[1]
    return {
      rootKind = "mainBackpack",
      identity = "main:" .. main:getId(),
      itemType = main:getId(),
      slotIndex = 0,
    }
  end
  return nil
end

function Discovery:reconcileRoots(roots)
  self.stateMachine:transition("traversing")
  self.bfs = BFS.new(self.registry, self.stateMachine)
  self.bfs:start(roots)
  self:processNext()
end

function Discovery:processNext()
  if self.stateMachine:is("traversing") then
    local candidate = self.bfs:processNext()
    if candidate then
      self.inFlightCount = self.inFlightCount + 1
      self.stateMachine:transition("waitingForAcknowledgement")
      self:sendOpenRequest(candidate)
    else
      self:complete()
    end
  end
end

function Discovery:sendOpenRequest(candidate)
  self.scheduler:enqueue({
    type = "open",
    identity = candidate.identity,
    callback = function()
      ClientAdapter.open(candidate.itemType)
    end,
  })
  local action = self.scheduler:processNext()
  if action and action.callback then
    action.callback()
  end
end

function Discovery:onContainerOpened(event)
  if self.stateMachine:is("waitingForAcknowledgement") then
    self.inFlightCount = math.max(0, self.inFlightCount - 1)
    self.bfs:onContainerOpened(event)
    self.stateMachine:transition("traversing")
    self:processNext()
  end
end

function Discovery:onContainerClosed(event)
end

function Discovery:complete()
  self.stateMachine:transition("completed")
  self.readiness = Readiness.compute(self.registry, self.stateMachine.generation, Quiver.isPaladin())
end

function Discovery:cancel()
  self.stateMachine:transition("cancelled")
  self.scheduler:clear()
end

function Discovery:getState()
  return self.stateMachine.state
end

function Discovery:getReadiness()
  if self.readiness then
    return self.readiness
  end
  return Readiness.compute(self.registry, self.stateMachine.generation, Quiver.isPaladin())
end

return Discovery
