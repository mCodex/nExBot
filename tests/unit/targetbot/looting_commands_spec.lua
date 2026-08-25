local function loadLooting(config)
  _G.nExBot = {
    Shared = {
      getClient = function() return nil end,
      getClientVersion = function() return 0 end,
    },
  }
  _G.TargetBot = {
    save = function() _G.lootSaveCount = _G.lootSaveCount + 1 end,
  }
  _G.lootSaveCount = 0
  _G.onTextMessage = function() end
  _G.onContainerOpen = function() end
  _G.onCreatureDisappear = function() end

  dofile("targetbot/looting.lua")
  TargetBot.Looting.update(config)
  return TargetBot.Looting
end

describe("Looting commands", function()
  it("edits an item id atomically and persists once", function()
    local looting = loadLooting({
      items = { { id = 100 }, { id = 101 } },
      containers = { { id = 200 } },
    })

    assert.is_true(looting.updateEntry(100, "item", 102, "item"))
    assert.same({ { id = 102 }, { id = 101 } }, looting.getConfig().items)
    assert.are_equal(1, lootSaveCount)
  end)

  it("moves an entry between item and container without partial duplicate changes", function()
    local looting = loadLooting({
      items = { { id = 100 }, { id = 101 } },
      containers = { { id = 200 } },
    })

    assert.is_true(looting.updateEntry(100, "item", 201, "container"))
    assert.same({ { id = 101 } }, looting.getConfig().items)
    assert.same({ { id = 200 }, { id = 201 } }, looting.getConfig().containers)
    assert.are_equal(1, lootSaveCount)

    assert.is_false(looting.updateEntry(101, "item", 200, "container"))
    assert.same({ { id = 101 } }, looting.getConfig().items)
    assert.same({ { id = 200 }, { id = 201 } }, looting.getConfig().containers)
    assert.are_equal(1, lootSaveCount)
  end)
end)
