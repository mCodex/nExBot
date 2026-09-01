describe("diagnostics", function()
  before_each(function()
    package.loaded["ui.modules.diagnostics"] = nil
    _G.nExBot = {
      Shared = { nowMs = function() return 10000 end },
      UI = {
        ["ui.core.view_model"] = require("ui.core.view_model"),
        ["ui.modules.page"] = { render = function() end },
      },
      Intelligence = {},
    }
  end)

  it("keeps Bot Doctor off the fast cockpit refresh path", function()
    local inspections = 0
    _G.IntelligenceBotDoctor = {
      capture = function() return {} end,
      inspect = function()
        inspections = inspections + 1
        return { { code = "TEST", message = "cached" } }
      end,
    }

    local Diagnostics = require("ui.modules.diagnostics")
    assert.are_equal(1, #Diagnostics.currentIssues())
    assert.are_equal(1, #Diagnostics.currentIssues())
    assert.are_equal(1, inspections)

    Diagnostics.refreshIssues()
    assert.are_equal(2, inspections)
  end)

  it("presents each issue as one actionable row with secondary raw details", function()
    local Diagnostics = require("ui.modules.diagnostics")
    local view = Diagnostics.viewModel({
      issueCount = 1,
      issues = {
        {
          code = "SLOW_TICK",
          subsystem = "UnifiedTick",
          severity = "warning",
          message = "Tick exceeded its budget.",
          action = "Disable expensive scripts.",
          timestamp = "10:00",
        },
      },
    }).snapshot

    assert.are_equal("SLOW_TICK - Tick exceeded its budget.", view.sections[1].items[1].title)
    assert.are_equal("Next: Disable expensive scripts.", view.sections[1].items[1].subtitle)
    assert.are_equal("WARNING", view.sections[1].items[1].status)
    assert.are_same({ { key = "SLOW_TICK", value = "UnifiedTick | 10:00" } }, view.sections[2].rows)
    assert.are_equal(0, #view.errors)
  end)

  it("shows a concise healthy state when Bot Doctor has no issues", function()
    local Diagnostics = require("ui.modules.diagnostics")
    local view = Diagnostics.viewModel({ issues = {}, issueCount = 0 }).snapshot

    assert.are_equal("No issues found", view.sections[1].items[1].title)
    assert.are_equal("OK", view.sections[1].items[1].status)
    assert.are_equal("subscriptions", view.sections[2].id)
  end)
end)
