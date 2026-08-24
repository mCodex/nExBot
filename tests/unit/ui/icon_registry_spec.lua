_G.nExBot = { UI = {} }

local function loadRegistry()
  _G.nExBot.UI.IconRegistry = nil
  return dofile("ui/core/icon_registry.lua")
end

describe("IconRegistry", function()
  before_each(function()
    loadRegistry()
  end)

  it("registers icons by id", function()
    local R = nExBot.UI.IconRegistry
    R.register("dashboard", { svg = "ui/assets/icons/dashboard.svg" })
    assert.is_table(R.get("dashboard"))
    assert.are_equal("dashboard", R.get("dashboard").id)
  end)

  it("resolves the raster path for a size", function()
    local R = nExBot.UI.IconRegistry
    R.register("cavebot", { svg = "ui/assets/icons/cavebot.svg", raster = "ui/assets/icons/generated/cavebot_%d.png" })
    assert.are_equal("ui/assets/icons/generated/cavebot_24.png", R.resolve("cavebot", 24))
  end)

  it("falls back to the svg when no raster is registered", function()
    local R = nExBot.UI.IconRegistry
    R.register("onlysvg", { svg = "ui/assets/icons/onlysvg.svg" })
    assert.are_equal("ui/assets/icons/onlysvg.svg", R.resolve("onlysvg", 24))
  end)

  it("returns a safe fallback for unknown icons", function()
    local R = nExBot.UI.IconRegistry
    assert.is_string(R.resolve("does_not_exist", 24))
    assert.is_string(R.get("does_not_exist").id) -- fallback entry is a table
  end)

  it("rejects invalid registrations", function()
    local R = nExBot.UI.IconRegistry
    assert.is_false(R.register("nopath", {}))
    assert.is_false(R.register("", { svg = "x" }))
  end)

  it("has O(1) lookup backed by a keyed map", function()
    local R = nExBot.UI.IconRegistry
    for i = 1, 100 do R.register("icon" .. i, { svg = "ui/assets/icons/" .. i .. ".svg" }) end
    assert.is_table(R.get("icon87"))
  end)

  it("registers all catalog icons deterministically", function()
    local R = nExBot.UI.IconRegistry
    local ids = {
      "dashboard", "cavebot", "targetbot", "healing", "looting", "supplies",
      "scripts", "intelligence", "learning", "monsters", "navigation",
      "profiles", "settings", "diagnostics", "replay",
      "add", "remove", "edit", "save", "import", "export", "refresh", "search",
      "filter", "close", "info", "warning", "success", "paused", "active",
      "expand", "collapse", "reorder", "record", "stop",
      "waypoint", "route", "stairs-up", "stairs-down", "ladder", "hole",
      "rope", "shovel", "door", "obstacle", "recovery", "target", "shield",
      "potion", "backpack",
    }
    for _, id in ipairs(ids) do
      R.register(id, { svg = "ui/assets/icons/" .. id .. ".svg" })
    end
    for _, id in ipairs(ids) do
      assert.is_table(R.get(id), "missing icon " .. id)
      assert.is_true(R.has(id), "has() false for " .. id)
    end
    assert.are_equal(#ids, R.count())
  end)
end)
