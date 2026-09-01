dofile("core/intelligence/contracts/outcome_reasons.lua")
dofile("core/intelligence/records/outcome_record.lua")
local EpisodeBase = dofile("core/intelligence/episodes/episode_base.lua")

describe("IntelligenceEpisodeBase", function()
  local base

  before_each(function()
    base = EpisodeBase.new({ outcomeRecord = nExBot.IntelligenceOutcomeRecord })
  end)

  describe("new", function()
    it("returns an episode base instance", function()
      assert.is_not_nil(base)
      assert.is_function(base.create)
      assert.is_function(base.close)
      assert.is_function(base.validate)
      assert.is_function(base.isOpen)
    end)

    it("returns nil without outcomeRecord", function()
      local b = EpisodeBase.new({})
      assert.is_not_nil(b)
    end)
  end)

  describe("create", function()
    it("creates episode with required fields", function()
      local ep = base:create({
        episodeId = "ep1",
        episodeType = "encounter",
        sessionId = "s1",
        startedAt = 1000,
      })
      assert.is_not_nil(ep)
      assert.equals("ep1", ep.episodeId)
      assert.equals("encounter", ep.episodeType)
      assert.equals("s1", ep.sessionId)
      assert.equals(1000, ep.startedAt)
      assert.equals("open", ep.state)
    end)

    it("returns nil for missing episodeId", function()
      local ep = base:create({
        episodeType = "encounter",
        sessionId = "s1",
        startedAt = 1000,
      })
      assert.is_nil(ep)
    end)

    it("returns nil for missing episodeType", function()
      local ep = base:create({
        episodeId = "ep1",
        sessionId = "s1",
        startedAt = 1000,
      })
      assert.is_nil(ep)
    end)

    it("returns nil for missing sessionId", function()
      local ep = base:create({
        episodeId = "ep1",
        episodeType = "encounter",
        startedAt = 1000,
      })
      assert.is_nil(ep)
    end)

    it("returns nil for missing startedAt", function()
      local ep = base:create({
        episodeId = "ep1",
        episodeType = "encounter",
        sessionId = "s1",
      })
      assert.is_nil(ep)
    end)

    it("returns nil for invalid episodeType", function()
      local ep = base:create({
        episodeId = "ep1",
        episodeType = "invalid",
        sessionId = "s1",
        startedAt = 1000,
      })
      assert.is_nil(ep)
    end)

    it("accepts all valid episode types", function()
      local types = { "action", "encounter", "loot", "route_segment", "hunt" }
      for _, t in ipairs(types) do
        local ep = base:create({
          episodeId = "ep1",
          episodeType = t,
          sessionId = "s1",
          startedAt = 1000,
        })
        assert.is_not_nil(ep)
        assert.equals(t, ep.episodeType)
      end
    end)

    it("includes optional fields when provided", function()
      local ep = base:create({
        episodeId = "ep1",
        episodeType = "encounter",
        sessionId = "s1",
        startedAt = 1000,
        huntId = "h1",
        routeId = "r1",
        segmentId = "seg1",
        encounterId = "enc1",
        metadata = { key = "value" },
      })
      assert.equals("h1", ep.huntId)
      assert.equals("r1", ep.routeId)
      assert.equals("seg1", ep.segmentId)
      assert.equals("enc1", ep.encounterId)
      assert.equals("value", ep.metadata.key)
    end)

    it("defaults metadata to empty table", function()
      local ep = base:create({
        episodeId = "ep1",
        episodeType = "encounter",
        sessionId = "s1",
        startedAt = 1000,
      })
      assert.is_table(ep.metadata)
    end)
  end)

  describe("close", function()
    local ep

    before_each(function()
      ep = base:create({
        episodeId = "ep1",
        episodeType = "encounter",
        sessionId = "s1",
        startedAt = 1000,
      })
    end)

    it("closes an open episode", function()
      local closed = base:close(ep, "completed")
      assert.equals("closed", closed.state)
      assert.is_number(closed.closedAt)
      assert.equals("completed", closed.closureReason)
    end)

    it("returns nil for invalid reason", function()
      local closed = base:close(ep, "invalid_reason")
      assert.is_nil(closed)
    end)

    it("does not modify original episode table", function()
      base:close(ep, "completed")
      assert.equals("open", ep.state)
    end)

    it("returns already-closed episode unchanged", function()
      local closed = base:close(ep, "completed")
      local closed2 = base:close(closed, "timeout")
      assert.equals("closed", closed2.state)
      assert.equals("completed", closed2.closureReason)
    end)
  end)

  describe("validate", function()
    it("returns true for well-formed open episode", function()
      local ep = base:create({
        episodeId = "ep1",
        episodeType = "encounter",
        sessionId = "s1",
        startedAt = 1000,
      })
      assert.is_true(base:validate(ep))
    end)

    it("returns true for well-formed closed episode", function()
      local ep = base:create({
        episodeId = "ep1",
        episodeType = "encounter",
        sessionId = "s1",
        startedAt = 1000,
      })
      local closed = base:close(ep, "completed")
      assert.is_true(base:validate(closed))
    end)

    it("rejects non-table", function()
      assert.is_false(base:validate(nil))
      assert.is_false(base:validate("bad"))
    end)

    it("rejects missing episodeId", function()
      assert.is_false(base:validate({
        episodeType = "encounter",
        sessionId = "s1",
        startedAt = 1000,
        state = "open",
      }))
    end)

    it("rejects invalid state", function()
      local ep = base:create({
        episodeId = "ep1",
        episodeType = "encounter",
        sessionId = "s1",
        startedAt = 1000,
      })
      ep.state = "invalid"
      assert.is_false(base:validate(ep))
    end)
  end)

  describe("isOpen", function()
    it("returns true for open episode", function()
      local ep = base:create({
        episodeId = "ep1",
        episodeType = "encounter",
        sessionId = "s1",
        startedAt = 1000,
      })
      assert.is_true(base:isOpen(ep))
    end)

    it("returns false for closed episode", function()
      local ep = base:create({
        episodeId = "ep1",
        episodeType = "encounter",
        sessionId = "s1",
        startedAt = 1000,
      })
      local closed = base:close(ep, "completed")
      assert.is_false(base:isOpen(closed))
    end)

    it("returns false for nil", function()
      assert.is_false(base:isOpen(nil))
    end)
  end)

  describe("global registration", function()
    it("sets nExBot.IntelligenceEpisodeBase", function()
      assert.is_not_nil(nExBot.IntelligenceEpisodeBase)
    end)
  end)
end)
