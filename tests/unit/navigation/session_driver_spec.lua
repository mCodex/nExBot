-- tests/unit/navigation/session_driver_spec.lua
-- SessionDriver: maps a NavigationResult onto the goto callback contract.
local Fake = require("tests.helpers.fake_otclient")
local AdapterFake = require("navigation.adapter_fake")
local Bridge = require("navigation.legacy_bridge")
local SD = require("cavebot.session_driver")

describe("SessionDriver", function()
  local world, player, port, bridge
  local A = { x = 10, y = 10, z = 7 }
  local B = { x = 13, y = 10, z = 7 }

  before_each(function()
    world = Fake.newWorld()
    world:freespaceRect(5, 5, 20, 15, 7)
    player = Fake.newPlayer(world, A)
    port = AdapterFake.create(world, player, { onEvent = function() end })
    bridge = Bridge.new({ port = port, owner = "CAVEBOT" })
  end)

  it("returns 'walking' on a dispatched step", function()
    bridge:goTo(B, { playerPos = A })
    local walk, _ = SD.tickAndMap(bridge, A, { preempted = false, combatActive = false })
    assert.equals("walking", walk)
  end)

  it("returns 'retry' while preempted (never walks during combat)", function()
    bridge:goTo(B, { playerPos = A })
    local walk = SD.tickAndMap(bridge, A, { preempted = true, combatActive = true })
    assert.equals("retry", walk)
  end)

  it("gates on a built route", function()
    assert.is_false(SD.shouldUse(bridge))
    bridge:goTo(B, { playerPos = A })
    assert.is_true(SD.shouldUse(bridge))
  end)

  it("maps statuses to the callback contract (pure)", function()
    local nav = {
      isRouteBuilt = function() return true end,
      tick = function(self, o)
        return { status = o.preempted and "WAITING_BLOCKER" or "PROGRESS" }
      end,
    }
    assert.equals("walking", SD.tickAndMap(nav, A, { preempted = false }))
    assert.equals("retry", SD.tickAndMap(nav, A, { preempted = true }))
  end)
end)
