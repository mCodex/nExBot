local combat_executor = require("core.attack.combat_executor")

describe("combat_executor", function()
  local deps

  before_each(function()
    deps = {
      cast = function() end,
      turn = function() end,
      useWith = function() return true end,
      g_game = { useInventoryItemWith = function() return true end },
      SafeCall = {
        findItem = function() return nil end,
        getCachedCaller = function() return nil end,
        target = function() return nil end,
        isInPz = function() return false end,
      },
      Client = { useInventoryItemWith = nil, useWith = nil },
      nowMs = function() return 1000 end,
      player = { getDirection = function() return 0 end },
      recordAttackAction = function() end,
      getSpellState = function() return { nextReadyAt = 0 } end,
      toCooldownMs = function(cd) return cd end,
      applyGlobalBackoff = function() end,
      confirmSpellCast = function(_, _, onSuccess) onSuccess() end,
      isSpellCategory = function(cat) return cat == 1 or cat == 4 or cat == 5 end,
      getSpellKey = function(entry) return (entry.spell or ""):lower() end,
      spellPatterns = {},
      buildPatternKey = function() return "key" end,
      getBestTileByPattern = function() return nil end,
      getSpectators = function() return {} end,
      stamp = function() end,
    }
  end)

  it("useRuneOnTarget calls useWith", function()
    local called = false
    deps.useWith = function(id, target)
      called = true
      assert.equals(3160, id)
      return true
    end
    local result = combat_executor.useRuneOnTarget(3160, "target", deps)
    assert.is_true(result)
    assert.is_true(called)
  end)

  it("useRuneOnTarget falls back to g_game", function()
    deps.useWith = function() error("not available") end
    local called = false
    deps.g_game.useInventoryItemWith = function(id, target)
      called = true
      return true
    end
    local result = combat_executor.useRuneOnTarget(3160, "target", deps)
    assert.is_true(result)
    assert.is_true(called)
  end)

  it("useRuneOnTarget returns false when all methods fail", function()
    deps.useWith = function() error("fail") end
    deps.g_game.useInventoryItemWith = function() error("fail") end
    deps.SafeCall.findItem = function() return nil end
    local result = combat_executor.useRuneOnTarget(3160, "target", deps)
    assert.is_false(result)
  end)

  it("executeAttack delegates to attemptSpellCast for category 1", function()
    local entry = { category = 1, spell = "exori", cooldown = 100 }
    local context = { settings = { Cooldown = true, PvpSafe = false }, target = "target" }
    local result = combat_executor.executeAttack(entry, context, deps)
    assert.is_true(result)
  end)

  it("executeAttack calls useRuneOnTarget for category 3", function()
    local entry = { category = 3, itemId = 3160, spell = "rune" }
    local context = { settings = { Cooldown = true, PvpSafe = false }, target = "target" }
    local result = combat_executor.executeAttack(entry, context, deps)
    assert.is_true(result)
  end)

  it("executeAttack returns false when rune fails", function()
    deps.useWith = function() error("fail") end
    deps.g_game.useInventoryItemWith = function() error("fail") end
    local entry = { category = 3, itemId = 3160, spell = "rune" }
    local context = { settings = { Cooldown = true, PvpSafe = false }, target = "target" }
    local result = combat_executor.executeAttack(entry, context, deps)
    assert.is_false(result)
  end)

  it("executeAttack calls stamp on success", function()
    local stamped = nil
    deps.stamp = function(key) stamped = key end
    local entry = { category = 3, itemId = 3160, spell = "rune" }
    local context = { settings = { Cooldown = true, PvpSafe = false }, target = "target" }
    combat_executor.executeAttack(entry, context, deps)
    assert.equals("3160", stamped)
  end)
end)
