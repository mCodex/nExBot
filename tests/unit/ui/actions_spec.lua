local function loadActions()
  _G.nExBot = { UI = {} }
  return dofile("ui/core/actions.lua")
end

describe("Actions", function()
  local Actions

  before_each(function()
    Actions = loadActions()
  end)

  it("has no open_macros handler (no reachable host macro editor)", function()
    assert.is_nil(Actions.handlers.open_macros)
  end)

  it("does not expose removed legacy navigation handlers", function()
    assert.is_nil(Actions.handlers.open_dashboard)
    assert.is_nil(Actions.handlers.open_conditions)
    assert.is_nil(Actions.handlers.open_cave_editor)
    assert.is_nil(Actions.handlers.open_target_editor)
    assert.is_nil(Actions.handlers.open_heal_config)
    assert.is_nil(Actions.handlers.open_loot_config)
    assert.is_nil(Actions.handlers.open_supply_config)
  end)

  it("returns a useful failure for unknown actions", function()
    local ok, reason = Actions.run("missing")
    assert.is_false(ok)
    assert.are_equal("Action unavailable", reason)
  end)

  it("returns a useful failure when an engine is unavailable", function()
    local ok, reason = Actions.run("toggle_cavebot")
    assert.is_false(ok)
    assert.are_equal("Action unavailable", reason)
  end)

  it("returns a useful failure when shell navigation is unavailable", function()
    local ok, reason = Actions.run("open_cavebot")
    assert.is_false(ok)
    assert.are_equal("Action unavailable", reason)
  end)

  it("keeps internal Lua paths out of user-facing failures", function()
    local message = Actions.userMessage("toggle_cavebot", '[string "/ui/core/actions.lua"]:35: boom')

    assert.are_equal("Cave unavailable", message)
    assert.is_nil(message:find(".lua", 1, true))
  end)

  it("maps unavailable navigation and attack actions to domain messages", function()
    assert.are_equal("Cave page unavailable", Actions.userMessage("open_cavebot", "Action unavailable"))
    assert.are_equal("Attack settings unavailable", Actions.userMessage("open_attack_config", "Action failed"))
  end)

  it("pause_all stops every available hunt engine", function()
    local stopped = {}
    _G.CaveBot = { setOff = function() stopped.cave = true end }
    _G.TargetBot = {
      setOff = function() stopped.target = true end,
    }
    _G.HealBot = { setOff = function() stopped.heal = true end }

    assert.is_true(Actions.run("pause_all"))
    assert.are_same({ cave = true, target = true, heal = true }, stopped)
    _G.CaveBot, _G.TargetBot, _G.HealBot = nil, nil, nil
  end)
end)
