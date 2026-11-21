dofile("core/intelligence/contracts/outcome_reasons.lua")
dofile("core/intelligence/records/outcome_record.lua")
local EpisodeBase = dofile("core/intelligence/episodes/episode_base.lua")
local HuntTracker = dofile("core/intelligence/episodes/hunt_tracker.lua")

describe("IntelligenceHuntTracker", function()
  local tracker
  local episodeBase

  before_each(function()
    episodeBase = EpisodeBase.new({})
    tracker = HuntTracker.new({ episodeBase = episodeBase })
  end)

  describe("new", function()
    it("returns a tracker instance", function()
      assert.is_not_nil(tracker)
      assert.is_function(tracker.start)
      assert.is_function(tracker.close)
      assert.is_function(tracker.get)
      assert.is_function(tracker.getOpen)
    end)

    it("returns nil without episodeBase", function()
      local t = HuntTracker.new({})
      assert.is_nil(t)
    end)
  end)

  describe("start", function()
    it("starts a hunt with required fields", function()
      local hunt = tracker:start({
        huntId = "h1",
        sessionId = "s1",
        characterKey = "ck1",
        profileKey = "pk1",
        routeId = "r1",
      })
      assert.is_not_nil(hunt)
      assert.equals("h1", hunt.huntId)
      assert.equals("hunt", hunt.episodeType)
      assert.equals("s1", hunt.sessionId)
      assert.equals("ck1", hunt.characterKey)
      assert.equals("pk1", hunt.profileKey)
      assert.equals("r1", hunt.routeId)
      assert.equals("open", hunt.state)
    end)

    it("initializes huntMetrics", function()
      local hunt = tracker:start({
        huntId = "h1",
        sessionId = "s1",
        characterKey = "ck1",
        profileKey = "pk1",
        routeId = "r1",
      })
      assert.is_table(hunt.huntMetrics)
      assert.equals(0, hunt.huntMetrics.xpDelta)
      assert.equals(0, hunt.huntMetrics.lootValue)
      assert.equals(0, hunt.huntMetrics.resourcesConsumed)
      assert.equals(0, hunt.huntMetrics.deaths)
      assert.equals(0, hunt.huntMetrics.nearDeaths)
      assert.equals(0, hunt.huntMetrics.manualInterventions)
      assert.equals(0, hunt.huntMetrics.downtime)
    end)

    it("returns nil for missing required fields", function()
      local hunt = tracker:start({})
      assert.is_nil(hunt)
    end)
  end)

  describe("close", function()
    it("closes a hunt with valid reason", function()
      tracker:start({
        huntId = "h1",
        sessionId = "s1",
        characterKey = "ck1",
        profileKey = "pk1",
        routeId = "r1",
      })
      local closed = tracker:close("h1", "completed")
      assert.is_not_nil(closed)
      assert.equals("closed", closed.state)
      assert.equals("completed", closed.closureReason)
    end)

    it("returns nil for invalid reason", function()
      tracker:start({
        huntId = "h1",
        sessionId = "s1",
        characterKey = "ck1",
        profileKey = "pk1",
        routeId = "r1",
      })
      local closed = tracker:close("h1", "bad_reason")
      assert.is_nil(closed)
    end)

    it("returns nil for nonexistent hunt", function()
      local closed = tracker:close("nope", "completed")
      assert.is_nil(closed)
    end)
  end)

  describe("get", function()
    it("returns a hunt by ID", function()
      tracker:start({
        huntId = "h1",
        sessionId = "s1",
        characterKey = "ck1",
        profileKey = "pk1",
        routeId = "r1",
      })
      local hunt = tracker:get("h1")
      assert.is_not_nil(hunt)
      assert.equals("h1", hunt.huntId)
    end)

    it("returns nil for nonexistent hunt", function()
      local hunt = tracker:get("nope")
      assert.is_nil(hunt)
    end)
  end)

  describe("getOpen", function()
    it("returns all open hunts", function()
      tracker:start({
        huntId = "h1",
        sessionId = "s1",
        characterKey = "ck1",
        profileKey = "pk1",
        routeId = "r1",
      })
      tracker:start({
        huntId = "h2",
        sessionId = "s1",
        characterKey = "ck2",
        profileKey = "pk2",
        routeId = "r1",
      })
      local open = tracker:getOpen()
      assert.equals(2, #open)
    end)

    it("excludes closed hunts", function()
      tracker:start({
        huntId = "h1",
        sessionId = "s1",
        characterKey = "ck1",
        profileKey = "pk1",
        routeId = "r1",
      })
      tracker:start({
        huntId = "h2",
        sessionId = "s1",
        characterKey = "ck2",
        profileKey = "pk2",
        routeId = "r1",
      })
      tracker:close("h1", "completed")
      local open = tracker:getOpen()
      assert.equals(1, #open)
      assert.equals("h2", open[1].huntId)
    end)

    it("returns empty table when no open hunts", function()
      local open = tracker:getOpen()
      assert.is_table(open)
      assert.equals(0, #open)
    end)
  end)

  describe("global registration", function()
    it("sets nExBot.IntelligenceHuntTracker", function()
      assert.is_not_nil(nExBot.IntelligenceHuntTracker)
    end)
  end)
end)
