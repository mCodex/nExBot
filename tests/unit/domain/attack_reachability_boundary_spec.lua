local function makeCreature(id)
  local c = { id = id }
  function c:getId() return self.id end
  function c:getName() return "Target" end
  function c:getHealthPercent() return 100 end
  function c:isDead() return false end
  return c
end

describe("AttackFSM reachability boundary", function()
  local attacks
  local cancels
  local allowed
  local attackingCreature

  before_each(function()
    attacks = 0
    cancels = 0
    allowed = false
    attackingCreature = nil
    _G.now = 10000
    _G.nExBot = {
      Shared = {
        nowMs = function() return _G.now end,
        getClient = function() return _G.g_game end,
      },
    }
    _G.SafeCreature = {
      getId = function(c) return c:getId() end,
      getName = function(c) return c:getName() end,
      getHealthPercent = function(c) return c:getHealthPercent() end,
      isDead = function(c) return c:isDead() end,
      getPosition = function() return { x = 100, y = 100, z = 7 } end,
    }
    _G.CombatConstants = {
      TICK_INTERVAL = 100, COMMAND_COOLDOWN = 0, CONFIRM_TIMEOUT = 1,
      GRACE_PERIOD = 1, STOP_DEBOUNCE = 0, REAFFIRM_RETRY_MAX = 2,
      ENGAGE_BACKOFF_BASE = 1, ENGAGE_BACKOFF_GROWTH = 1,
      SWITCH_COOLDOWN = 0, CONFIG_SWITCH_COOLDOWN = 0,
      CRITICAL_HP = 25, PATH_SKIP_DURATION = 1000,
    }
    _G.g_game = {
      getLocalPlayer = function() return {} end,
      getAttackingCreature = function() return attackingCreature end,
      attack = function() attacks = attacks + 1 end,
      cancelAttackAndFollow = function() cancels = cancels + 1; attackingCreature = nil end,
    }
    _G.ReachabilityService = {
      evaluate = function()
        return { attackable = allowed, reason = allowed and "reachable" or "no_attack_position", state = allowed and "ATTACKABLE_NOW" or "CONFIRMED_HARD_UNREACHABLE" }
      end,
    }
    _G.ReachabilityState = {
      isHardRelease = function(state) return state == "CONFIRMED_HARD_UNREACHABLE" end,
      isTemporary = function(state) return false end,
    }
    _G.TargetReachability = {
      evaluate = function()
        return { attackable = allowed, reason = allowed and "reachable" or "no_attack_position", classification = allowed and "confirmed" or "hard_unreachable" }
      end,
      quarantine = function() end,
      invalidate = function() end,
      isQuarantined = function() return not allowed end,
    }
    _G.TargetBot = { isOn = function() return true end, Creature = { getConfigs = function() return {} end } }
    _G.MonsterAI = nil
    _G.PriorityEngine = nil
    _G.EventBus = nil
    _G.BotCore = { Creatures = { getNearby = function() return {} end } }
    _G.AttackFSM = nil
    _G.AttackFSM = dofile("targetbot/application/attack_fsm.lua")
    AttackFSM.reset()
  end)

  it("blocks initial and forced attacks at the final boundary", function()
    local target = makeCreature(1)
    assert.is_false(AttackFSM.requestAttack(target, 100))
    assert.is_false(AttackFSM.forceAttack(target))
    assert.equals(0, attacks)
  end)

  it("issues an attack after authoritative validation succeeds", function()
    allowed = true
    assert.is_true(AttackFSM.requestAttack(makeCreature(2), 100))
    assert.equals(1, attacks)
  end)

  it("releases a target that becomes unreachable once locked", function()
    allowed = true
    local target = makeCreature(3)
    assert.is_true(AttackFSM.requestAttack(target, 100))
    attackingCreature = target
    _G.now = _G.now + 100
    AttackFSM.update()
    assert.equals("ATTACKING", AttackFSM.getState())
    _G.now = _G.now + 100
    AttackFSM.update()
    assert.equals("LOCKED", AttackFSM.getState())

    allowed = false
    _G.now = _G.now + 100
    AttackFSM.update()
    assert.equals("RELEASING", AttackFSM.getState())
    _G.now = _G.now + 100
    AttackFSM.update()

    assert.equals("IDLE", AttackFSM.getState())
    assert.is_nil(AttackFSM.getTargetId())
    assert.equals(1, attacks)
    assert.equals(1, cancels)
  end)
end)
