local Harness = require("tests.helpers.widget_harness")

local function loadRegistry()
  Harness.install()
  _G.nExBot = _G.nExBot or {}
  _G.nExBot.UI = _G.nExBot.UI or {}
  return dofile("ui/core/module_registry.lua")
end

describe("ModuleRegistry", function()
  before_each(function()
    Harness.reset()
    _G.nExBot = { UI = {} }
    loadRegistry()
  end)

  it("exposes a global registry table", function()
    assert.is_table(nExBot.UI.ModuleRegistry)
  end)

  it("registers a module and reads it back in O(1)", function()
    local Registry = nExBot.UI.ModuleRegistry
    Registry.register({
      id = "dashboard",
      label = "Dashboard",
      icon = "dashboard",
      order = 10,
      sections = { "Overview" },
    })
    assert.is_table(Registry.get("dashboard"))
    assert.are_equal("dashboard", Registry.get("dashboard").id)
    assert.is_nil(Registry.get("nonexistent"))
  end)

  it("rejects duplicate module ids", function()
    local Registry = nExBot.UI.ModuleRegistry
    local ok1 = Registry.register({ id = "x", label = "X", order = 1 })
    local ok2 = Registry.register({ id = "x", label = "X2", order = 2 })
    assert.is_true(ok1)
    assert.is_false(ok2)
  end)

  it("rejects modules without required fields", function()
    local Registry = nExBot.UI.ModuleRegistry
    assert.is_false(Registry.register({ id = "noid", order = 1 }))
    assert.is_false(Registry.register({ id = "nolabel", order = 1 }))
    assert.is_false(Registry.register({ id = "noorder", label = "X" }))
  end)

  it("lists modules in deterministic order", function()
    local Registry = nExBot.UI.ModuleRegistry
    Registry.register({ id = "zeta", label = "Z", order = 30 })
    Registry.register({ id = "alpha", label = "A", order = 10 })
    Registry.register({ id = "mid", label = "M", order = 20 })
    local ids = Registry.ids()
    assert.same({ "alpha", "mid", "zeta" }, ids)
  end)

  it("each module has a unique id, icon, and registered sections", function()
    local Registry = nExBot.UI.ModuleRegistry
    Registry.register({
      id = "cavebot", label = "CaveBot", icon = "cavebot", order = 1,
      sections = { "Routes", "Recovery" },
    })
    Registry.register({
      id = "targetbot", label = "TargetBot", icon = "targetbot", order = 2,
      sections = { "Creatures" },
    })
    local errors = Registry.validate()
    assert.are_equal(0, #errors)
  end)

  it("defaults the icon to the module id when unspecified", function()
    local Registry = nExBot.UI.ModuleRegistry
    Registry.register({ id = "defaulticon", label = "Bad", order = 1, sections = {} })
    assert.are_equal("defaulticon", Registry.get("defaulticon").icon)
    assert.are_equal(0, #Registry.validate())
  end)

  it("a rejected duplicate leaves the original intact", function()
    local Registry = nExBot.UI.ModuleRegistry
    Registry.register({ id = "a", label = "A", order = 1 })
    Registry.register({ id = "a", label = "A", order = 2 })
    assert.are_equal("A", Registry.get("a").label)
    assert.are_equal(1, Registry.get("a").order)
  end)

  it("an invalid registration is not stored at all", function()
    local Registry = nExBot.UI.ModuleRegistry
    Registry.register({ id = "broken", label = "Broken" })
    assert.is_nil(Registry.get("broken"))
  end)
end)
