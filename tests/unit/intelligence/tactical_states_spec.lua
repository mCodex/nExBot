local function load(name)
  return dofile("core/intelligence/decisions/" .. name .. ".lua")
end

describe("intelligence tactical proposal states", function()
  it("applies lure hysteresis, tracks evidence, and aborts safely", function()
    local lure = load("dynamic_lure_state").new({ minCount = 3, maxCount = 4 })

    local proposal = lure:update({ snapshotGeneration = 2, creatures = { 11 } }, {
      generations = { snapshot = 2, combat = 4 }, now = 100,
    })
    assert.equals("gathering", lure.state)
    assert.same({ 11 }, proposal.evidence.participants)
    assert.equals(0.7, proposal.confidence)

    assert.is_truthy(lure:update({ snapshotGeneration = 3, creatures = { 11, 12 } }, {
      generations = { snapshot = 3, combat = 4 }, now = 110,
    }))
    assert.equals("gathering", lure.state)

    assert.is_truthy(lure:update({ snapshotGeneration = 4, creatures = { 11, 12, 13 } }, {
      generations = { snapshot = 4, combat = 4 }, now = 120,
    }))
    assert.equals("gathering", lure.state)

    assert.is_nil(lure:update({ snapshotGeneration = 5, creatures = { 11, 12, 13, 14 } }, {
      generations = { snapshot = 5 }, now = 125,
    }))
    assert.equals("completed", lure.state)

    local aborted, reason = lure:update({ snapshotGeneration = 6, creatures = { 11 }, safe = false }, {
      generations = { snapshot = 6 }, now = 130,
    })
    assert.is_nil(aborted)
    assert.equals("unsafe_lure", reason)
    assert.equals("aborted", lure.state)
  end)

  it("pulls one participant, holds through hysteresis, and ignores stale input", function()
    local pull = load("pull_state").new({ enterDistance = 5, exitDistance = 2 })
    local context = { generations = { snapshot = 7, route = 3 }, now = 200 }

    local proposal = pull:update({ snapshotGeneration = 7, participantId = 42, distance = 6 }, context)
    assert.equals("pulling", pull.state)
    assert.equals(42, proposal.evidence.participantId)
    assert.equals("pull", proposal.action)

    proposal = pull:update({ snapshotGeneration = 8, participantId = 42, distance = 3 }, {
      generations = { snapshot = 8, route = 3 }, now = 210,
    })
    assert.equals("pulling", pull.state)
    assert.equals("pull", proposal.action)

    local stale, reason = pull:update({ snapshotGeneration = 7, participantId = 42, distance = 1 }, {
      generations = { snapshot = 8 }, now = 220,
    })
    assert.is_nil(stale)
    assert.equals("stale_snapshot_generation", reason)
    assert.equals("pulling", pull.state)

    assert.is_nil(pull:update({ snapshotGeneration = 9, participantId = 42, distance = 2 }, {
      generations = { snapshot = 9 }, now = 230,
    }))
    assert.equals("completed", pull.state)
  end)

  it("weights wave evidence, uses hysteresis, and emits proposal-only avoidance", function()
    local wave = load("wave_beam_state").new({ enterConfidence = 0.7, exitConfidence = 0.4 })
    local context = { generations = { snapshot = 10, combat = 6 }, now = 300 }

    local proposal = wave:update({ snapshotGeneration = 10, threatId = 9, kind = "beam", evidence = {
      { name = "facing", confidence = 0.5, weight = 2 },
      { name = "cooldown", confidence = 0.5, weight = 1 },
    } }, context)
    assert.equals("watching", wave.state)
    assert.is_nil(proposal)

    proposal = wave:update({ snapshotGeneration = 11, threatId = 9, kind = "beam", evidence = {
      { name = "facing", confidence = 0.9, weight = 2 },
      { name = "cooldown", confidence = 0.8, weight = 1 },
    } }, { generations = { snapshot = 11, combat = 6 }, now = 310 })
    assert.equals("avoiding", wave.state)
    assert.equals("avoid_beam", proposal.action)
    assert.near(0.8667, proposal.confidence, 0.0001)
    assert.same({ facing = 0.9, cooldown = 0.8 }, proposal.evidence.sources)

    proposal = wave:update({ snapshotGeneration = 12, threatId = 9, kind = "beam", evidence = {
      { name = "facing", confidence = 0.5, weight = 1 },
    } }, { generations = { snapshot = 12 }, now = 320 })
    assert.equals("avoiding", wave.state)
    assert.is_truthy(proposal)

    local aborted, reason = wave:update({ snapshotGeneration = 13, threatId = 9, safe = false, evidence = {} }, {
      generations = { snapshot = 13 }, now = 330,
    })
    assert.is_nil(aborted)
    assert.equals("unsafe_wave_avoidance", reason)
    assert.equals("aborted", wave.state)
  end)
end)
