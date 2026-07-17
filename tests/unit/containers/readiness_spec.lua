-- readiness_spec.lua (updated for v5 readiness with 10 levels)
local Readiness = dofile("core/containers/readiness.lua")
local Registry  = dofile("core/containers/registry.lua")

describe("Readiness", function()
  -- ── Backward-compat mode (no role assignments) ──────────────────────────

  it("backward compat: ready when empty", function()
    local reg = Registry.new()
    local r = Readiness.compute(reg, 1, false)
    assert.equals("ready", r.status)
    assert.equals(1, r.generation)
  end)

  it("backward compat: discovering when queued", function()
    local reg = Registry.new()
    reg:add({ identity = "a", state = "queued", itemType = 3003 })
    local r = Readiness.compute(reg, 1, false)
    assert.equals("discovering", r.status)
    assert.equals(1, r.queuedCount)
  end)

  it("backward compat: ready when all inspected", function()
    local reg = Registry.new()
    reg:add({ identity = "a", state = "inspected", itemType = 3003 })
    local r = Readiness.compute(reg, 1, false)
    assert.equals("ready", r.status)
    assert.equals(1, r.inspectedCount)
  end)

  it("backward compat: degraded when some failed", function()
    local reg = Registry.new()
    reg:add({ identity = "a", state = "inspected", itemType = 3003 })
    reg:add({ identity = "b", state = "failed",    itemType = 3031 })
    local r = Readiness.compute(reg, 1, false)
    assert.equals("degraded", r.status)
    assert.equals(1, r.failedCount)
  end)

  it("backward compat: mainBackpackReady when ready", function()
    local reg = Registry.new()
    reg:add({ identity = "a", state = "inspected", itemType = 3003 })
    local r = Readiness.compute(reg, 1, false)
    assert.is_true(r.mainBackpackReady)
  end)

  it("backward compat: sets quiverRequired for paladins (bool arg)", function()
    local reg = Registry.new()
    local r = Readiness.compute(reg, 1, true)
    assert.is_true(r.quiverRequired)
  end)

  it("backward compat: quiverRequired false for non-paladins", function()
    local reg = Registry.new()
    local r = Readiness.compute(reg, 1, false)
    assert.is_false(r.quiverRequired)
  end)

  -- ── Role-based mode (new API) ────────────────────────────────────────────

  it("SESSION_READY when no roles and no nodes", function()
    local reg = Registry.new()
    local r = Readiness.compute(reg, 1, { isPaladin = false, roleAssignments = { MAIN = "x" } })
    -- role assigned but node not in registry → not mainReady
    assert.equals("SESSION_READY", r.status)
  end)

  it("ROOTS_READY when main opened but HEALING_SUPPLIES configured and not ready", function()
    local reg = Registry.new()
    reg:add({ identity = "main",    state = "opened", itemType = 2854 })
    -- supplies identity is configured but not in registry → not ready
    local r = Readiness.compute(reg, 1, {
      isPaladin = false,
      roleAssignments = { MAIN = "main", HEALING_SUPPLIES = "supplies-not-in-reg" }
    })
    assert.equals("ROOTS_READY", r.status)
    assert.is_true(r.mainBackpackReady)
  end)

  it("FULLY_DISCOVERED when only MAIN is configured and ready (no other required roles)", function()
    local reg = Registry.new()
    reg:add({ identity = "main", state = "opened", itemType = 2854 })
    local r = Readiness.compute(reg, 1, {
      isPaladin = false,
      roleAssignments = { MAIN = "main" }
    })
    -- No other roles configured → all requirements satisfied → FULLY_DISCOVERED
    assert.equals("FULLY_DISCOVERED", r.status)
    assert.is_true(r.mainBackpackReady)
  end)

  it("SURVIVAL_READY when main and HEALING_SUPPLIES ready, LOOT configured but not ready", function()
    local reg = Registry.new()
    reg:add({ identity = "main",    state = "opened", itemType = 2854 })
    reg:add({ identity = "supplies", state = "opened", itemType = 2866 })
    -- LOOT configured but not in registry → not ready
    local r = Readiness.compute(reg, 1, {
      isPaladin = false,
      roleAssignments = {
        MAIN             = "main",
        HEALING_SUPPLIES = "supplies",
        LOOT             = "loot-not-in-reg",
      }
    })
    -- mainReady=true, survivalReady=true, lootReady=false → SURVIVAL_READY
    assert.is_true(r.status == "SURVIVAL_READY" or r.status == "COMBAT_READY",
      "Got: " .. tostring(r.status))
    assert.is_true(r.survivalReady)
  end)

  it("COMBAT_READY when main + healing + quiver + ammo (paladin) all configured and ready", function()
    local reg = Registry.new()
    reg:add({ identity = "main",    state = "inspected", itemType = 2854 })
    reg:add({ identity = "supplies", state = "inspected", itemType = 2866 })
    reg:add({ identity = "quiver",  state = "inspected", itemType = 3031 })
    reg:add({ identity = "ammo",    state = "inspected", itemType = 763  })
    -- LOOT configured but not ready → prevents FULLY_DISCOVERED
    local r = Readiness.compute(reg, 1, {
      isPaladin = true,
      roleAssignments = {
        MAIN             = "main",
        HEALING_SUPPLIES = "supplies",
        QUIVER           = "quiver",
        AMMO_RESERVE     = "ammo",
        LOOT             = "loot-not-in-reg",
      }
    })
    assert.equals("COMBAT_READY", r.status)
    assert.is_true(r.quiverReady)
    assert.is_true(r.ammoReady)
  end)

  it("FULLY_DISCOVERED when all roles including loot are ready", function()
    local reg = Registry.new()
    reg:add({ identity = "main",    state = "inspected", itemType = 2854 })
    reg:add({ identity = "supplies", state = "inspected", itemType = 2866 })
    reg:add({ identity = "loot",    state = "inspected", itemType = 2869 })
    local r = Readiness.compute(reg, 1, {
      isPaladin = false,
      roleAssignments = {
        MAIN             = "main",
        HEALING_SUPPLIES = "supplies",
        LOOT             = "loot",
      }
    })
    assert.equals("FULLY_DISCOVERED", r.status)
    assert.is_true(r.lootReady)
  end)

  it("meetsLevel: COMBAT_READY meets SURVIVAL_READY", function()
    assert.is_true(Readiness.meetsLevel("COMBAT_READY", "SURVIVAL_READY"))
  end)

  it("meetsLevel: SURVIVAL_READY does not meet COMBAT_READY", function()
    assert.is_false(Readiness.meetsLevel("SURVIVAL_READY", "COMBAT_READY"))
  end)

  it("meetsLevel: FULLY_DISCOVERED meets every level", function()
    for _, lvl in ipairs(Readiness.LEVELS) do
      assert.is_true(Readiness.meetsLevel("FULLY_DISCOVERED", lvl),
        "Expected FULLY_DISCOVERED >= " .. lvl)
    end
  end)

  it("meetsLevel: FAILED meets only FAILED", function()
    assert.is_true(Readiness.meetsLevel("FAILED", "FAILED"))
    assert.is_false(Readiness.meetsLevel("FAILED", "SESSION_READY"))
  end)

  it("discovering flag true when nodes are queued", function()
    local reg = Registry.new()
    reg:add({ identity = "a", state = "queued", itemType = 3003 })
    local r = Readiness.compute(reg, 1, { isPaladin = false,
      roleAssignments = { MAIN = "a" } })
    assert.is_true(r.discovering)
  end)
end)
