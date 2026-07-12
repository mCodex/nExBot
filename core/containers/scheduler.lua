local Queue = dofile("core/containers/queue.lua")

local Scheduler = {}

function Scheduler.new()
  return setmetatable({
    queue = Queue.new(100),
    lastActionTime = 0,
    cooldownMs = 200,
    priority = 25,
    enabled = true,
  }, { __index = Scheduler })
end

function Scheduler:enqueue(action)
  return self.queue:enqueue(action)
end

function Scheduler:canRun()
  if not self.enabled then return false end
  if self.lastActionTime == 0 then return true end
  local now = os.clock() * 1000
  return (now - self.lastActionTime) >= self.cooldownMs
end

function Scheduler:processNext()
  if not self:canRun() then return nil end
  local action = self.queue:dequeue()
  if action then
    self.lastActionTime = os.clock() * 1000
  end
  return action
end

function Scheduler:getQueueSize()
  return self.queue.size
end

function Scheduler:clear()
  self.queue:clear()
end

return Scheduler
