dofile("core/intelligence/contracts/outcome_reasons.lua")
dofile("core/intelligence/records/outcome_record.lua")
local EpisodeBase = dofile("core/intelligence/episodes/episode_base.lua")
local RouteSegmentTracker = dofile("core/intelligence/episodes/route_segment_tracker.lua")

describe("IntelligenceRouteSegmentTracker", function()
  local tracker
  local episodeBase

  before_each(function()
    episodeBase = EpisodeBase.new({})
    tracker = RouteSegmentTracker.new({ episodeBase = episodeBase })
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
      local t = RouteSegmentTracker.new({})
      assert.is_nil(t)
    end)
  end)

  describe("start", function()
    it("starts a route segment with required fields", function()
      local seg = tracker:start({
        segmentId = "seg1",
        sessionId = "s1",
        huntId = "h1",
        routeId = "r1",
        routeGeneration = 1,
        startWaypoint = 0,
      })
      assert.is_not_nil(seg)
      assert.equals("seg1", seg.segmentId)
      assert.equals("route_segment", seg.episodeType)
      assert.equals("s1", seg.sessionId)
      assert.equals("h1", seg.huntId)
      assert.equals("r1", seg.routeId)
      assert.equals(1, seg.routeGeneration)
      assert.equals(0, seg.startWaypoint)
      assert.equals("open", seg.state)
    end)

    it("initializes segmentMetrics", function()
      local seg = tracker:start({
        segmentId = "seg1",
        sessionId = "s1",
        huntId = "h1",
        routeId = "r1",
        routeGeneration = 1,
        startWaypoint = 0,
      })
      assert.is_table(seg.segmentMetrics)
      assert.equals(0, seg.segmentMetrics.retries)
      assert.equals(0, seg.segmentMetrics.stuckEvents)
      assert.equals(0, seg.segmentMetrics.deviations)
      assert.equals(0, seg.segmentMetrics.pathFailures)
    end)

    it("returns nil for missing required fields", function()
      local seg = tracker:start({})
      assert.is_nil(seg)
    end)
  end)

  describe("close", function()
    it("closes a route segment with valid reason", function()
      tracker:start({
        segmentId = "seg1",
        sessionId = "s1",
        huntId = "h1",
        routeId = "r1",
        routeGeneration = 1,
        startWaypoint = 0,
      })
      local closed = tracker:close("seg1", "completed")
      assert.is_not_nil(closed)
      assert.equals("closed", closed.state)
      assert.equals("completed", closed.closureReason)
    end)

    it("returns nil for invalid reason", function()
      tracker:start({
        segmentId = "seg1",
        sessionId = "s1",
        huntId = "h1",
        routeId = "r1",
        routeGeneration = 1,
        startWaypoint = 0,
      })
      local closed = tracker:close("seg1", "bad_reason")
      assert.is_nil(closed)
    end)

    it("returns nil for nonexistent segment", function()
      local closed = tracker:close("nope", "completed")
      assert.is_nil(closed)
    end)
  end)

  describe("get", function()
    it("returns a route segment by ID", function()
      tracker:start({
        segmentId = "seg1",
        sessionId = "s1",
        huntId = "h1",
        routeId = "r1",
        routeGeneration = 1,
        startWaypoint = 0,
      })
      local seg = tracker:get("seg1")
      assert.is_not_nil(seg)
      assert.equals("seg1", seg.segmentId)
    end)

    it("returns nil for nonexistent segment", function()
      local seg = tracker:get("nope")
      assert.is_nil(seg)
    end)
  end)

  describe("getOpen", function()
    it("returns all open segments", function()
      tracker:start({
        segmentId = "seg1",
        sessionId = "s1",
        huntId = "h1",
        routeId = "r1",
        routeGeneration = 1,
        startWaypoint = 0,
      })
      tracker:start({
        segmentId = "seg2",
        sessionId = "s1",
        huntId = "h1",
        routeId = "r1",
        routeGeneration = 1,
        startWaypoint = 1,
      })
      local open = tracker:getOpen()
      assert.equals(2, #open)
    end)

    it("excludes closed segments", function()
      tracker:start({
        segmentId = "seg1",
        sessionId = "s1",
        huntId = "h1",
        routeId = "r1",
        routeGeneration = 1,
        startWaypoint = 0,
      })
      tracker:start({
        segmentId = "seg2",
        sessionId = "s1",
        huntId = "h1",
        routeId = "r1",
        routeGeneration = 1,
        startWaypoint = 1,
      })
      tracker:close("seg1", "completed")
      local open = tracker:getOpen()
      assert.equals(1, #open)
      assert.equals("seg2", open[1].segmentId)
    end)

    it("returns empty table when no open segments", function()
      local open = tracker:getOpen()
      assert.is_table(open)
      assert.equals(0, #open)
    end)
  end)

  describe("global registration", function()
    it("sets nExBot.IntelligenceRouteSegmentTracker", function()
      assert.is_not_nil(nExBot.IntelligenceRouteSegmentTracker)
    end)
  end)
end)
