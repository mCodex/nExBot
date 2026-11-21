local Presenter = dofile("core/intelligence/ui/ui_presenter.lua")

describe("intelligence UI presenter", function()
  local now
  local state
  local calls
  local presenter

  before_each(function()
    now = 100
    state = {
      lifecycle = { active = true },
      route = { state = "RUNNING" },
      models = { mode = "SHADOW" },
      metrics = { tickMs = 3 },
    }
    calls = {}
    presenter = Presenter.new({
      state = state,
      nowMs = function() return now end,
      refreshMs = 100,
      commands = {
        pause = function(args) calls[#calls + 1] = { "pause", args.reason } return true end,
        resetModels = { destructive = true, run = function() calls[#calls + 1] = { "reset" } return true end },
      },
    })
  end)

  it("maps shared domain state and throttles high-frequency refreshes", function()
    local first = presenter:view({ width = 1200, platform = "desktop" })
    assert.equals("wide", first.layout.mode)
    assert.equals("RUNNING", first.route.state)
    assert.equals("SHADOW", first.models.mode)

    state.route.state = "PAUSED"
    assert.equals(first, presenter:view({ width = 1200, platform = "desktop" }))
    assert.equals("single", presenter:view({ width = 500, platform = "web" }).layout.mode)
    now = 200
    local refreshed = presenter:view({ width = 1200, platform = "desktop" })
    assert.equals("PAUSED", refreshed.route.state)
    assert.are_not.equal(first, refreshed)
  end)

  it("uses one responsive policy for desktop, mobile, and web", function()
    assert.same({ mode = "single", columns = 1, touch = true },
      Presenter.layout({ width = 500, platform = "mobile" }))
    assert.same({ mode = "compact", columns = 1, touch = false },
      Presenter.layout({ width = 700, platform = "web" }))
    assert.same({ mode = "wide", columns = 2, touch = false },
      Presenter.layout({ width = 1200, platform = "desktop" }))
  end)

  it("dispatches application commands and confirms destructive actions", function()
    assert.is_true(presenter:execute("pause", { reason = "user" }))
    assert.same({ "pause", "user" }, calls[1])
    assert.is_false(presenter:execute("resetModels"))
    assert.equals("confirmation_required", presenter:lastError())
    assert.is_true(presenter:execute("resetModels", {}, true))
    assert.same({ "reset" }, calls[2])
    assert.is_false(presenter:execute("missing"))
    assert.equals("unknown_command", presenter:lastError())
  end)

  it("cleans up lifecycle state and rejects work after termination", function()
    presenter:terminate()
    assert.is_false(presenter:view({ width = 1200 }))
    assert.is_false(presenter:execute("pause", { reason = "late" }))
    assert.equals("terminated", presenter:lastError())
    assert.same({}, calls)
    assert.is_false(presenter:terminate())
  end)
end)
