local Discovery = dofile("core/containers/discovery.lua")

describe("Discovery", function()
  before_each(function()
    _G.g_game = nil
    _G.player = nil
    _G.Client = nil
  end)

  it("starts in IDLE", function()
    local d = Discovery.new()
    assert.equals("idle", d:getState())
  end)

  it("starts discovery", function()
    local d = Discovery.new()
    d:start()
    assert.not_equals("idle", d:getState())
  end)

  it("cancels discovery", function()
    local d = Discovery.new()
    d:start()
    d:cancel()
    assert.equals("cancelled", d:getState())
  end)

  it("returns readiness", function()
    local d = Discovery.new()
    local r = d:getReadiness()
    assert.equals("ready", r.status)
  end)

  it("completes with no containers", function()
    _G.g_game = { getContainers = function() return {} end }
    local d = Discovery.new()
    d:start()
    local r = d:getReadiness()
    assert.equals("ready", r.status)
  end)
end)
