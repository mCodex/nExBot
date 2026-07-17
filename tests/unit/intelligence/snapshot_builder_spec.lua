local function loadModule()
  _G.IntelligenceSnapshotBuilder = nil
  return dofile("core/intelligence/foundation/snapshot_builder.lua")
end

describe("Intelligence Snapshot Builder", function()
  it("reconciles spectators once into a detached deterministic index", function()
    local calls = 0
    local spectators = {
      { id = 9, name = "Rat", isMonster = true, healthPercent = 70, position = { x = 102, y = 99, z = 7 } },
      { id = 3, name = "Orc", isMonster = true, healthPercent = 40, position = { x = 101, y = 100, z = 7 } },
    }
    local builder = loadModule().new({
      now = function() return 123 end,
      getSpectators = function() calls = calls + 1; return spectators end,
    })

    local snapshot = builder:build({
      generation = 4,
      player = { id = 1, health = 80, maxHealth = 100, mana = 30, maxMana = 60,
        position = { x = 100, y = 100, z = 7 } },
    })

    assert.equals(1, calls)
    assert.equals(3, snapshot.creatures[1].id)
    assert.equals(9, snapshot.creatures[2].id)
    assert.equals(snapshot.creatures[1], snapshot.creaturesById[3])
    assert.equals(2, snapshot.creaturesById[9].distance)
    assert.equals(2, #snapshot.visibleMonsters)
    assert.same({ x = 100, y = 100, z = 7 }, snapshot.player.position)

    spectators[2].healthPercent = 1
    spectators[2].position.x = 999
    assert.equals(40, snapshot.creaturesById[3].healthPercent)
    assert.equals(101, snapshot.creaturesById[3].position.x)
  end)

  it("rejects duplicate creature ids", function()
    local builder = loadModule().new({ getSpectators = function()
      return { { id = 2 }, { id = 2 } }
    end })
    assert.has_error(function() builder:build({ generation = 1 }) end,
      "duplicate creature id: 2")
  end)
end)
