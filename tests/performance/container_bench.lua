local Queue = dofile("core/containers/queue.lua")
local Registry = dofile("core/containers/registry.lua")

local function benchQueue()
  local q = Queue.new(1000)
  local start = os.clock()
  for i = 1, 10000 do
    q:enqueue(i)
  end
  for i = 1, 10000 do
    q:dequeue()
  end
  return os.clock() - start
end

local function benchRegistry()
  local reg = Registry.new()
  local start = os.clock()
  for i = 1, 1000 do
    reg:add({ identity = "id_" .. i, state = "discovered", itemType = i % 100 })
  end
  for i = 1, 1000 do
    reg:findByItemType(i % 100)
  end
  return os.clock() - start
end

local function benchRegistryStateTransition()
  local reg = Registry.new()
  for i = 1, 1000 do
    reg:add({ identity = "id_" .. i, state = "discovered", itemType = i % 100 })
  end
  local start = os.clock()
  for i = 1, 1000 do
    reg:setState("id_" .. i, "queued")
  end
  return os.clock() - start
end

print("=== Container Module Benchmarks ===")
print(string.format("Queue (10k enqueue/dequeue):  %.4fs", benchQueue()))
print(string.format("Registry (1k add + lookup):   %.4fs", benchRegistry()))
print(string.format("Registry (1k state transition): %.4fs", benchRegistryStateTransition()))
print("=== Done ===")
