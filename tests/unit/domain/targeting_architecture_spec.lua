local function read(path)
  local file = assert(io.open(path, "r"))
  local contents = file:read("*a")
  file:close()
  return contents
end

describe("TargetBot reachability architecture", function()
  it("keeps the attack client call behind the state-machine boundary", function()
    local handle = assert(io.popen("find targetbot -name '*.lua' -type f"))
    for path in handle:lines() do
      local source = read(path):gsub("%-%-[^\n]*", "")
      if path ~= "targetbot/attack_state_machine.lua" then
        assert.is_nil(source:match("g_game%.attack%s*%(") or source:match("Client%.attack%s*%("), path)
      end
    end
    handle:close()
  end)

  it("has no close-range or current-target reachability bypass", function()
    local source = read("targetbot/target_coordinator.lua")
    assert.is_nil(source:match("Fake short path"))
    assert.is_nil(source:match("local simplePath"))
    assert.is_nil(source:match("not isCurrentTarget"))
    assert.is_truthy(source:match("TargetReachability%.evaluate"))
  end)

  it("does not retain the old floor-only creature path cache", function()
    local source = read("targetbot/target_pathfinding.lua")
    assert.is_nil(source:match("playerZ"))
    assert.is_nil(source:match("creatureZ"))
    assert.is_truthy(source:match("TargetReachability"))
  end)
end)

describe("intelligence reachability ownership", function()
  it("does not keep a second unreachable tracker or cancel attacks outside ASM", function()
    local file = assert(io.open("targetbot/attack_coordinator.lua", "r"))
    local source = file:read("*a")
    file:close()
    assert.is_nil(source:find("UnreachableTracker", 1, true))
    assert.is_nil(source:find("cancelAttackAndFollow", 1, true))
  end)

  it("keeps autonomous attack calls behind AttackStateMachine", function()
    for _, path in ipairs({ "cavebot/actions.lua", "cavebot/clear_tile.lua", "cavebot/stand_lure.lua", "core/hold_target.lua" }) do
      local file = assert(io.open(path, "r"))
      local source = file:read("*a")
      file:close()
      assert.is_nil(source:match("[^%w_%.]attack%s*%(") , path)
    end
  end)

  it("reports every coordinated movement decision", function()
    local file = assert(io.open("targetbot/movement_coordinator.lua", "r"))
    local source = file:read("*a")
    file:close()
    assert.is_truthy(source:find('EventBus.emit("movement:outcome"', 1, true))
  end)

  it("routes wave avoidance through intelligence arbitration and MovementCoordinator", function()
    local file = assert(io.open("targetbot/attack_waves.lua", "r"))
    local source = file:read("*a")
    file:close()
    assert.is_nil(source:find("TargetBot.walkTo", 1, true))
    assert.is_truthy(source:find("Intelligence.waveBeam:update", 1, true))
    assert.is_truthy(source:find("MovementCoordinator.avoidWave", 1, true))
  end)

  it("removes direct movement and chase writers from attack coordination", function()
    local file = assert(io.open("targetbot/attack_coordinator.lua", "r"))
    local source = file:read("*a")
    file:close()
    for _, call in ipairs({ "TargetBot.walkTo", "player:autoWalk", "turn(" }) do
      assert.is_nil(source:find(call, 1, true), call)
    end
    assert.is_truthy(source:find("MovementCoordinator.setChaseMode(useNativeChase)", 1, true))
  end)

  it("keeps deterministic CaveBot paths outside combat movement arbitration", function()
    local cave = assert(io.open("cavebot/walking.lua", "r")):read("*a")
    local movement = assert(io.open("targetbot/movement_coordinator.lua", "r")):read("*a")
    assert.is_nil(cave:find("MovementCoordinator", 1, true))
    assert.is_nil(movement:find("CAVEBOT", 1, true))
  end)

  it("keeps TargetBot path execution behind MovementCoordinator", function()
    local handle = assert(io.popen("find targetbot -name '*.lua' -type f"))
    for path in handle:lines() do
      if path ~= "targetbot/movement_coordinator.lua" and path ~= "targetbot/walking.lua" then
        local source = read(path):gsub("%-%-[^\n]*", "")
        assert.is_nil(source:find("TargetBot.walkTo", 1, true), path)
      end
    end
    handle:close()
  end)

  it("keeps native chase writes inside ChaseController", function()
    local handle = assert(io.popen("find targetbot -name '*.lua' -type f"))
    for path in handle:lines() do
      if path ~= "targetbot/chase_controller.lua" then
        local source = read(path):gsub("%-%-[^\n]*", "")
        assert.is_nil(source:match("Client%.setChaseMode%s*%(") or source:match("g_game%.setChaseMode%s*%(") or source:match("game%.setChaseMode%s*%("), path)
      end
    end
    handle:close()
  end)

  it("exports chase control and rejects no-op movement intents", function()
    local chase = read("targetbot/chase_controller.lua")
    local movement = read("targetbot/movement_coordinator.lua")
    assert.is_truthy(chase:find("ChaseController = {}", 1, true))
    assert.is_nil(chase:find("local ChaseController = {}", 1, true))
    assert.is_truthy(movement:find('return false, "already_at_position"', 1, true))
  end)

  it("loads the native chase owner before movement and targeting consumers", function()
    local loader = read("core/cavebot.lua")
    local chase = assert(loader:find('dofile("/targetbot/chase_controller.lua")', 1, true))
    local movement = assert(loader:find('dofile("/targetbot/movement_coordinator.lua")', 1, true))
    local targeting = assert(loader:find('dofile("/targetbot/event_targeting.lua")', 1, true))
    assert.is_true(chase < movement and movement < targeting)
    assert.is_nil(read("targetbot/event_targeting.lua"):find('dofile("nExBot/targetbot/chase_controller.lua")', 1, true))
  end)

  it("connects CaveBot pause, resume, and waypoint outcomes to intelligence route state", function()
    local cave = assert(io.open("cavebot/cavebot.lua", "r")):read("*a")
    assert.is_truthy(cave:find('pauseIntelligenceRoute("targetbot")', 1, true))
    assert.is_truthy(cave:find('intelligenceRoute:resume()', 1, true))
    assert.is_truthy(cave:find('"waypoint_reached"', 1, true))
    assert.is_truthy(cave:find('"path_failed"', 1, true))
  end)

  it("keeps the sighting pipeline connected to acquisition", function()
    local source = read("targetbot/event_targeting.lua")
    local emit = source:find('EventBus.emit("targeting/creature_seen"', 1, true)
    local call = source:find("TargetAcquisition.evaluateTarget(creature, priority, path)", 1, true)
    assert.is_truthy(emit)
    assert.is_truthy(call)
    assert.is_true(call > emit)
  end)

  it("guards intelligence calls against stale singleton state", function()
    local cave = read("cavebot/cavebot.lua")
    assert.is_truthy(cave:find("if nExBot.Intelligence.advanceGeneration then", 1, true))
  end)
end)
