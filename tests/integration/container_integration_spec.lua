local Discovery = dofile("core/containers/discovery.lua")

describe("Container Integration", function()
  before_each(function()
    _G.g_game = nil
    _G.player = nil
    _G.Client = nil
  end)

  it("completes full discovery cycle with no containers", function()
    _G.g_game = { getContainers = function() return {} end }
    
    local d = Discovery.new()
    d:start()
    
    local r = d:getReadiness()
    assert.equals("ready", r.status)
    assert.is_true(r.mainBackpackReady)
  end)

  it("handles cancel during discovery", function()
    _G.g_game = { getContainers = function() return {} end }
    
    local d = Discovery.new()
    d:start()
    d:cancel()
    
    local r = d:getReadiness()
    assert.equals("ready", r.status)
  end)

  it("maintains generation across operations", function()
    _G.g_game = { getContainers = function() return {} end }
    
    local d = Discovery.new()
    local gen1 = d.stateMachine.generation
    d:start()
    d:cancel()
    local gen2 = d.stateMachine.generation
    
    assert.equals(gen1 + 1, gen2)
  end)

  it("provides readiness snapshot", function()
    _G.g_game = { getContainers = function() return {} end }
    
    local d = Discovery.new()
    d:start()
    
    local r = d:getReadiness()
    assert.is_number(r.generation)
    assert.is_string(r.status)
    assert.is_boolean(r.mainBackpackReady)
    assert.is_boolean(r.quiverRequired)
    assert.is_number(r.queuedCount)
    assert.is_number(r.openingCount)
    assert.is_number(r.openedCount)
    assert.is_number(r.inspectedCount)
    assert.is_number(r.failedCount)
  end)
end)
