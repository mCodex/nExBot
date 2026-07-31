local clock = 1000

local function pos(x, y, z) return { x = x, y = y, z = z or 7 } end

local player = { id = 1, position = pos(100, 100, 7), hp = 100, dead = false, name = "Player" }
function player:getId() return self.id end
function player:getPosition() return self.position end
function player:getHealthPercent() return self.hp end
function player:isDead() return self.dead end
function player:getName() return self.name end

local function makeCreature(id, name, hp, dead, position)
  local c = { id = id, name = name or "Monster", hp = hp or 100, dead = dead or false, position = position or pos(102, 100, 7) }
  function c:getId() return self.id end
  function c:getPosition() return self.position end
  function c:getHealthPercent() return self.hp end
  function c:isDead() return self.dead end
  function c:getName() return self.name end
  return c
end

local attackCalls = {}
local cancelCalls = {}
local attackingCreature = nil

local reachabilityResult = { state = "ATTACKABLE_NOW", attackable = true }
local commitmentBlocks = false

_G.nExBot = {
  Shared = {
    nowMs = function() return clock end,
    getClient = function() return nil end,
  }
}

_G.g_game = {
  attack = function(creature)
    table.insert(attackCalls, creature)
    attackingCreature = creature
  end,
  getAttackingCreature = function()
    return attackingCreature
  end,
  cancelAttackAndFollow = function()
    table.insert(cancelCalls, true)
    attackingCreature = nil
  end,
  getLocalPlayer = function() return player end,
}

_G.ReachabilityState = dofile("targetbot/domain/reachability_states.lua")
_G.ReleaseReason = dofile("targetbot/domain/release_reasons.lua")

_G.ReachabilityService = {
  evaluate = function(creature, context)
    local result = {}
    for k, v in pairs(reachabilityResult) do result[k] = v end
    return result
  end,
}

_G.TargetCommitmentManager = {
  blocksRelease = function(targetId, reason)
    return commitmentBlocks
  end,
  isActive = function() return false end,
  getActive = function() return nil end,
}

_G.TargetBot = {
  isOn = function() return true end,
}

_G.SafeCreature = {}

_G.CombatConstants = {
  TICK_INTERVAL = 100,
  COMMAND_COOLDOWN = 0,
  CONFIRM_TIMEOUT = 1200,
  GRACE_PERIOD = 1500,
  STOP_DEBOUNCE = 0,
  REAFFIRM_RETRY_MAX = 5,
  ENGAGE_BACKOFF_BASE = 1500,
  ENGAGE_BACKOFF_GROWTH = 1.5,
  SWITCH_COOLDOWN = 2500,
  CONFIG_SWITCH_COOLDOWN = 400,
  CRITICAL_HP = 25,
  PATH_SKIP_DURATION = 10000,
}

_G.EventBus = nil

