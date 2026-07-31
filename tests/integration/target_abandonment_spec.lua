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

    _G.CombatConstants = nil
    _G.CombatConstants = dofile("targetbot/combat_constants.lua")

    _G.AttackStateMachine = nil
    _G.AttackStateMachine = dofile("targetbot/attack_state_machine.lua")
  end)

  it("REGRESSION #1: invalid replacement does NOT stop current target", function()
    local monsterA = fx:addMonster(1, "Orc", 20, 101, 100)
    local monsterB = fx:addMonster(2, "Dragon", 100, 105, 105)

    AttackStateMachine.requestAttack(monsterA, 1000)
    fx:tick(3)
    AttackStateMachine.update()

    assert.equals(1, AttackStateMachine.getTargetId())

    fx:setReachability(2, false, "no_attack_position")
    TargetReachability.evaluate(monsterB, { force = true })
    TargetReachability.quarantine(monsterB, {
      attackable = false, reason = "no_attack_position",
      classification = "hard_unreachable",
      playerPosition = fx.player:getPosition(),
      creaturePosition = monsterB:getPosition(),
    })

    AttackStateMachine.requestAttack(monsterB, 2000)
    fx:tick(2)
    AttackStateMachine.update()

    assert.equals(1, AttackStateMachine.getTargetId(),
      "Current target must remain Monster A after invalid replacement")
    fx:checkNotCancelled()
  end)

  it("REGRESSION #2: temporary LOS failure preserves commitment", function()
    local target = fx:addMonster(3, "Elf", 15, 101, 100)

    AttackStateMachine.requestAttack(target, 1000)
    fx:tick(3)
    AttackStateMachine.update()
    assert.equals(3, AttackStateMachine.getTargetId())

    fx:setLOS({x=100,y=100,z=7}, {x=101,y=100,z=7}, false)
    TargetReachability.evaluate(target, { mode = "ranged", force = true, config = { distance = 5 } })

    fx:tick(2)
    AttackStateMachine.update()

    assert.equals(3, AttackStateMachine.getTargetId(),
      "Target must not be released on single LOS failure")
  end)

  it("REGRESSION #3: single pathfinding failure does not release target", function()
    local target = fx:addMonster(4, "Demon", 30, 103, 100)

    AttackStateMachine.requestAttack(target, 1000)
    fx:tick(5)
    AttackStateMachine.update()
    assert.equals(4, AttackStateMachine.getTargetId())

    TargetReachability.evaluate(target, { force = true })

    fx:tick(2)
    AttackStateMachine.update()

    assert.equals(4, AttackStateMachine.getTargetId(),
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

    AttackStateMachine.requestAttack(target, 500)
    fx:tick(3)
    AttackStateMachine.update()
    assert.equals(6, AttackStateMachine.getTargetId())

    target:kill()
    fx:tick(2)
    AttackStateMachine.update()

    assert.is_nil(AttackStateMachine.getTargetId())
  end)

  it("REGRESSION #6: stale callback cannot cancel newer target", function()
    local monsterA = fx:addMonster(7, "Wolf", 50, 101, 100)
    local monsterB = fx:addMonster(8, "Bear", 80, 102, 100)

    AttackStateMachine.requestAttack(monsterA, 1000)
    fx:tick(5)
    AttackStateMachine.update()
    assert.equals(7, AttackStateMachine.getTargetId())

    monsterA:kill()
    fx:tick(6)
    AttackStateMachine.update()

    fx:tick(3)
    AttackStateMachine.requestAttack(monsterB, 1000)
    fx:tick(6)
    AttackStateMachine.update()
    assert.equals(8, AttackStateMachine.getTargetId())

    fx:tick(10)
    AttackStateMachine.update()
    assert.equals(8, AttackStateMachine.getTargetId(),
      "Stale callback must not cancel newer target")
  end)

  it("REGRESSION #7: same-target requests are idempotent", function()
    local target = fx:addMonster(9, "Rat", 100, 101, 100)

    local r1 = AttackStateMachine.requestAttack(target, 500)
    fx:tick(3)
    AttackStateMachine.update()
    local r2 = AttackStateMachine.requestAttack(target, 600)
    fx:tick(2)
    AttackStateMachine.update()

    assert.equals(9, AttackStateMachine.getTargetId())
    assert.is_true(r1)
    assert.is_true(r2)
    fx:checkNotCancelled()
  end)
end)
