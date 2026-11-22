describe("TargetBot selection from live creatures", function()
  local env, visible, handlers, pathCalls, rankings, current
  local function noop() end
  local function creature(id, configured)
    return {
      id = id, configured = configured,
      getId = function(self) return self.id end,
      getPosition = function() return {x = 101, y = 100, z = 7} end,
      isMonster = function() return true end, isPlayer = function() return false end,
      isNpc = function() return false end, isDead = function() return false end,
      canShoot = function() return true end, getHealthPercent = function() return 100 end,
      getName = function() return configured and "Hydra" or "Rat" end,
    }
  end

  before_each(function()
    pathCalls, visible, rankings, handlers, current = 0, {}, {}, {}, nil
    local label = {setText = noop, setTooltip = noop}
    local row = {left = label, right = label}
    local panel = {listPanel = {list = {}}, status = row, target = row, config = row,
      danger = row, configButton = label, editor = {buttons = {add = label, edit = label, remove = label}}}
    local player = {getPosition = function() return {x = 100, y = 100, z = 7} end}
    local client = {getLocalPlayer = function() return player end}
    local function countPath() pathCalls = pathCalls + 1 end
    env = setmetatable({
      player = player, now = 10000, BotConfigName = "test", storage = {rustTargetRanking = true},
      nExBot = {target_pathfinding = {isTargetableCreature = function() return true end},
        Shared = {getClient = function() return client end, getClientVersion = function() return 1000 end},
        SharedHelpers = {ensurePathUtils = noop, makeDebounce = function() return noop end}},
      UI = {createWidget = function() return panel end}, Config = {setup = function() return {isOn = true} end},
      macro = function() return {} end, schedule = noop, SafeCall = {}, SafeCreature = {
        getPosition = function(c) return c:getPosition() end, getId = function(c) return c:getId() end},
      ClientService = {getAttackingCreature = function() return current end},
      EventBus = {on = function(event, callback)
        handlers[event] = handlers[event] or {}
        table.insert(handlers[event], callback)
      end},
      EventTargeting = {getLiveMonsterCount = function() return #visible, visible end},
      TargetBot = {isOff = function() return false end, Looting = {setup = noop}, Creature = {
        getConfigs = function(c) return c.configured and {{}} or {} end,
        calculateParams = function(c) return {creature = c, config = {}, priority = 1} end}},
      TargetReachability = {evaluate = function() countPath(); return {attackable = true, path = {1}} end},
      findPath = countPath,
      nExBotRuntime = {decide = function(op, observation)
        assert.equals("target_rank", op)
        table.insert(rankings, observation)
        return observation.candidates[#observation.candidates].id
      end},
    }, {__index = _G})
    assert(loadfile("targetbot/target_coordinator.lua", "t", env))()
    assert(loadfile("targetbot/target_events.lua", "t", env))()
  end)

  it("keeps every arrival visible and evaluates paths only for matching candidates", function()
    for id = 1, 25 do
      local c = creature(id, id == 25)
      visible[id] = c
      for _, notify in ipairs(handlers["monster:appear"]) do notify(c) end
    end
    assert.equals(25, env.TargetBot.getTargetableMonsterCount())
    local best, count = env.TargetBot.__internals.recalculateBestTarget()
    assert.equals(1, count)
    assert.equals(25, best.creature.id)
    assert.equals(1, pathCalls)
  end)

  it("ranks the current sample synchronously and respects a scenario switch veto", function()
    visible[1], visible[2] = creature(1, true), creature(2, true)
    local recalc = env.TargetBot.__internals.recalculateBestTarget
    assert.equals(2, recalc().creature.id)
    assert.equals(2, #rankings[1].candidates)
    assert.equals(100, rankings[1].player.x)
    current = visible[1]
    env.MonsterAI = {Scenario = {shouldAllowTargetSwitch = function() return false end}}
    assert.equals(1, recalc().creature.id)
    assert.equals(1, rankings[2].current)
  end)

  it("preserves the IPC fallback when native ranking is unavailable and honors native no-target", function()
    visible[1], visible[2] = creature(1, true), creature(2, true)
    local recalc = env.TargetBot.__internals.recalculateBestTarget
    local ipcCalls = 0
    env.RustBridge = {
      useTargetRanking = function() return true end,
      rankedTarget = function() ipcCalls = ipcCalls + 1; return 2 end,
    }
    env.nExBotRuntime.decide = function() return nil end
    assert.equals(2, recalc().creature.id)
    env.nExBotRuntime.decide = function() return 0 end
    local best = recalc()
    assert.is_nil(best)
    assert.equals(1, ipcCalls)
  end)

  it("uses local selection for invalid responses, disabled ranking and oversized samples", function()
    visible[1], visible[2] = creature(1, true), creature(2, true)
    local recalc = env.TargetBot.__internals.recalculateBestTarget
    env.nExBotRuntime.decide = function() return 999 end
    assert.equals(1, recalc().creature.id)
    env.nExBotRuntime.decide = function() error("unexpected native call") end
    env.storage.rustTargetRanking = false
    assert.equals(1, recalc().creature.id)
    env.storage.rustTargetRanking = true
    for i = 3, 25 do visible[i] = creature(i, true) end
    assert.equals(1, recalc().creature.id)
  end)
end)
