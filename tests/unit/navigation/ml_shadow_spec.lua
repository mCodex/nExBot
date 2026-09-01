-- tests/unit/navigation/ml_shadow_spec.lua
-- MLShadow (T8): recommendations are never authoritative; the guardrail
-- rejects any recommendation whose step fails the strict validator.

local Fake = require("tests.helpers.fake_otclient")
local AdapterFake = require("navigation.adapter_fake")
local Session = require("navigation.session")
local MLShadow = require("navigation.ml_shadow")
local Obs = require("navigation.observability")
local D = require("navigation.domain")

describe("MLShadow", function()
  local world, player, port, session, ml
  local A = { x = 10, y = 10, z = 7 }

  before_each(function()
    world = Fake.newWorld()
    world:freespaceRect(5, 5, 16, 15, 7)
    player = Fake.newPlayer(world, A)
    port = AdapterFake.create(world, player)
    session = Session.new(port, {})
    ml = MLShadow.new(session)
    Obs.resetMetrics()
  end)

  local function observe(dir, edgeKind)
    return ml:observe({
      playerPos = player:getPosition(),
      world = port.world,
      recommendation = { direction = dir },
      edgeKind = edgeKind or D.EDGE_KIND.WALK,
    })
  end

  it("accepts a recommendation that passes the strict validator", function()
    local ok = observe(D.DIR.EAST)
    assert.is_true(ok)
    local s = ml.snapshot()
    assert.equals(1, s.recommendations)
    assert.equals(1, s.agreements)
    assert.equals(0, s.guardrailRejections)
    assert.equals(1, s.agreementRate)
  end)

  it("rejects a recommendation into a wall (never authorizes invalid steps)", function()
    world:setWall({ x = 11, y = 10, z = 7 })
    local ok = observe(D.DIR.EAST)
    assert.is_false(ok)
    local s = ml.snapshot()
    assert.equals(1, s.guardrailRejections)
    assert.equals(0, s.agreements)
    assert.equals("STATIC_UNWALKABLE", s.last.reason)
    assert.equals(1, Obs.snapshot().mlGuardrailRejections)
  end)

  it("rejects a recommendation across a hazard unless the edge allows it", function()
    world:setHazard({ x = 11, y = 10, z = 7 }, "FIRE_FIELD")
    assert.is_false(observe(D.DIR.EAST))
    assert.is_true(observe(D.DIR.EAST, D.EDGE_KIND.FIELD_CROSSING))
  end)

  it("rejects a recommendation that would enter a floor-change tile", function()
    world:setFloorChange({ x = 11, y = 10, z = 7 })
    assert.is_false(observe(D.DIR.EAST))
  end)
end)