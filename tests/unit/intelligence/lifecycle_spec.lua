local function loadModule(options)
  _G.IntelligenceLifecycle = nil
  dofile("core/intelligence/foundation/lifecycle.lua")
  return IntelligenceLifecycle.new(options)
end

describe("Intelligence Lifecycle", function()
  it("initializes and terminates exactly once", function()
    local registered, removed = 0, 0
    local lifecycle = loadModule({
      register = function()
        registered = registered + 1
        return function() removed = removed + 1 end
      end,
    })

    assert.is_true(lifecycle:initialize())
    assert.is_false(lifecycle:initialize())
    assert.equals(1, registered)
    assert.is_true(lifecycle:terminate())
    assert.is_false(lifecycle:terminate())
    assert.equals(1, removed)
  end)

  it("invalidates callbacks when their generation advances", function()
    local lifecycle = loadModule()
    lifecycle:initialize()
    local calls = 0
    local callback = lifecycle:guard("route", function(value) calls = calls + value end)

    assert.equals(0, callback(1))
    assert.equals(1, lifecycle:advance("route"))
    assert.is_nil(callback(10))
    assert.equals(1, calls)
    assert.equals(1, lifecycle:generation("route"))
  end)
end)
