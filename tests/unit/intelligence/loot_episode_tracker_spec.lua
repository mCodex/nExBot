dofile("core/intelligence/contracts/outcome_reasons.lua")
dofile("core/intelligence/records/outcome_record.lua")
dofile("core/intelligence/episodes/episode_base.lua")
local Tracker = dofile("core/intelligence/episodes/loot_episode_tracker.lua")

describe("IntelligenceLootEpisodeTracker", function()
  local tracker

  before_each(function()
    tracker = Tracker.new({ episodeBase = nExBot.IntelligenceEpisodeBase })
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
      assert.is_not_nil(nExBot.IntelligenceLootEpisodeTracker)
    end)
  end)

  describe("start", function()
    it("starts a loot episode with required fields", function()
      local ep = tracker:start({
        lootEpisodeId = "le1",
        sessionId = "s1",
        huntId = "h1",
        corpseId = "c1",
        encounterId = "enc1",
      })
      assert.is_not_nil(ep)
      assert.equals("le1", ep.episodeId)
      assert.equals("loot", ep.episodeType)
      assert.equals("s1", ep.sessionId)
      assert.equals("h1", ep.huntId)
      assert.equals("c1", ep.corpseId)
      assert.equals("enc1", ep.encounterId)
      assert.equals("open", ep.state)
    end)

    it("initializes lootLifecycle counters", function()
      local ep = tracker:start({
        lootEpisodeId = "le2",
        sessionId = "s1",
        huntId = "h1",
        corpseId = "c1",
        encounterId = "enc1",
      })
      assert.equals(0, ep.lootLifecycle.corpseObserved)
      assert.equals(0, ep.lootLifecycle.corpseIdentified)
      assert.equals(0, ep.lootLifecycle.containerOpened)
      assert.equals(0, ep.lootLifecycle.itemsListed)
      assert.equals(0, ep.lootLifecycle.itemsAttempted)
      assert.equals(0, ep.lootLifecycle.itemsSucceeded)
      assert.equals(0, ep.lootLifecycle.itemsFailed)
      assert.equals(0, ep.lootLifecycle.captureVerified)
    end)

    it("rejects missing lootEpisodeId", function()
      local ep = tracker:start({
        sessionId = "s1",
        huntId = "h1",
        corpseId = "c1",
        encounterId = "enc1",
      })
      assert.is_nil(ep)
    end)

    it("rejects missing sessionId", function()
      local ep = tracker:start({
        lootEpisodeId = "le3",
        huntId = "h1",
        corpseId = "c1",
        encounterId = "enc1",
      })
      assert.is_nil(ep)
    end)

    it("rejects missing corpseId", function()
      local ep = tracker:start({
        lootEpisodeId = "le4",
        sessionId = "s1",
        huntId = "h1",
        encounterId = "enc1",
      })
      assert.is_nil(ep)
    end)

    it("rejects missing encounterId", function()
      local ep = tracker:start({
        lootEpisodeId = "le5",
        sessionId = "s1",
        huntId = "h1",
        corpseId = "c1",
      })
      assert.is_nil(ep)
    end)

    it("rejects duplicate lootEpisodeId", function()
      tracker:start({
        lootEpisodeId = "le6",
        sessionId = "s1",
        huntId = "h1",
        corpseId = "c1",
        encounterId = "enc1",
      })
      local dup = tracker:start({
        lootEpisodeId = "le6",
        sessionId = "s1",
        huntId = "h1",
        corpseId = "c1",
        encounterId = "enc1",
      })
      assert.is_nil(dup)
    end)
  end)

  describe("close", function()
    it("closes a loot episode with valid reason", function()
      tracker:start({
        lootEpisodeId = "le7",
        sessionId = "s1",
        huntId = "h1",
        corpseId = "c1",
        encounterId = "enc1",
      })
      local closed = tracker:close("le7", "loot_completed")
      assert.is_not_nil(closed)
      assert.equals("closed", closed.state)
      assert.equals("loot_completed", closed.closureReason)
    end)

    it("returns nil for invalid reason", function()
      tracker:start({
        lootEpisodeId = "le8",
        sessionId = "s1",
        huntId = "h1",
        corpseId = "c1",
        encounterId = "enc1",
      })
      local closed = tracker:close("le8", "bogus")
      assert.is_nil(closed)
    end)

    it("returns nil for nonexistent episode", function()
      local closed = tracker:close("nonexistent", "loot_completed")
      assert.is_nil(closed)
    end)

    it("removes closed episode from open set", function()
      tracker:start({
        lootEpisodeId = "le9",
        sessionId = "s1",
        huntId = "h1",
        corpseId = "c1",
        encounterId = "enc1",
      })
      tracker:close("le9", "loot_completed")
      assert.is_nil(tracker:get("le9"))
    end)
  end)

  describe("get", function()
    it("returns loot episode by id", function()
      tracker:start({
        lootEpisodeId = "le10",
        sessionId = "s1",
        huntId = "h1",
        corpseId = "c1",
        encounterId = "enc1",
      })
      local ep = tracker:get("le10")
      assert.is_not_nil(ep)
      assert.equals("le10", ep.episodeId)
    end)

    it("returns nil for unknown id", function()
      assert.is_nil(tracker:get("unknown"))
    end)
  end)

  describe("getOpen", function()
    it("returns all open episodes", function()
      tracker:start({
        lootEpisodeId = "le11",
        sessionId = "s1",
        huntId = "h1",
        corpseId = "c1",
        encounterId = "enc1",
      })
      tracker:start({
        lootEpisodeId = "le12",
        sessionId = "s1",
        huntId = "h1",
        corpseId = "c2",
        encounterId = "enc2",
      })
      local open = tracker:getOpen()
      assert.equals(2, #open)
    end)

    it("returns empty table when no open episodes", function()
      local open = tracker:getOpen()
      assert.equals(0, #open)
    end)

    it("excludes closed episodes", function()
      tracker:start({
        lootEpisodeId = "le13",
        sessionId = "s1",
        huntId = "h1",
        corpseId = "c1",
        encounterId = "enc1",
      })
      tracker:start({
        lootEpisodeId = "le14",
        sessionId = "s1",
        huntId = "h1",
        corpseId = "c2",
        encounterId = "enc2",
      })
      tracker:close("le13", "loot_completed")
      local open = tracker:getOpen()
      assert.equals(1, #open)
      assert.equals("le14", open[1].episodeId)
    end)
  end)

  describe("stats", function()
    it("returns tracker statistics", function()
      tracker:start({
        lootEpisodeId = "le15",
        sessionId = "s1",
        huntId = "h1",
        corpseId = "c1",
        encounterId = "enc1",
      })
      tracker:start({
        lootEpisodeId = "le16",
        sessionId = "s1",
        huntId = "h1",
        corpseId = "c2",
        encounterId = "enc2",
      })
      tracker:close("le15", "loot_completed")
      local s = tracker:stats()
      assert.equals(2, s.total)
      assert.equals(1, s.open)
      assert.equals(1, s.closed)
      assert.equals(1, s.byReason.loot_completed)
    end)

    it("returns zeros when empty", function()
      local s = tracker:stats()
      assert.equals(0, s.total)
      assert.equals(0, s.open)
      assert.equals(0, s.closed)
    end)
  end)
end)
