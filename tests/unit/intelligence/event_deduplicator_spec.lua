local Dedup = dofile("core/intelligence/contracts/event_deduplicator.lua")

describe("IntelligenceEventDeduplicator", function()
  local dedup

  before_each(function()
    dedup = Dedup.new()
  end)

  describe("new", function()
    it("creates with default maxSize", function()
      assert.is_not_nil(dedup)
      local s = dedup:stats()
      assert.equals(1000, s.maxSize)
    end)

    it("accepts custom maxSize", function()
      local d = Dedup.new({ maxSize = 50 })
      assert.equals(50, d:stats().maxSize)
    end)
  end)

  describe("isDuplicate", function()
    it("returns false for first occurrence by eventId", function()
      local event = { eventId = "evt:1", type = "test" }
      assert.is_false(dedup:isDuplicate(event))
    end)

    it("returns true for duplicate eventId after record", function()
      local event = { eventId = "evt:1", type = "test" }
      dedup:record(event)
      assert.is_true(dedup:isDuplicate(event))
    end)

    it("detects duplicate by idempotencyKey", function()
      local e1 = { eventId = "evt:1", idempotencyKey = "idem:1", type = "test" }
      local e2 = { eventId = "evt:2", idempotencyKey = "idem:1", type = "test" }
      dedup:record(e1)
      assert.is_true(dedup:isDuplicate(e2))
    end)

    it("returns false for events without eventId", function()
      assert.is_false(dedup:isDuplicate({ type = "test" }))
      assert.is_false(dedup:isDuplicate(nil))
    end)
  end)

  describe("record", function()
    it("does not record events without eventId", function()
      dedup:record({ type = "test" })
      local s = dedup:stats()
      assert.equals(0, s.totalSeen)
    end)

    it("increments totalSeen", function()
      dedup:record({ eventId = "evt:1", type = "test" })
      assert.equals(1, dedup:stats().totalSeen)
      dedup:record({ eventId = "evt:2", type = "test" })
      assert.equals(2, dedup:stats().totalSeen)
    end)

    it("increments totalDuplicates on duplicate", function()
      local e = { eventId = "evt:1", type = "test" }
      dedup:record(e)
      dedup:record(e)
      assert.equals(1, dedup:stats().totalDuplicates)
    end)
  end)

  describe("LRU eviction", function()
    it("evicts oldest when at capacity", function()
      local small = Dedup.new({ maxSize = 2 })
      small:record({ eventId = "evt:1", type = "test" })
      small:record({ eventId = "evt:2", type = "test" })
      small:record({ eventId = "evt:3", type = "test" })

      assert.is_true(small:isDuplicate({ eventId = "evt:3" }))
      assert.is_true(small:isDuplicate({ eventId = "evt:2" }))
      assert.is_false(small:isDuplicate({ eventId = "evt:1" }))
      assert.equals(3, small:stats().totalSeen)
    end)

    it("evicts both eventId and idempotencyKey mappings", function()
      local small = Dedup.new({ maxSize = 2 })
      small:record({ eventId = "evt:1", idempotencyKey = "idem:1", type = "test" })
      small:record({ eventId = "evt:2", idempotencyKey = "idem:2", type = "test" })
      small:record({ eventId = "evt:3", idempotencyKey = "idem:3", type = "test" })

      assert.is_false(small:isDuplicate({ idempotencyKey = "idem:1" }))
      assert.is_true(small:isDuplicate({ eventId = "evt:2" }))
      assert.is_true(small:isDuplicate({ eventId = "evt:3" }))
    end)
  end)

  describe("stats", function()
    it("returns zero counts initially", function()
      local s = dedup:stats()
      assert.equals(0, s.totalSeen)
      assert.equals(0, s.totalDuplicates)
      assert.equals(0, s.total)
    end)

    it("tracks total as seen minus duplicates", function()
      local e = { eventId = "evt:1", type = "test" }
      dedup:record(e)
      dedup:record(e)
      local s = dedup:stats()
      assert.equals(2, s.totalSeen)
      assert.equals(1, s.totalDuplicates)
      assert.equals(1, s.total)
    end)
  end)

  describe("reset", function()
    it("clears all recorded events", function()
      dedup:record({ eventId = "evt:1", type = "test" })
      dedup:record({ eventId = "evt:2", type = "test" })
      dedup:reset()

      local s = dedup:stats()
      assert.equals(0, s.totalSeen)
      assert.equals(0, s.totalDuplicates)
      assert.equals(0, s.total)
    end)

    it("allows re-recording after reset", function()
      local e = { eventId = "evt:1", type = "test" }
      dedup:record(e)
      dedup:reset()
      assert.is_false(dedup:isDuplicate(e))
    end)
  end)

  describe("global registration", function()
    it("sets nExBot.IntelligenceEventDeduplicator", function()
      assert.is_not_nil(nExBot.IntelligenceEventDeduplicator)
    end)
  end)
end)
