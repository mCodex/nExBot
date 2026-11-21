-- bfs.lua
-- Event-driven BFS traversal.  Processes one container at a time.
-- Ownership: queue management, visited set, in-flight tracking, retry counting.
-- Does NOT own: scheduling (Scheduler), identity (Identity), readiness (Readiness).

local Queue    = dofile("core/containers/queue.lua")
local Identity = dofile("core/containers/identity.lua")

local BFS = {}

local MAX_RETRIES = 3

function BFS.new(registry, stateMachine)
  return setmetatable({
    registry     = registry,
    stateMachine = stateMachine,
    queue        = Queue.new(200),
    inFlight     = nil,
    queued       = {},   -- identity → true  (deduplication)
    generation   = 0,
  }, { __index = BFS })
end

-- Seed the BFS with root descriptors.
-- Each root: { rootKind, identity, itemType, slotIndex, item? }
function BFS:start(roots)
  self.generation = self.stateMachine.generation
  self.inFlight   = nil
  self.queued     = {}
  self.queue:clear()

  for _, root in ipairs(roots) do
    self:_enqueueCandidate({
      generation    = self.generation,
      identity      = root.identity,
      rootKind      = root.rootKind,
      parentIdentity= "none",
      slotIndex     = root.slotIndex or 0,
      itemType      = root.itemType,
      item          = root.item,
      depth         = 0,
      state         = "queued",
      attempt       = 0,
      discoveredAt  = os.clock(),
    })
  end
end

-- Dequeue the next candidate to open.  Returns nil when nothing is pending
-- or the generation has changed.
function BFS:processNext()
  if not self:_generationValid() then return nil end
  if self.inFlight then return nil end  -- Already one in flight.

  local candidate = self.queue:dequeue()
  if not candidate then return nil end

  -- Skip stale-generation candidates.
  if candidate.generation ~= self.generation then
    return self:processNext()
  end

  candidate.state = "opening"
  self.registry:setState(candidate.identity, "opening")
  self.inFlight   = candidate
  return candidate
end

-- Call when the client confirms a container was opened.
-- event: { identity, containerId, itemCount, pageCount? }
-- Returns the opened candidate or nil when the event is stale.
function BFS:onContainerOpened(event)
  if not self:_generationValid() then return nil end
  if not self.inFlight then return nil end
  if self.inFlight.identity ~= event.identity then return nil end

  local opened = self.inFlight
  opened.state       = "opened"
  opened.containerId = event.containerId
  opened.pageCount   = event.pageCount or 1
  opened.currentPage = 0
  self.registry:setState(opened.identity, "opened")
  self.inFlight = nil
  return opened
end

-- Call when a page of container content arrives.
-- event: { identity, pageIndex, items[] }
-- Returns the candidate or nil.
function BFS:onPageReceived(event)
  if not self:_generationValid() then return nil end
  local candidate = self.registry:get(event.identity)
  if not candidate then return nil end

  candidate.currentPage = event.pageIndex or candidate.currentPage
  candidate.state       = "indexing"
  self.registry:setState(event.identity, "indexing")
  return candidate
end

-- Mark a candidate as fully inspected (all pages scanned).
function BFS:onInspectionComplete(identity)
  if not self:_generationValid() then return false end
  local candidate = self.registry:get(identity)
  if not candidate then return false end
  candidate.state = "inspected"
  self.registry:setState(identity, "inspected")
  return true
end

-- Record children discovered inside a parent and enqueue unseen ones.
-- parentIdentity : physical identity string of the parent
-- children       : list of { identity, rootKind, itemType, slotIndex, item? }
function BFS:discoverChildren(parentIdentity, children)
  if not self:_generationValid() then return end
  local parent = self.registry:get(parentIdentity)
  local parentDepth = parent and parent.depth or 0

  for _, child in ipairs(children) do
    if not self.queued[child.identity] and not self.registry:get(child.identity) then
      local candidate = {
        generation    = self.generation,
        identity      = child.identity,
        rootKind      = child.rootKind or "nested",
        parentIdentity= parentIdentity,
        slotIndex     = child.slotIndex or 0,
        itemType      = child.itemType,
        item          = child.item,
        depth         = parentDepth + 1,
        state         = "queued",
        attempt       = 0,
        discoveredAt  = os.clock(),
      }
      self.registry:add(candidate)
      self.registry:setParent(parentIdentity, candidate.identity)
      self:_enqueueCandidate(candidate)
    end
  end
end

-- Re-enqueue a candidate for retry (increments attempt counter).
-- Returns false when max retries are exhausted.
function BFS:retry(identity)
  if not self:_generationValid() then return false end
  local candidate = self.registry:get(identity)
  if not candidate then return false end

  candidate.attempt = (candidate.attempt or 0) + 1
  if candidate.attempt > MAX_RETRIES then
    candidate.state = "failed"
    self.registry:setState(identity, "failed")
    return false
  end

  candidate.state = "queued"
  self.registry:setState(identity, "queued")
  -- Clear dedup guard so the identity can be re-enqueued.
  self.queued[identity] = nil
  self:_enqueueCandidate(candidate)
  return true
end

-- Mark a candidate as permanently failed (no retry).
function BFS:markFailed(identity)
  local candidate = self.registry:get(identity)
  if candidate then
    candidate.state = "failed"
    self.registry:setState(identity, "failed")
  end
  if self.inFlight and self.inFlight.identity == identity then
    self.inFlight = nil
  end
end

function BFS:isActive()
  return self.queue.size > 0 or self.inFlight ~= nil
end

function BFS:getQueueSize()
  return self.queue.size
end

function BFS:_generationValid()
  return self.generation == self.stateMachine.generation
end

function BFS:_enqueueCandidate(candidate)
  if self.queued[candidate.identity] then return false end
  self.queued[candidate.identity] = true
  -- Ensure the node is in the registry so state lookups work.
  if not self.registry:get(candidate.identity) then
    self.registry:add(candidate)
  end
  return self.queue:enqueue(candidate)
end

return BFS

