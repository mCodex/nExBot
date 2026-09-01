local function read(path)
  local file = assert(io.open(path, "r"))
  local source = file:read("*a")
  file:close()
  return source
end

describe("combat ownership", function()
  it("blocks CaveBot when AttackFSM owns a live configured target", function()
    local coordinator = read("targetbot/target_coordinator.lua")
    local cavebot = read("cavebot/cavebot.lua")

    assert.is_truthy(coordinator:find("TargetBot.CombatOwnership", 1, true))
    for _, method in ipairs({ "isBlockingRoute", "getTarget", "hasLiveConfiguredTarget", "canReleaseTarget" }) do
      assert.is_truthy(coordinator:find(method, 1, true), method)
    end
    assert.is_truthy(cavebot:find("CombatOwnership.isBlockingRoute", 1, true))
    assert.is_nil(cavebot:find("AttackStateMachine.isActive", 1, true))
  end)
end)
