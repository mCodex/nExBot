local TargetProposal = dofile("targetbot/target_proposal.lua")

local function creature(id)
  return { getId = function() return id end }
end

describe("TargetBot proposal seam", function()
  it("adapts the selected legacy target without executing it", function()
    local selected = {
      creature = creature(42),
      config = { name = "Dragon", priority = 5 },
      priority = 5123,
      danger = 8,
    }

    assert.same({
      domain = "combat",
      action = "attack",
      source = "TargetBot",
      targetId = 42,
      configuredPriority = 5,
      basePriority = 5123,
      priority = 5123,
      confidence = 1,
      createdAt = 1000,
      expiresAt = 1250,
      snapshotGeneration = 7,
      combatGeneration = 9,
      selection = selected,
    }, TargetProposal.fromSelection(selected, {
      now = 1000,
      generations = { snapshot = 7, combat = 9 },
    }))
  end)

  it("rejects selections the legacy attack seam cannot execute", function()
    assert.same({ nil, "invalid_selection" }, { TargetProposal.fromSelection({}) })
    assert.same({ nil, "invalid_target" }, {
      TargetProposal.fromSelection({ creature = creature("42"), config = {}, priority = 1 }),
    })
    assert.same({ nil, "invalid_priority" }, {
      TargetProposal.fromSelection({ creature = creature(42), config = {}, priority = 0 }),
    })
  end)

  it("keeps execution behind intelligence arbitration and AttackStateMachine", function()
    local coordinator = assert(io.open("targetbot/target_coordinator.lua")):read("*a")
    local attack = assert(io.open("targetbot/attack_coordinator.lua")):read("*a")

    assert.is_falsy(coordinator:find("TargetBot.Creature.attack(bestTarget, targetCount, false)", 1, true))
    assert.is_truthy(coordinator:find("TargetBot.Creature.attack(selection, targetCount, false)", 1, true))
    assert.is_truthy(attack:find("AttackStateMachine.requestSwitch(creature, priority * 100)", 1, true))
    assert.is_falsy(attack:find("g_game.attack(", 1, true))
  end)
end)

describe("TargetBot intelligence runtime wiring", function()
  it("routes both targeting loops through proposal arbitration", function()
    local file = assert(io.open("targetbot/target_coordinator.lua", "r"))
    local source = file:read("*a")
    file:close()
    local _, calls = source:gsub("pcall%(executeIntelligenceSelection", "")
    assert.equals(2, calls)
    assert.is_truthy(source:find("Intelligence.decisions:select", 1, true))
  end)
end)
