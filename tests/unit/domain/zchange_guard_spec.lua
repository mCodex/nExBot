-- tests/unit/domain/zchange_guard_spec.lua
-- Characterization tests for ZChangeGuard

local mock = require("tests.helpers.mock_otclient")

describe("ZChangeGuard", function()
  local ZCG

  before_each(function()
    mock.resetPlayer()
    mock.install()
    _G.now = os.time() * 1000
    ZCG = dofile("core/zchange_guard.lua")
  end)

  describe("isBlocked()", function()
    it("returns false by default", function()
      assert.is_false(ZCG.isBlocked())
    end)
  end)

  describe("checkBurst()", function()
    it("returns false for first 4 events in same frame", function()
      _G.now = 1000
      assert.is_false(ZCG.checkBurst())
      assert.is_false(ZCG.checkBurst())
      assert.is_false(ZCG.checkBurst())
      assert.is_false(ZCG.checkBurst())
    end)

    it("returns true on 5th event in same frame (triggers burst)", function()
      _G.now = 1000
      ZCG.checkBurst()
      ZCG.checkBurst()
      ZCG.checkBurst()
      ZCG.checkBurst()
      assert.is_true(ZCG.checkBurst())
    end)

    it("sets isBlocked after burst detection", function()
      _G.now = 1000
      for i = 1, 5 do ZCG.checkBurst() end
      assert.is_true(ZCG.isBlocked())
    end)

    it("resets counter on new frame", function()
      _G.now = 1000
      ZCG.checkBurst()
      ZCG.checkBurst()
      _G.now = 1001
      ZCG.checkBurst()
      ZCG.checkBurst()
      _G.now = 1002
      -- Should not burst (counter reset on frame change)
      assert.is_false(ZCG.checkBurst())
    end)

    it("returns true immediately if already blocked", function()
      _G.now = 1000
      for i = 1, 5 do ZCG.checkBurst() end
      _G.now = 1001
      assert.is_true(ZCG.checkBurst())
    end)
  end)

  describe("onZChange()", function()
    it("activates z-block", function()
      ZCG.onZChange({z = 7}, {z = 8})
      assert.is_true(ZCG.isBlocked())
    end)

    it("updates last known z", function()
      ZCG.onZChange({z = 7}, {z = 8})
      assert.equals(8, ZCG.getLastKnownZ())
    end)
  end)

  describe("isTileThrottled()", function()
    it("returns false by default", function()
      assert.is_false(ZCG.isTileThrottled())
    end)
  end)

  describe("checkTileBurst()", function()
    it("returns false below threshold", function()
      _G.now = 1000
      for i = 1, 11 do
        assert.is_false(ZCG.checkTileBurst())
      end
    end)

    it("returns true at threshold (12)", function()
      _G.now = 1000
      for i = 1, 11 do ZCG.checkTileBurst() end
      assert.is_true(ZCG.checkTileBurst())
    end)

    it("sets tile throttle after burst", function()
      _G.now = 1000
      for i = 1, 12 do ZCG.checkTileBurst() end
      assert.is_true(ZCG.isTileThrottled())
    end)
  end)

  describe("backward compatibility", function()
    it("nExBot.zChanging is aliased", function()
      assert.is_function(nExBot.zChanging)
      assert.is_false(nExBot.zChanging())
    end)

    it("nExBot.tileThrottled is aliased", function()
      assert.is_function(nExBot.tileThrottled)
      assert.is_false(nExBot.tileThrottled())
    end)

    it("zChanging global is aliased", function()
      assert.is_function(zChanging)
      assert.is_false(zChanging())
    end)

    it("tileThrottled global is aliased", function()
      assert.is_function(tileThrottled)
      assert.is_false(tileThrottled())
    end)
  end)
end)
