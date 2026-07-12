local Queue = dofile("core/containers/queue.lua")

local BFS = {}

function BFS.new(registry, stateMachine)
  return setmetatable({
    registry = registry,
    stateMachine = stateMachine,
    queue = Queue.new(200),
    inFlight = nil,
    generation = 0,
  }, { __index = BFS })
end

function BFS:start(roots)
  self.generation = self.stateMachine.generation
  for _, root in ipairs(roots) do
    local candidate = {
      generation = self.generation,
      identity = root.identity,
      rootKind = root.rootKind,
      parentIdentity = root.parentIdentity or "none",
      slotIndex = root.slotIndex or 0,
      itemType = root.itemType,
      depth = 0,
      state = "queued",
      attempt = 0,
      discoveredAt = os.clock(),
    }
    self.registry:add(candidate)
    self.queue:enqueue(candidate)
  end
end

function BFS:processNext()
  if self.generation ~= self.stateMachine.generation then
    return nil
  end

  if self.queue.size == 0 then
    return nil
  end

  local candidate = self.queue:dequeue()
  if not candidate then return nil end

  candidate.state = "opening"
  self.registry:setState(candidate.identity, "opening")
  self.inFlight = candidate

  return candidate
end

function BFS:onContainerOpened(event)
  if not self.inFlight then return nil end
  if self.inFlight.identity ~= event.identity then return nil end

  self.inFlight.state = "opened"
  self.registry:setState(self.inFlight.identity, "opened")
  local opened = self.inFlight
  self.inFlight = nil

  return opened
end

function BFS:onPageReceived(event)
  return nil
end

function BFS:discoverChildren(parentIdentity, children)
  for _, child in ipairs(children) do
    local candidate = {
      generation = self.generation,
      identity = child.identity,
      rootKind = child.rootKind or "nested",
      parentIdentity = parentIdentity,
      slotIndex = child.slotIndex or 0,
      itemType = child.itemType,
      depth = ((self.registry:get(parentIdentity) or {}).depth or 0) + 1,
      state = "queued",
      attempt = 0,
      discoveredAt = os.clock(),
    }

    if not self.registry:get(candidate.identity) then
      self.registry:add(candidate)
      self.registry:setParent(parentIdentity, candidate.identity)
      self.queue:enqueue(candidate)
    end
  end
end

function BFS:isActive()
  return self.queue.size > 0 or self.inFlight ~= nil
end

function BFS:getQueueSize()
  return self.queue.size
end

return BFS
