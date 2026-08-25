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
end)
