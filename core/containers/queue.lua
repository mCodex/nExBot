local Queue = {}
Queue.__index = Queue

function Queue.new(maxSize)
  return setmetatable({
    head = 1,
    tail = 0,
    size = 0,
    maxSize = maxSize or 100,
    items = {},
  }, Queue)
end

function Queue:enqueue(item)
  if self.size >= self.maxSize then return false end
  self.tail = self.tail + 1
  self.items[self.tail] = item
  self.size = self.size + 1
  return true
end

function Queue:dequeue()
  if self.size == 0 then return nil end
  local item = self.items[self.head]
  self.items[self.head] = nil
  self.head = self.head + 1
  self.size = self.size - 1
  return item
end

function Queue:peek()
  if self.size == 0 then return nil end
  return self.items[self.head]
end

function Queue:compact()
  local new = {}
  for i = self.head, self.tail do
    new[#new + 1] = self.items[i]
    self.items[i] = nil
  end
  self.items = new
  self.head = 1
  self.tail = #new
  self.size = #new
end

function Queue:clear()
  self.items = {}
  self.head = 1
  self.tail = 0
  self.size = 0
end

return Queue
