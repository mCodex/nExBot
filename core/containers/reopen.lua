-- One outstanding use or page request: OTClient assigns the first free window
-- number at send time and only reserves it when the server replies.
local Queue = ...
local Reopen = {}
local active
local advance
local OPEN_INTERVAL = 200
local ACK_TIMEOUT = 2000

local function firstIndex(container)
  return container.getFirstIndex and container:getFirstIndex() or 0
end

local function finish(run, reason)
  active = nil
  if reason then warn("[Container Panel] " .. reason) end
  if run.failed > 0 then
    warn("[Container Panel] Reopen All: " .. run.failed .. " bag or page request(s) could not be completed.")
  end
  local complete = not reason and run.failed == 0
  for _, callback in ipairs(run.callbacks) do callback(complete) end
  if EventBus and EventBus.emit then
    EventBus.emit(complete and "containers:open_all_complete" or "containers:open_all_incomplete")
  end
end

local function enqueueItem(run, node, item, slot)
  if item:isContainer() and not node.items[item] then
    node.items[item] = true
    node.queue:enqueue({node = node, item = item, slot = slot, page = firstIndex(node.container)})
  end
end

local function scan(run, container, node)
  if run.exclude(container:getName()) then return end
  node = node or {pages = {}}
  local rule = run.rule(container:getContainerItem():getId())
  node.queue = rule and rule.openNested and run.priority or run.queue
  node.container = container
  node.items = {}
  run.nodes[container:getId()] = node
  local page = firstIndex(container)
  node.pages[page] = true
  for slot, item in ipairs(container:getItems()) do enqueueItem(run, node, item, slot) end

  if container.hasPages and container:hasPages() then
    local capacity = container:getCapacity()
    if capacity > 0 then
      local nextPage = page + capacity
      if nextPage >= container:getSize() then nextPage = 0 end
      if not node.pages[nextPage] then
        run.pages:enqueue({node = node, target = nextPage})
      end
    end
  end
end

local function resolveItem(job)
  if job.root then return job.root() end
  local parent = job.node.container
  if g_game.getContainer(parent:getId()) ~= parent or firstIndex(parent) ~= job.page then return end
  -- An inventory update may shift two identical backpacks into different slots.
  if parent:getItem(job.slot - 1) == job.item then return job.item end
  for _, item in ipairs(parent:getItems()) do
    if item == job.item then return item end
  end
end

local function wake(run)
  if run.scheduled then return end
  run.scheduled = true
  schedule(math.max(1, run.nextSend - g_clock.millis()), function()
    if active ~= run then return end
    run.scheduled = false
    advance(run)
  end)
end

local function send(run, job, item)
  local pending = {job = job}
  run.pending = pending
  run.nextSend = g_clock.millis() + OPEN_INTERVAL
  if job.target then
    g_game.seekInContainer(job.node.container:getId(), job.target)
  else
    pending.itemId = item:getId()
    pending.window = g_game.open(item)
  end

  schedule(ACK_TIMEOUT, function()
    if active ~= run or run.pending ~= pending then return end
    run.pending = nil
    if not job.retried then
      job.retried = true
      run.retry = job
    else
      run.failed = run.failed + 1
    end
    wake(run)
  end)
end

advance = function(run)
  if run.pending or run.closing then return end
  while true do
    -- Drain visible bags before seeking away from their page.
    local job = run.retry or run.priority:dequeue() or run.queue:dequeue() or run.pages:dequeue()
    run.retry = nil
    if not job then
      finish(run)
      return
    end
    if job.target then
      local parent = job.node.container
      if g_game.getContainer(parent:getId()) == parent then
        send(run, job)
        return
      end
    else
      local item = resolveItem(job)
      if item then
        send(run, job, item)
        return
      end
    end
    if not job.optional then run.failed = run.failed + 1 end
  end
end

function Reopen.onOpen(container, previous)
  local run = active
  local pending = run and run.pending
  if not pending then return end
  local job = pending.job
  if job.target then
    if job.node.container:getId() ~= container:getId() or firstIndex(container) ~= job.target
        or (previous and previous ~= job.node.container) then return end
    scan(run, container, job.node)
  else
    local item = container:getContainerItem()
    if previous or not item or item:getId() ~= pending.itemId then return end
    if pending.window ~= nil and pending.window ~= container:getId() then return end
    scan(run, container)
  end
  run.pending = nil
  wake(run)
end

function Reopen.onClose(container)
  local run = active
  if not run then return end
  local id = container:getId()
  if run.closing and run.closing[id] == container then
    run.closing[id] = nil
    run.closeCount = run.closeCount - 1
    if run.closeCount == 0 then
      run.closing = nil
      wake(run)
    end
  end
  local node = run.nodes[id]
  if node and node.container == container then run.nodes[id] = nil end
end

function Reopen.onAdd(container, item, slot)
  local run = active
  local node = run and run.nodes[container:getId()]
  if node and node.container == container then enqueueItem(run, node, item, slot + 1) end
end

function Reopen.isActive()
  return active ~= nil
end

function Reopen.cancel()
  if active then finish(active, "Reopen All cancelled.") end
end

function Reopen.start(roots, exclude, rule, callback)
  if active then
    if callback then active.callbacks[#active.callbacks + 1] = callback end
    return
  end
  local run = {
    queue = Queue.new(math.huge), priority = Queue.new(math.huge), pages = Queue.new(math.huge),
    nodes = {}, nextSend = 0, failed = 0, callbacks = {callback}, exclude = exclude, rule = rule,
  }
  for _, root in ipairs(roots) do run.queue:enqueue(root) end
  active = run
  if EventBus and EventBus.emit then EventBus.emit("containers:close_all") end
  local open = g_game.getContainers()
  local closing = {}
  run.closeCount = 0
  for _, container in pairs(open) do
    closing[container:getId()] = container
    run.closeCount = run.closeCount + 1
  end
  if run.closeCount == 0 then
    wake(run)
    return
  end
  run.closing = closing
  for _, container in pairs(open) do g_game.close(container) end
  schedule(ACK_TIMEOUT, function()
    if active == run and run.closing then finish(run, "Timed out waiting for open containers to close.") end
  end)
end

return Reopen
