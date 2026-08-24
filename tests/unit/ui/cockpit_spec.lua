local function fresh()
  _G.nExBot = { UI = {} }
  dofile("ui/core/view_model.lua")
  return dofile("ui/modules/cockpit.lua")
end

describe("Hunt cockpit", function()
  local Cockpit

  before_each(function()
    Cockpit = fresh()
  end)

  it("keeps unavailable engine state distinct from stopped", function()
    local view = Cockpit.viewModel({ cave = nil, target = false, heal = true, loot = false }).snapshot

    assert.are_equal("UNKNOWN", view.engines[1].status)
    assert.are_equal("DISABLED", view.engines[2].status)
    assert.are_equal("ACTIVE", view.engines[3].status)
  end)

  it("exposes one explicit toggle and editor action per engine", function()
    local engines = Cockpit.viewModel({}).snapshot.engines

    assert.are_same({ "toggle_cavebot", "toggle_targetbot", "toggle_healing", "toggle_looting" }, {
      engines[1].toggleAction, engines[2].toggleAction, engines[3].toggleAction, engines[4].toggleAction,
    })
    assert.are_same({ "open_cavebot", "open_targetbot", "open_healing", "open_looting" }, {
      engines[1].editorAction, engines[2].editorAction, engines[3].editorAction, engines[4].editorAction,
    })
    assert.are_same({ 3003, 3155, 23375, 2854 }, {
      engines[1].itemId, engines[2].itemId, engines[3].itemId, engines[4].itemId,
    })
  end)

  it("shows no warning when healthy and preserves actionable issues", function()
    local healthy = Cockpit.viewModel({ issues = {} }).snapshot
    local degraded = Cockpit.viewModel({ issues = { { message = "Low supplies" } } }).snapshot

    assert.are_equal("No issues", healthy.attention)
    assert.are_equal("Low supplies", degraded.attention)
  end)

  it("calls OTClient percentage helpers instead of displaying function values", function()
    _G.player = nil
    _G.hppercent = function() return 87 end
    _G.manapercent = function() return 64 end

    local view = Cockpit.statusProvider().snapshot
    assert.are_equal(87, view.hp)
    assert.are_equal(64, view.mana)

    _G.hppercent, _G.manapercent = nil, nil
  end)
end)
