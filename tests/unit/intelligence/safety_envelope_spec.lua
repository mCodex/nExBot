local function loadModule()
  _G.IntelligenceSafetyEnvelope = nil
  return dofile("core/intelligence/decisions/safety_envelope.lua")
end

describe("Intelligence Safety Envelope", function()
  it("returns the first explainable hard-safety rejection", function()
    local envelope = loadModule().new({ validators = {
      { name = "valid_tile", check = function(_, context) return context.tileValid end },
      { name = "escape_route", check = function(_, context)
        return context.escapeRouteValid, "pull_requires_escape_route"
      end },
    } })

    local valid, reason = envelope:validate({}, { tileValid = true, escapeRouteValid = false })

    assert.is_false(valid)
    assert.equals("pull_requires_escape_route", reason)
  end)

  it("rejects validator errors and accepts only when every validator passes", function()
    local broken = loadModule().new({ validators = {
      { name = "target", check = function() error("bad validator") end },
    } })
    assert.same({ false, "validator_error:target" }, { broken:validate({}, {}) })

    local safe = loadModule().new({ validators = {
      { name = "target", check = function() return true end },
      { name = "tile", check = function() return true end },
    } })
    assert.is_true(safe:validate({}, {}))
  end)
end)