describe("AttackFSM", function()
  local fsm

  before_each(function()
    clock = 1000
    attackCalls = {}
    cancelCalls = {}
    attackingCreature = nil
    reachabilityResult = { state = "ATTACKABLE_NOW", attackable = true }
    commitmentBlocks = false
    fsm = dofile("targetbot/application/attack_fsm.lua")
    fsm.reset()
  end)

  it("transitions IDLE -> ACQUIRING on requestAttack", function()
    local c = makeCreature(100, "Orc")
    assert.equals("IDLE", fsm.getState())
    local ok = fsm.requestAttack(c, 500)
    assert.is_true(ok)
    assert.equals("ACQUIRING", fsm.getState())
    assert.equals(100, fsm.getTargetId())
    assert.equals(1, fsm.getGeneration())
  end)

  it("transitions ACQUIRING -> ATTACKING -> LOCKED on successful attack + confirmation", function()
    local c = makeCreature(200, "Dragon")
    fsm.requestAttack(c, 500)
    assert.equals("ACQUIRING", fsm.getState())

    clock = clock + 200
    fsm.update()
    assert.equals("ATTACKING", fsm.getState())
    assert.equals(1, #attackCalls)

    attackingCreature = c
    clock = clock + 200
    fsm.update()
    assert.equals("LOCKED", fsm.getState())
  end)

  it("same-target requestAttack is idempotent", function()
    local c = makeCreature(300, "Elf")
    fsm.requestAttack(c, 500)
    local genBefore = fsm.getGeneration()

    local ok = fsm.requestAttack(c, 600)
    assert.is_true(ok)
    assert.equals("ACQUIRING", fsm.getState())
    assert.equals(genBefore, fsm.getGeneration())
    assert.equals(1, fsm.getStats().stats.switches)
  end)

  it("failed replacement: preserves current target, rejects candidate, no cancelAttack", function()
    local c1 = makeCreature(400, "Orc")
    fsm.requestAttack(c1, 500)
    clock = clock + 200
    fsm.update()
    attackingCreature = c1
    clock = clock + 200
    fsm.update()
    assert.equals("LOCKED", fsm.getState())
    assert.equals(400, fsm.getTargetId())

    local cancelBefore = #cancelCalls
    reachabilityResult = { state = "DIFFERENT_FLOOR", attackable = false }
    local c2 = makeCreature(500, "Demon")
    local ok = fsm.requestAttack(c2, 900)
    assert.is_false(ok)
    assert.equals("LOCKED", fsm.getState())
    assert.equals(400, fsm.getTargetId())
    assert.equals(cancelBefore, #cancelCalls)
  end)

  it("temporary reachability failure goes to TEMPORARILY_BLOCKED not IDLE", function()
    local c = makeCreature(600, "Bear")
    fsm.requestAttack(c, 500)
    clock = clock + 200
    fsm.update()
    attackingCreature = c
    clock = clock + 200
    fsm.update()
    assert.equals("LOCKED", fsm.getState())

    reachabilityResult = { state = "TEMPORARILY_BLOCKED", attackable = false }
    attackingCreature = nil
    clock = clock + 200
    fsm.update()
    assert.equals("TEMPORARILY_BLOCKED", fsm.getState())
    assert.equals(600, fsm.getTargetId())
  end)

  it("hard release DIFFERENT_FLOOR goes RELEASING -> IDLE", function()
    local c = makeCreature(700, "Ghost")
    fsm.requestAttack(c, 500)
    clock = clock + 200
    fsm.update()
    attackingCreature = c
    clock = clock + 200
    fsm.update()
    assert.equals("LOCKED", fsm.getState())

    reachabilityResult = { state = "DIFFERENT_FLOOR", attackable = false }
    attackingCreature = nil
    clock = clock + 200
    fsm.update()
    assert.equals("RELEASING", fsm.getState())

    clock = clock + 200
    fsm.update()
    assert.equals("IDLE", fsm.getState())
    assert.is_nil(fsm.getTargetId())
    assert.is_true(#cancelCalls > 0)
  end)

  it("generation token: stale callback is discarded", function()
    local c1 = makeCreature(800, "Wolf")
    fsm.requestAttack(c1, 500)
    local gen1 = fsm.getGeneration()

    clock = clock + 200
    fsm.update()
    attackingCreature = c1
    clock = clock + 200
    fsm.update()
    assert.equals("LOCKED", fsm.getState())
    local gen2 = fsm.getGeneration()
    assert.is_true(gen2 > gen1)

    fsm.stop()
    local gen3 = fsm.getGeneration()
    assert.is_true(gen3 > gen2)

    clock = clock + 200
    fsm.update()
    assert.equals("IDLE", fsm.getState())
    assert.equals(gen3 + 1, fsm.getGeneration())
  end)

  it("commitment blocks release to IDLE, goes TEMPORARILY_BLOCKED instead", function()
    local c = makeCreature(900, "Troll")
    fsm.requestAttack(c, 500)
    clock = clock + 200
    fsm.update()
    attackingCreature = c
    clock = clock + 200
    fsm.update()
    assert.equals("LOCKED", fsm.getState())

    commitmentBlocks = true
    reachabilityResult = { state = "TEMPORARILY_BLOCKED", attackable = false }
    attackingCreature = nil
    clock = clock + 200
    fsm.update()
    assert.equals("TEMPORARILY_BLOCKED", fsm.getState())
    assert.equals(900, fsm.getTargetId())
  end)

  it("target death transitions to IDLE with kill counted", function()
    local c = makeCreature(1000, "Skeleton")
    fsm.requestAttack(c, 500)
    clock = clock + 200
    fsm.update()
    attackingCreature = c
    clock = clock + 200
    fsm.update()
    assert.equals("LOCKED", fsm.getState())

    c.dead = true
    clock = clock + 200
    fsm.update()
    assert.equals("IDLE", fsm.getState())
    assert.equals(1, fsm.getStats().stats.kills)
  end)

  it("stop() goes RELEASING -> IDLE with cancelAttack called", function()
    local c = makeCreature(1100, "Goblin")
    fsm.requestAttack(c, 500)
    clock = clock + 200
    fsm.update()
    attackingCreature = c
    clock = clock + 200
    fsm.update()
    assert.equals("LOCKED", fsm.getState())

    fsm.stop()
    assert.equals("RELEASING", fsm.getState())

    clock = clock + 200
    fsm.update()
    assert.equals("IDLE", fsm.getState())
    assert.is_nil(fsm.getTargetId())
    assert.is_true(#cancelCalls > 0)
  end)
end)
