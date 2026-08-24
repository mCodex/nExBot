local function loadActions()
  _G.nExBot = { UI = {} }
  return dofile("ui/core/actions.lua")
end

describe("Actions", function()
  local Actions

  before_each(function()
    Actions = loadActions()
  end)

  it("open_containers invokes Containers.initSetupWindow", function()
    local called = false
    _G.Containers = { initSetupWindow = function() called = true end }
    Actions.run("open_containers")
    assert.is_true(called)
    _G.Containers = nil
  end)

  it("open_containers is a no-op when Containers has no initSetupWindow", function()
    _G.Containers = {}
    assert.has_no.errors(function() Actions.run("open_containers") end)
    _G.Containers = nil
  end)

  it("has no open_macros handler (no reachable host macro editor)", function()
    assert.is_nil(Actions.handlers.open_macros)
  end)

  it("returns a useful failure for unknown actions", function()
    local ok, reason = Actions.run("missing")
    assert.is_false(ok)
    assert.are_equal("Action unavailable", reason)
  end)

  it("opens each editor without opening sibling editors", function()
    local opened = {}
    _G.CaveBot = { Editor = { show = function() opened.cave = true end } }
    _G.TargetBot = { showCreatureEditor = function() opened.target = true end }
    _G.HealBot = { show = function() opened.heal = true end }
    _G.Containers = { initSetupWindow = function() opened.loot = true end }

    assert.is_true(Actions.run("open_cave_editor"))
    assert.is_true(opened.cave)
    assert.is_nil(opened.target)
    assert.is_true(Actions.run("open_target_editor"))
    assert.is_true(Actions.run("open_heal_config"))
    assert.is_true(Actions.run("open_loot_config"))

    _G.CaveBot, _G.TargetBot, _G.HealBot, _G.Containers = nil, nil, nil, nil
  end)

  it("pause_all stops every available hunt engine", function()
    local stopped = {}
    _G.CaveBot = { setOff = function() stopped.cave = true end }
    _G.TargetBot = {
      setOff = function() stopped.target = true end,
      setLootingEnabled = function(value) stopped.loot = value == false end,
    }
    _G.HealBot = { setOff = function() stopped.heal = true end }

    assert.is_true(Actions.run("pause_all"))
    assert.are_same({ cave = true, target = true, heal = true, loot = true }, stopped)
    _G.CaveBot, _G.TargetBot, _G.HealBot = nil, nil, nil
  end)
end)
