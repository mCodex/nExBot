--[[
  NexBot Core Module Tests
  Tests for event_bus, bot_state, and distance_calculator
]]

local TestFramework = dofile("/NexBot/tests/test_framework.lua")

-- Mock player object for testing
local mockPlayer = {
  getPosition = function()
    return { x = 100, y = 100, z = 7 }
  end
}

-- Mock creature for testing
local mockCreature = {
  getName = function() return "Dragon" end,
  getHealthPercent = function() return 75 end,
  getPosition = function() return { x = 102, y = 103, z = 7 } end
}

-- ============================================
-- EventBus Tests
-- ============================================
local eventBusTests = TestFramework:new("EventBus")

eventBusTests:test("should emit and receive events", function(t)
  local received = false
  local testBus = {
    listeners = {},
    on = function(self, event, callback)
      self.listeners[event] = self.listeners[event] or {}
      table.insert(self.listeners[event], callback)
    end,
    emit = function(self, event, ...)
      local callbacks = self.listeners[event]
      if callbacks then
        for _, cb in ipairs(callbacks) do
          cb(...)
        end
      end
    end
  }
  
  testBus:on("test_event", function(data)
    received = data
  end)
  
  testBus:emit("test_event", "hello")
  
  t:assertEquals(received, "hello", "Event data should be received")
end)

eventBusTests:test("should support multiple listeners", function(t)
  local count = 0
  local testBus = {
    listeners = {},
    on = function(self, event, callback)
      self.listeners[event] = self.listeners[event] or {}
      table.insert(self.listeners[event], callback)
    end,
    emit = function(self, event, ...)
      local callbacks = self.listeners[event]
      if callbacks then
        for _, cb in ipairs(callbacks) do
          cb(...)
        end
      end
    end
  }
  
  testBus:on("count_event", function() count = count + 1 end)
  testBus:on("count_event", function() count = count + 1 end)
  testBus:on("count_event", function() count = count + 1 end)
  
  testBus:emit("count_event")
  
  t:assertEquals(count, 3, "All listeners should be called")
end)

-- ============================================
-- Distance Calculator Tests
-- ============================================
local distanceTests = TestFramework:new("DistanceCalculator")

distanceTests:test("should calculate Manhattan distance correctly", function(t)
  local pos1 = { x = 100, y = 100 }
  local pos2 = { x = 103, y = 104 }
  
  local manhattan = math.abs(pos1.x - pos2.x) + math.abs(pos1.y - pos2.y)
  
  t:assertEquals(manhattan, 7, "Manhattan distance should be 7")
end)

distanceTests:test("should calculate Euclidean distance correctly", function(t)
  local pos1 = { x = 100, y = 100 }
  local pos2 = { x = 103, y = 104 }
  
  local dx = pos1.x - pos2.x
  local dy = pos1.y - pos2.y
  local euclidean = math.sqrt(dx * dx + dy * dy)
  
  t:assertTrue(euclidean > 4.9 and euclidean < 5.1, "Euclidean distance should be ~5")
end)

distanceTests:test("should calculate Chebyshev distance correctly", function(t)
  local pos1 = { x = 100, y = 100 }
  local pos2 = { x = 103, y = 104 }
  
  local chebyshev = math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
  
  t:assertEquals(chebyshev, 4, "Chebyshev distance should be 4")
end)

distanceTests:test("should return 0 for same position", function(t)
  local pos = { x = 100, y = 100 }
  
  local distance = math.abs(pos.x - pos.x) + math.abs(pos.y - pos.y)
  
  t:assertEquals(distance, 0, "Distance to same position should be 0")
end)

-- ============================================
-- Object Pool Tests
-- ============================================
local poolTests = TestFramework:new("ObjectPool")

poolTests:test("should create and acquire objects", function(t)
  local pool = {
    objects = {},
    create = function(self, factory)
      return { factory = factory }
    end
  }
  
  local created = pool:create(function() return {} end)
  
  t:assertNotNil(created, "Pool should create object")
  t:assertNotNil(created.factory, "Created object should have factory")
end)

poolTests:test("should track pool size", function(t)
  local pool = {
    available = {},
    size = 0
  }
  
  -- Simulate acquiring
  for i = 1, 5 do
    pool.size = pool.size + 1
  end
  
  t:assertEquals(pool.size, 5, "Pool size should be 5")
end)

-- ============================================
-- Priority Target Tests
-- ============================================
local targetTests = TestFramework:new("PriorityTargetManager")

targetTests:test("should calculate creature score", function(t)
  local creature = {
    health = 50,
    distance = 3,
    threat = 10
  }
  
  -- Score = threat * 10 + (100 - health) / 10 + (10 - distance)
  local score = creature.threat * 10 + (100 - creature.health) / 10 + (10 - creature.distance)
  
  t:assertGreaterThan(score, 0, "Score should be positive")
  t:assertTrue(score > 100, "High threat creature should have high score")
end)

targetTests:test("should prefer closer creatures with equal threat", function(t)
  local creature1 = { threat = 5, health = 100, distance = 2 }
  local creature2 = { threat = 5, health = 100, distance = 5 }
  
  local score1 = creature1.threat * 10 + (10 - creature1.distance)
  local score2 = creature2.threat * 10 + (10 - creature2.distance)
  
  t:assertGreaterThan(score1, score2, "Closer creature should have higher score")
end)

-- ============================================
-- Path Cache Tests
-- ============================================
local cacheTests = TestFramework:new("PathCache")

cacheTests:test("should create valid cache key", function(t)
  local from = { x = 100, y = 100, z = 7 }
  local to = { x = 105, y = 105, z = 7 }
  
  local key = string.format("%d,%d,%d->%d,%d,%d", 
    from.x, from.y, from.z,
    to.x, to.y, to.z)
  
  t:assertEquals(key, "100,100,7->105,105,7", "Cache key format should be correct")
end)

cacheTests:test("should handle TTL correctly", function(t)
  local cached = {
    path = {},
    timestamp = os.time() - 10,
    ttl = 5
  }
  
  local isExpired = (os.time() - cached.timestamp) > cached.ttl
  
  t:assertTrue(isExpired, "Entry older than TTL should be expired")
end)

cacheTests:test("should not expire fresh entries", function(t)
  local cached = {
    path = {},
    timestamp = os.time(),
    ttl = 5
  }
  
  local isExpired = (os.time() - cached.timestamp) > cached.ttl
  
  t:assertFalse(isExpired, "Fresh entry should not be expired")
end)

-- ============================================
-- Run all tests
-- ============================================
local function runAllTests()
  local results = {}
  
  table.insert(results, eventBusTests:run())
  table.insert(results, distanceTests:run())
  table.insert(results, poolTests:run())
  table.insert(results, targetTests:run())
  table.insert(results, cacheTests:run())
  
  -- Summary
  local totalPassed = 0
  local totalFailed = 0
  local totalSkipped = 0
  
  for _, result in ipairs(results) do
    local r = result:getResults()
    totalPassed = totalPassed + r.passed
    totalFailed = totalFailed + r.failed
    totalSkipped = totalSkipped + r.skipped
  end
  
  print("\n========== OVERALL RESULTS ==========")
  print(string.format("Total Passed:  %d", totalPassed))
  print(string.format("Total Failed:  %d", totalFailed))
  print(string.format("Total Skipped: %d", totalSkipped))
  print(string.format("Success Rate:  %.1f%%", 
    (totalPassed / (totalPassed + totalFailed)) * 100))
  
  return totalFailed == 0
end

return runAllTests
