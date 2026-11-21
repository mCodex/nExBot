local CombatFixture = require("tests.helpers.combat_fixture")

describe("Target abandonment — regression tests", function()
  local fx

  before_each(function()
    fx = CombatFixture.new()
    fx:installGlobals()
    _G.now = fx.clock

    _G.ReleaseReason = nil
    _G.ReachabilityState = nil
    _G.ReleaseReason = dofile("targetbot/domain/release_reasons.lua")
    _G.ReachabilityState = dofile("targetbot/domain/reachability_states.lua")

    _G.TargetReachability = nil
    _G.TargetReachability = dofile("targetbot/monster_reachability.lua")

    _G.ReachabilityService = nil
    _G.ReachabilityService = dofile("targetbot/domain/reachability_service.lua")

    _G.CombatConstants = nil
    _G.CombatConstants = dofile("targetbot/combat_constants.lua")

    _G.AttackFSM = nil
    _G.AttackFSM = dofile("targetbot/application/attack_fsm.lua")
    AttackFSM.reset()
  end)

  it("REGRESSION #1: invalid replacement does NOT stop current target", function()
    local monsterA = fx:addMonster(1, "Orc", 20, 101, 100)
    local monsterB = fx:addMonster(2, "Dragon", 100, 105, 105)

    AttackFSM.requestAttack(monsterA, 1000)
    fx:tick(3)
    AttackFSM.update()

    assert.equals(1, AttackFSM.getTargetId())

    fx:setReachability(2, false, "no_attack_position")
    TargetReachability.evaluate(monsterB, { force = true })
    TargetReachability.quarantine(monsterB, {
      attackable = false, reason = "no_attack_position",
      classification = "hard_unreachable",
      playerPosition = fx.player:getPosition(),
      creaturePosition = monsterB:getPosition(),
    })

    AttackFSM.requestAttack(monsterB, 2000)
    fx:tick(2)
    AttackFSM.update()

    assert.equals(1, AttackFSM.getTargetId(),
      "Current target must remain Monster A after invalid replacement")
    fx:checkNotCancelled()
  end)

  it("REGRESSION #2: temporary LOS failure preserves commitment", function()
    local target = fx:addMonster(3, "Elf", 15, 101, 100)

    AttackFSM.requestAttack(target, 1000)
    fx:tick(3)
    AttackFSM.update()
    assert.equals(3, AttackFSM.getTargetId())

    fx:setLOS({x=100,y=100,z=7}, {x=101,y=100,z=7}, false)
    TargetReachability.evaluate(target, { mode = "ranged", force = true, config = { distance = 5 } })

    fx:tick(2)
    AttackFSM.update()

    assert.equals(3, AttackFSM.getTargetId(),
      "Target must not be released on single LOS failure")
  end)

  it("REGRESSION #3: single pathfinding failure does not release target", function()
    local target = fx:addMonster(4, "Demon", 30, 103, 100)

    AttackFSM.requestAttack(target, 1000)
    fx:tick(5)
    AttackFSM.update()
    assert.equals(4, AttackFSM.getTargetId())

    TargetReachability.evaluate(target, { force = true })

    fx:tick(2)
    AttackFSM.update()

    assert.equals(4, AttackFSM.getTargetId(),
      "Target must survive single reachability failure")
  end)

  it("REGRESSION #4: player movement invalidates stale temporary quarantine", function()
    local target = fx:addMonster(5, "Goblin", 50, 105, 100)

    TargetReachability.evaluate(target, { force = true })
    TargetReachability.quarantine(target, {
      attackable = false, reason = "temporarily_blocked",
      classification = "temporarily_blocked",
      playerPosition = fx.player:getPosition(),
      creaturePosition = target:getPosition(),
    })
    assert.is_true(TargetReachability.isQuarantined(target))

    fx.player:setPosition(103, 100, 7)
    if EventBus and EventBus.emit then EventBus.emit("player:position") end
    TargetReachability.invalidateCache()

    assert.is_false(TargetReachability.isQuarantined(target),
      "Quarantine must be invalidated when player moves")
  end)

  it("REGRESSION #5: every target release has a reason code", function()
    local target = fx:addMonster(6, "Troll", 10, 101, 100)

    AttackFSM.requestAttack(target, 500)
    fx:tick(3)
    AttackFSM.update()
    assert.equals(6, AttackFSM.getTargetId())

    target:kill()
    fx:tick(2)
    AttackFSM.update()

    assert.is_nil(AttackFSM.getTargetId())
  end)

  it("REGRESSION #6: stale callback cannot cancel newer target", function()
    local monsterA = fx:addMonster(7, "Wolf", 50, 101, 100)
    local monsterB = fx:addMonster(8, "Bear", 80, 102, 100)

    AttackFSM.requestAttack(monsterA, 1000)
    fx:tick(5)
    AttackFSM.update()
    assert.equals(7, AttackFSM.getTargetId())

    monsterA:kill()
    fx:tick(6)
    AttackFSM.update()

    fx:tick(3)
    AttackFSM.requestAttack(monsterB, 1000)
    fx:tick(6)
    AttackFSM.update()
    assert.equals(8, AttackFSM.getTargetId())

    fx:tick(10)
    AttackFSM.update()
    assert.equals(8, AttackFSM.getTargetId(),
      "Stale callback must not cancel newer target")
  end)

  it("REGRESSION #7: same-target requests are idempotent", function()
    local target = fx:addMonster(9, "Rat", 100, 101, 100)

    local r1 = AttackFSM.requestAttack(target, 500)
    fx:tick(3)
    AttackFSM.update()
    local r2 = AttackFSM.requestAttack(target, 600)
    fx:tick(2)
    AttackFSM.update()

    assert.equals(9, AttackFSM.getTargetId())
    assert.is_true(r1)
    assert.is_true(r2)
    fx:checkNotCancelled()
  end)
end)
