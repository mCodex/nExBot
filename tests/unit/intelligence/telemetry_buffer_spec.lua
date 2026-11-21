local TelemetryBuffer = dofile("core/intelligence/telemetry/buffer.lua")

describe("IntelligenceTelemetryBuffer", function()
  local buffer

  before_each(function()
    buffer = TelemetryBuffer.new({ maxSize = 5 })
  end)

  describe("new", function()
    it("returns an instance with empty tiers and zero counters", function()
      assert.is_not_nil(buffer)
      assert.equals(0, buffer:size())
      local stats = buffer:stats()
      assert.equals(0, stats.size)
      assert.equals(5, stats.capacity)
      assert.equals(0, stats.accepted)
      assert.equals(0, stats.droppedTotal)
      for tier = 0, 4 do
        assert.equals(0, stats.dropped[tier])
      end
    end)

    it("uses default maxSize when not provided", function()
      local defaultBuffer = TelemetryBuffer.new()
      assert.equals(2000, defaultBuffer:stats().capacity)
    end)
  end)

  describe("priorityOf", function()
    it("returns defaultPriority when priorityFor is not configured", function()
      assert.equals(2, buffer:priorityOf("anything"))
    end)

    it("uses priorityFor classifier when configured", function()
      local classified = TelemetryBuffer.new({
        priorityFor = function(eventType)
          if eventType == "critical" then return 0 end
          return 3
        end,
      })
      assert.equals(0, classified:priorityOf("critical"))
      assert.equals(3, classified:priorityOf("sample"))
    end)

    it("falls back to defaultPriority when priorityFor returns nil", function()
      local classified = TelemetryBuffer.new({
        priorityFor = function() return nil end,
        defaultPriority = 4,
      })
      assert.equals(4, classified:priorityOf("whatever"))
    end)

    it("falls back to defaultPriority when priorityFor returns out-of-range value", function()
      local classified = TelemetryBuffer.new({
        priorityFor = function() return 9 end,
        defaultPriority = 1,
      })
      assert.equals(1, classified:priorityOf("whatever"))
    end)
  end)

  describe("push", function()
    it("rejects a non-table event without touching counters", function()
      local ok = buffer:push("not a table")
      assert.is_false(ok)
      assert.equals(0, buffer:size())
      assert.equals(0, buffer:stats().accepted)
    end)

    it("rejects an event missing a string type field without touching counters", function()
      local ok = buffer:push({ value = 1 })
      assert.is_false(ok)
      assert.equals(0, buffer:size())
      assert.equals(0, buffer:stats().accepted)
    end)

    it("accepts a push below capacity", function()
      local ok = buffer:push({ type = "sample", priority = 2 })
      assert.is_true(ok)
      assert.equals(1, buffer:size())
      assert.equals(1, buffer:stats().accepted)
    end)

    it("evicts the oldest item from the worst present tier when a better item arrives at capacity", function()
      local classified = TelemetryBuffer.new({
        maxSize = 3,
        priorityFor = function(eventType)
          if eventType == "p0" then return 0 end
          if eventType == "p4" then return 4 end
          return 2
        end,
      })

      classified:push({ type = "p4", id = "a" })
      classified:push({ type = "p4", id = "b" })
      classified:push({ type = "p4", id = "c" })

      local ok = classified:push({ type = "p0", id = "d" })
      assert.is_true(ok)
      assert.equals(3, classified:size())

      local stats = classified:stats()
      assert.equals(1, stats.dropped[4])
      assert.equals(0, stats.dropped[0])
      assert.equals(4, stats.accepted)

      local drained = classified:drain()
      assert.equals(3, #drained)
      assert.equals("d", drained[1].id)
      assert.equals("b", drained[2].id)
      assert.equals("c", drained[3].id)
    end)

    it("drops the incoming item itself when it is not better than the worst present tier", function()
      local classified = TelemetryBuffer.new({
        maxSize = 3,
        priorityFor = function(eventType)
          if eventType == "p2" then return 2 end
          return 2
        end,
      })

      classified:push({ type = "p2", id = "a" })
      classified:push({ type = "p2", id = "b" })
      classified:push({ type = "p2", id = "c" })

      local ok = classified:push({ type = "p2", id = "d" })
      assert.is_false(ok)
      assert.equals(3, classified:size())

      local stats = classified:stats()
      assert.equals(1, stats.dropped[2])
      assert.equals(3, stats.accepted)

      local drained = classified:drain()
      assert.equals(3, #drained)
      assert.equals("a", drained[1].id)
      assert.equals("b", drained[2].id)
      assert.equals("c", drained[3].id)
    end)

    it("does not evict when incoming priority equals the worst present tier", function()
      local classified = TelemetryBuffer.new({
        maxSize = 2,
        priorityFor = function(eventType)
          if eventType == "p1" then return 1 end
          return 3
        end,
      })

      classified:push({ type = "p1", id = "a" })
      classified:push({ type = "p3", id = "b" })

      local ok = classified:push({ type = "p3", id = "c" })
      assert.is_false(ok)

      local drained = classified:drain()
      assert.equals("a", drained[1].id)
      assert.equals("b", drained[2].id)
    end)
  end)

  describe("drain", function()
    it("respects tier ordering and FIFO order within a tier", function()
      local classified = TelemetryBuffer.new({
        maxSize = 10,
        priorityFor = function(eventType)
          if eventType == "hi" then return 0 end
          if eventType == "lo" then return 3 end
          return 2
        end,
      })

      classified:push({ type = "lo", id = "lo1" })
      classified:push({ type = "hi", id = "hi1" })
      classified:push({ type = "lo", id = "lo2" })
      classified:push({ type = "hi", id = "hi2" })

      local drained = classified:drain()
      assert.equals(4, #drained)
      assert.equals("hi1", drained[1].id)
      assert.equals("hi2", drained[2].id)
      assert.equals("lo1", drained[3].id)
      assert.equals("lo2", drained[4].id)
    end)

    it("drains everything when maxCount is nil", function()
      buffer:push({ type = "a" })
      buffer:push({ type = "b" })
      buffer:push({ type = "c" })
      local drained = buffer:drain(nil)
      assert.equals(3, #drained)
      assert.equals(0, buffer:size())
    end)

    it("limits drained items to maxCount and removes them from the buffer", function()
      buffer:push({ type = "a" })
      buffer:push({ type = "b" })
      buffer:push({ type = "c" })
      local drained = buffer:drain(2)
      assert.equals(2, #drained)
      assert.equals(1, buffer:size())
    end)
  end)

  describe("stats", function()
    it("reflects accepted and dropped counts across a mixed sequence of pushes", function()
      local classified = TelemetryBuffer.new({
        maxSize = 2,
        priorityFor = function(eventType)
          if eventType == "hi" then return 0 end
          return 4
        end,
      })

      classified:push({ type = "lo", id = "a" })
      classified:push({ type = "lo", id = "b" })
      classified:push({ type = "lo", id = "c" })
      classified:push({ type = "hi", id = "d" })

      local stats = classified:stats()
      assert.equals(2, stats.size)
      assert.equals(3, stats.accepted)
      assert.equals(2, stats.dropped[4])
      assert.equals(0, stats.dropped[0])
      assert.equals(2, stats.droppedTotal)
    end)
  end)

  describe("global registration", function()
    it("sets nExBot.IntelligenceTelemetryBuffer", function()
      assert.is_not_nil(nExBot.IntelligenceTelemetryBuffer)
    end)
  end)
end)
