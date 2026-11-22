describe("native combat decisions", function()
  local function loadIn(path, env)
    return assert(loadfile(path, "t", setmetatable(env, {__index = _G})))()
  end

  it("uses the Rust self-heal decision without also applying a local rule", function()
    local selected = 0
    local heal = loadIn("core/heal_engine.lua", {
      nExBot = {Shared = {nowMs = function() return 1000 end}},
      nExBotRuntime = {decide = function(operation, input)
        assert.equals("self_heal", operation)
        assert.equals(49.999, input.hp)
        assert.is_true(input.rules[1].ready)
        return selected
      end},
    })
    heal.configure({selfSpells = true})
    heal.setCustomSpells({{name = "exura", hp = 50, mana = 10}})

    local snapshot = {hp = 49.999, mp = 50, currentMana = 10, inPz = false}
    assert.is_nil(heal.planSelf(snapshot))
    selected = 1
    assert.equals("exura", heal.planSelf(snapshot).name)
  end)

  it("reacts synchronously to allied damage and dispatches one named spell", function()
    local callbacks, messages = {}, {}
    local ally = {
      getName = function() return "Friend" end,
      getPosition = function() return {z = 7} end,
      canShoot = function() return true end,
      isPlayer = function() return true end,
      isLocalPlayer = function() return false end,
    }
    local env = {
      BotCore = {Stats = {
        getHpPercent = function() return 100 end,
        getMpPercent = function() return 100 end,
        getMp = function() return 500 end,
      }},
      SafeCreature = {getName = ally.getName, isPlayer = ally.isPlayer},
      distanceFromPlayer = function() return 1 end,
      say = function(text) messages[#messages + 1] = text end,
      EventBus = {
        on = function(event, callback)
          callbacks[event] = callbacks[event] or {}
          callbacks[event][#callbacks[event] + 1] = callback
          return function() end
        end,
        emit = function() end,
      },
      nExBotRuntime = {decide = function(operation, input)
        assert.equals("ally_heal", operation)
        assert.equals(39, input.hp)
        assert.equals("spell", input.rules[1].action)
        return 1
      end},
    }

    local healer = loadIn("core/bot_core/friend_healer.lua", env)
    healer.init({enabled = true, useSio = true, customPlayers = {Friend = 80}})
    healer.setEnabled(true)
    for _, callback in ipairs(callbacks["creature:health"]) do callback(ally, 39, 41) end
    for _, callback in ipairs(callbacks["friend:health"]) do callback(ally, 39, 41) end

    assert.same({'exura sio "Friend"'}, messages)
  end)
end)
