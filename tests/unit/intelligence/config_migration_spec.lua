local Migration = dofile("core/intelligence/foundation/config_migration.lua")

describe("intelligence configuration migration", function()
  it("preserves user configuration and discards transient learned state", function()
    local migrated = Migration.migrate({
      unified = {
        targetbot = { enabled = true, selectedConfig = "knight", combatActive = true },
        cavebot = { enabled = true, selectedConfig = "route-a" },
        tools = { fishing = { dropFish = false } },
      },
      targetbotProfile = { Dragon = { priority = 5, danger = 8 } },
      cavebotProfile = { config = { walkDelay = 75 }, extensions = { "goto:100,100,7" } },
      learned = { monster = { Dragon = { samples = 999 } } },
    })

    assert.equals(5, migrated.version)
    assert.same({ enabled = true, selectedConfig = "knight" }, migrated.settings.targetbot)
    assert.same({ enabled = true, selectedConfig = "route-a" }, migrated.settings.cavebot)
    assert.same({ fishing = { dropFish = false } }, migrated.settings.tools)
    assert.same({ Dragon = { priority = 5, danger = 8 } }, migrated.profiles.targetbot)
    assert.same({ config = { walkDelay = 75 }, extensions = { "goto:100,100,7" } }, migrated.profiles.cavebot)
    assert.is_nil(migrated.learned)
    assert.equals("SHADOW", migrated.models.defaultMode)
  end)

  it("is idempotent for an existing intelligence document", function()
    local existing = { version = 5, settings = { targetbot = {} }, profiles = {}, models = { defaultMode = "SHADOW" } }
    assert.same(existing, Migration.migrate({ intelligence = existing }))
  end)

  it("copies selected profile contents without rewriting cavebot cfg", function()
    local files = {
      ["/bot/default/targetbot_configs/hunt.json"] = "target-json",
      ["/bot/default/cavebot_configs/route.cfg"] = "label:Start\ngoto:100,100,7",
    }
    local resources = {
      fileExists = function(path) return files[path] ~= nil end,
      readFileContents = function(path) return files[path] end,
    }
    local codec = { decode = function(content)
      assert.equals("target-json", content)
      return { Dragon = { priority = 5 } }
    end }
    assert.same({
      targetbot = { name = "hunt", content = { Dragon = { priority = 5 } } },
      cavebot = { name = "route", content = "label:Start\ngoto:100,100,7" },
    }, Migration.readProfiles(resources, codec, "/bot/default/", { targetbot = "hunt", cavebot = "route" }))
  end)
end)
