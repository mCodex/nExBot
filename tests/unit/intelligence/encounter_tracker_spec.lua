dofile("core/intelligence/contracts/outcome_reasons.lua")
dofile("core/intelligence/records/outcome_record.lua")
local EpisodeBase = dofile("core/intelligence/episodes/episode_base.lua")
local Tracker = dofile("core/intelligence/episodes/encounter_tracker.lua")

describe("IntelligenceEncounterTracker", function()
  local tracker
  local base

  before_each(function()
    base = EpisodeBase.new({})
    tracker = Tracker.new({ episodeBase = base })
  end)

  describe("new", function()
    it("returns a tracker instance", function()
      assert.is_not_nil(tracker)
      assert.is_function(tracker.start)
      assert.is_function(tracker.close)
      assert.is_function(tracker.get)
      assert.is_function(tracker.getOpen)
      assert.is_function(tracker.stats)
    end)

    it("sets global registration", function()
      assert.is_not_nil(nExBot.IntelligenceEncounterTracker)
    end)
  end)

  describe("start", function()
    it("starts an encounter with required fields", function()
      local enc = tracker:start({
        encounterId = "enc1",
        sessionId = "s1",
        huntId = "h1",
        targetInstanceId = "t1",
      })
      assert.is_not_nil(enc)
      assert.equals("enc1", enc.encounterId)
      assert.equals("encounter", enc.episodeType)
      assert.equals("s1", enc.sessionId)
      assert.equals("h1", enc.huntId)
      assert.equals("t1", enc.targetInstanceId)
      assert.equals("open", enc.state)
    end)

    it("adds encounter counters", function()
      local enc = tracker:start({
        encounterId = "enc1",
        sessionId = "s1",
        huntId = "h1",
        targetInstanceId = "t1",
      })
      assert.is_table(enc.encounters)
      assert.equals(0, enc.encounters.firstEngagement)
      assert.equals(0, enc.encounters.targetSwitches)
      assert.equals(0, enc.encounters.damageWindows)
      assert.equals(0, enc.encounters.resourceUses)
    end)

    it("rejects duplicate encounterId", function()
      tracker:start({
        encounterId = "enc1",
        sessionId = "s1",
        huntId = "h1",
        targetInstanceId = "t1",
      })
      local enc2 = tracker:start({
        encounterId = "enc1",
        sessionId = "s1",
        huntId = "h1",
        targetInstanceId = "t2",
      })
      assert.is_nil(enc2)
    end)

    it("returns nil for missing required fields", function()
      assert.is_nil(tracker:start({ encounterId = "enc1" }))
      assert.is_nil(tracker:start({ sessionId = "s1" }))
      assert.is_nil(tracker:start({ huntId = "h1" }))
      assert.is_nil(tracker:start({ targetInstanceId = "t1" }))
    end)
  end)

  describe("close", function()
    before_each(function()
      tracker:start({
        encounterId = "enc1",
        sessionId = "s1",
        huntId = "h1",
        targetInstanceId = "t1",
      })
    end)

    it("closes an open encounter", function()
      local closed = tracker:close("enc1", "completed")
      assert.is_not_nil(closed)
      assert.equals("closed", closed.state)
      assert.equals("completed", closed.closureReason)
    end)

    it("removes from open list after close", function()
      tracker:close("enc1", "completed")
      local open = tracker:getOpen()
      assert.equals(0, #open)
    end)

    it("returns nil for invalid reason", function()
      local closed = tracker:close("enc1", "bogus")
      assert.is_nil(closed)
    end)

    it("returns nil for unknown encounterId", function()
      local closed = tracker:close("nope", "completed")
      assert.is_nil(closed)
    end)

    it("returns nil when closing already-closed encounter", function()
      tracker:close("enc1", "completed")
      local closed = tracker:close("enc1", "timeout")
      assert.is_nil(closed)
    end)
  end)

  describe("get", function()
    it("returns encounter by id", function()
      tracker:start({
        encounterId = "enc1",
        sessionId = "s1",
        huntId = "h1",
        targetInstanceId = "t1",
      })
      local enc = tracker:get("enc1")
      assert.is_not_nil(enc)
      assert.equals("enc1", enc.encounterId)
    end)

    it("returns nil for unknown id", function()
      assert.is_nil(tracker:get("nope"))
    end)
  end)

  describe("getOpen", function()
    it("returns empty table when no encounters", function()
      local open = tracker:getOpen()
      assert.is_table(open)
      assert.equals(0, #open)
    end)

    it("returns only open encounters", function()
      tracker:start({ encounterId = "enc1", sessionId = "s1", huntId = "h1", targetInstanceId = "t1" })
      tracker:start({ encounterId = "enc2", sessionId = "s1", huntId = "h1", targetInstanceId = "t2" })
      tracker:close("enc1", "completed")

      local open = tracker:getOpen()
      assert.equals(1, #open)
      assert.equals("enc2", open[1].encounterId)
    end)
  end)

  describe("stats", function()
    it("returns zeroed stats when empty", function()
      local s = tracker:stats()
      assert.equals(0, s.total)
      assert.equals(0, s.open)
      assert.equals(0, s.closed)
      assert.is_table(s.byReason)
    end)

    it("tracks open and closed counts", function()
      tracker:start({ encounterId = "enc1", sessionId = "s1", huntId = "h1", targetInstanceId = "t1" })
      tracker:start({ encounterId = "enc2", sessionId = "s1", huntId = "h1", targetInstanceId = "t2" })
      tracker:close("enc1", "completed")

      local s = tracker:stats()
      assert.equals(2, s.total)
      assert.equals(1, s.open)
      assert.equals(1, s.closed)
      assert.equals(1, s.byReason.completed)
    end)
  end)
end)
