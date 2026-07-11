-- tests/unit/domain/kill_tracker_spec.lua
-- Characterization tests for KillTracker

local mock = require("tests.helpers.mock_otclient")

describe("KillTracker", function()
  local KT

  before_each(function()
    mock.resetPlayer()
    mock.install()
    _G.now = os.time() * 1000
    KT = dofile("core/kill_tracker.lua")
    KT.reset()
  end)

  describe("recordKill()", function()
    it("records a kill", function()
      KT.recordKill(1, "Dragon", {x = 100, y = 200, z = 7})
      assert.equals(1, KT.getCount())
    end)

    it("stores kill data correctly", function()
      KT.recordKill(42, "Demon", {x = 50, y = 60, z = 8})
      local data = KT.getKilled(42)
      assert.is_not_nil(data)
      assert.equals("Demon", data.name)
      assert.equals(50, data.pos.x)
      assert.equals(60, data.pos.y)
      assert.equals(8, data.pos.z)
    end)

    it("does not record nil creatureId", function()
      KT.recordKill(nil, "Dragon", {x = 100, y = 200, z = 7})
      assert.equals(0, KT.getCount())
    end)

    it("does not record nil pos", function()
      KT.recordKill(1, "Dragon", nil)
      assert.equals(0, KT.getCount())
    end)

    it("handles duplicate IDs by overwriting", function()
      KT.recordKill(1, "Dragon", {x = 100, y = 200, z = 7})
      KT.recordKill(1, "Demon", {x = 50, y = 60, z = 8})
      assert.equals(1, KT.getCount())
      assert.equals("Demon", KT.getKilled(1).name)
    end)

    it("evicts oldest when at capacity", function()
      -- Fill to capacity (200)
      for i = 1, 200 do
        _G.now = os.time() * 1000 + i
        KT.recordKill(i, "Monster " .. i, {x = i, y = i, z = 7})
      end
      assert.equals(200, KT.getCount())
      
      -- Add one more (should evict oldest)
      _G.now = os.time() * 1000 + 300
      KT.recordKill(201, "New Monster", {x = 201, y = 201, z = 7})
      assert.equals(200, KT.getCount())
      assert.is_not_nil(KT.getKilled(201))
    end)
  end)

  describe("getKilled()", function()
    it("returns nil for unknown ID", function()
      assert.is_nil(KT.getKilled(999))
    end)

    it("returns kill data", function()
      KT.recordKill(1, "Dragon", {x = 100, y = 200, z = 7})
      local data = KT.getKilled(1)
      assert.is_table(data)
    end)
  end)

  describe("getAll()", function()
    it("returns empty table initially", function()
      assert.same({}, KT.getAll())
    end)

    it("returns all kills", function()
      KT.recordKill(1, "Dragon", {x = 100, y = 200, z = 7})
      KT.recordKill(2, "Demon", {x = 50, y = 60, z = 8})
      local all = KT.getAll()
      assert.is_not_nil(all[1])
      assert.is_not_nil(all[2])
    end)
  end)

  describe("cleanup()", function()
    it("removes expired entries", function()
      _G.now = 1000
      KT.recordKill(1, "Dragon", {x = 100, y = 200, z = 7})
      _G.now = 1000 + 16000 -- 16 seconds later (> 15s expiry)
      KT.cleanup()
      assert.equals(0, KT.getCount())
    end)

    it("keeps fresh entries", function()
      _G.now = 1000
      KT.recordKill(1, "Dragon", {x = 100, y = 200, z = 7})
      _G.now = 1000 + 5000 -- 5 seconds later
      KT.cleanup()
      assert.equals(1, KT.getCount())
    end)
  end)

  describe("reset()", function()
    it("clears all kills", function()
      KT.recordKill(1, "Dragon", {x = 100, y = 200, z = 7})
      KT.recordKill(2, "Demon", {x = 50, y = 60, z = 8})
      KT.reset()
      assert.equals(0, KT.getCount())
    end)
  end)
end)
