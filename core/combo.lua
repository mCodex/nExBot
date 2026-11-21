local zChanging = nExBot.zChanging or function() return false end
local SafeCall = SafeCall or require("core.safe_call")
local panelName = "combobot"

if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    onSayEnabled = false,
    onShootEnabled = false,
    onCastEnabled = false,
    followLeaderEnabled = false,
    attackLeaderTargetEnabled = false,
    attackSpellEnabled = false,
    attackItemEnabled = false,
    sayLeader = "",
    shootLeader = "",
    castLeader = "",
    sayPhrase = "",
    spell = "",
    item = 3155,
    attack = "",
    follow = "",
    commandsEnabled = true,
  }
end

local config = storage[panelName]
ComboBot = {
  config = config,
  isOn = function() return config.enabled == true end,
  setOn = function() config.enabled = true end,
  setOff = function() config.enabled = false end,
  toggle = function() config.enabled = not config.enabled return config.enabled end,
  getSetting = function(key) return config[key] end,
  setSetting = function(key, value) config[key] = value end
}

local function canUseAttackItem()
  return config.attackItemEnabled and config.item and config.item > 100 and findItem and findItem(config.item)
end

local leaderTarget = nil
local startCombo = false

ComboBot.show = function() end

onTalk(function(name, level, mode, text, channelId, pos)
  if not config.enabled then return end

  if name:lower() == config.sayLeader:lower() and config.sayPhrase and string.find(text, config.sayPhrase) and config.onSayEnabled then
    startCombo = true
  end
  if config.castLeader and name:lower() == config.castLeader:lower() and isAttSpell and isAttSpell(text) and config.onCastEnabled then
    startCombo = true
  end

  if config.commandsEnabled then
    local isLeader = (config.shootLeader and name:lower() == config.shootLeader:lower())
        or (config.sayLeader and name:lower() == config.sayLeader:lower())
        or (config.castLeader and name:lower() == config.castLeader:lower())
    if isLeader then
      local textLower = text:lower()
      if textLower == "ue" then
        say(config.spell)
      elseif textLower == "sd" then
        local params = string.split(text, ",")
        if #params == 2 then
          local target = params[2]:trim()
          local creature = SafeCall.getCreatureByName(target)
          if creature and useWith then
            useWith(config.item, creature)
          end
        end
      elseif textLower == "att" then
        local attParams = string.split(text, ",")
        if #attParams == 2 then
          local atTarget = attParams[2]:trim()
          local creature = SafeCall.getCreatureByName(atTarget)
          if creature and config.attack == "COMMAND TARGET" and TargetBot and TargetBot.requestAttack then
            TargetBot.requestAttack(creature, "ComboCommand")
          end
        end
      end
    end
  end

  if isAttSpell and isAttSpell(text) and config.enabled and isLeader and config.onCastEnabled then
    EventBus.emit("combo:trigger")
  end
end)

onMissle(function(missle)
  if zChanging() then return end
  if not config.enabled or not config.onShootEnabled then return end
  if not config.shootLeader or config.shootLeader:len() == 0 then return end

  local src = missle:getSource()
  if src.z ~= posz() then return end

  local from = g_map.getTile(src)
  local to = g_map.getTile(missle:getDestination())
  if not from or not to then return end

  local fromCreatures = from:getCreatures()
  local toCreatures = to:getCreatures()
  if #fromCreatures == 0 or #toCreatures == 0 then return end

  -- Find the leader among creatures on the source tile
  local leader = nil
  for _, c in ipairs(fromCreatures) do
    if c:getName():lower() == config.shootLeader:lower() then
      leader = c
      break
    end
  end
  if not leader then return end

  -- Pick the target: prefer the first non-leader, non-local creature on destination tile
  local player = g_game.getLocalPlayer()
  local t1 = nil
  for _, c in ipairs(toCreatures) do
    if c ~= leader and (not player or c ~= player) then
      t1 = c
      break
    end
  end
  if not t1 then return end

  leaderTarget = t1
  if canUseAttackItem() and useWith then
    useWith(config.item, t1)
  end
  if config.attackSpellEnabled and config.spell and config.spell:len() > 1 then
    say(config.spell)
  end
  if config.attack == "LEADER TARGET" and TargetBot and TargetBot.requestAttack then
    TargetBot.requestAttack(leaderTarget, "ComboLeader")
  end
end)

local function leaderTargetHandler()
  if not config.enabled then return end
  if not leaderTarget or config.attack ~= "LEADER TARGET" then return end

  -- Clear stale target (creature left screen or died)
  if not leaderTarget then return end
  if not leaderTarget.getPosition then leaderTarget = nil; return end
  local ltPos = leaderTarget:getPosition()
  if not ltPos then leaderTarget = nil; return end

  local target = SafeCall.getTarget()
  if not target or target:getName() ~= leaderTarget:getName() then
    if TargetBot and TargetBot.requestAttack then
      TargetBot.requestAttack(leaderTarget, "ComboLeader")
    end
  end
end

local toFollow = nil
local toFollowPos = {}
local lastFollowPos = nil
local lastFollowWalk = 0
local FOLLOW_WALK_COOLDOWN = 100

local function followLeaderHandler()
  if not config.enabled or not config.followLeaderEnabled then
    toFollow = nil
    return
  end
  toFollow = nil  -- Clear before evaluating rules

  if config.follow == "LEADER TARGET" and leaderTarget and leaderTarget:isPlayer() then
    toFollow = leaderTarget:getName()
  elseif config.follow == "LEADER" then
    if config.onSayEnabled and config.sayLeader and config.sayLeader:len() ~= 0 then
      toFollow = config.sayLeader
    elseif config.onCastEnabled and config.castLeader and config.castLeader:len() ~= 0 then
      toFollow = config.castLeader
    elseif config.onShootEnabled and config.shootLeader and config.shootLeader:len() ~= 0 then
      toFollow = config.shootLeader
    end
  end

  if not toFollow then return end

  local target = SafeCall.getCreatureByName(toFollow)
  if target then
    local tpos = target:getPosition()
    toFollowPos[tpos.z] = tpos
  end

  if player:isWalking() then return end
  local p = toFollowPos[posz()]
  if not p then return end

  local posKey = p.x .. "," .. p.y .. "," .. p.z
  if posKey == lastFollowPos then return end
  if (now - lastFollowWalk) < FOLLOW_WALK_COOLDOWN then return end

  if CaveBot.walkTo(p, 20, {ignoreNonPathable=true, precision=1, ignoreStairs=false}) then
    lastFollowWalk = now
    lastFollowPos = posKey
  end
end

onCreaturePositionChange(function(creature, oldPos, newPos)
  if zChanging() then return end
  if toFollow and creature:getName() == toFollow and newPos then
    toFollowPos[newPos.z] = newPos
    lastFollowPos = nil
  end
end)

local function comboTriggerHandler()
  if config.enabled and startCombo then
    if canUseAttackItem() and useWith then
      local target = SafeCall.getTarget()
      if target then useWith(config.item, target) end
    end
    if config.attackSpellEnabled and config.spell and config.spell:len() > 1 then
      say(config.spell)
    end
    startCombo = false
  end
end

EventBus.on("combo:trigger", function()
  startCombo = true
end)

if UnifiedTick and UnifiedTick.register then
  UnifiedTick.register("combo_leader_target", {
    interval = 100,
    priority = UnifiedTick.Priority and UnifiedTick.Priority.NORMAL or 50,
    handler = leaderTargetHandler,
    group = "combo"
  })

  UnifiedTick.register("combo_follow_leader", {
    interval = 100,
    priority = UnifiedTick.Priority and UnifiedTick.Priority.NORMAL or 50,
    handler = followLeaderHandler,
    group = "combo"
  })

  UnifiedTick.register("combo_trigger", {
    interval = 100,
    priority = UnifiedTick.Priority and UnifiedTick.Priority.HIGH or 75,
    handler = comboTriggerHandler,
    group = "combo"
  })
else
  macro(100, leaderTargetHandler)
  macro(100, followLeaderHandler)
  macro(100, comboTriggerHandler)
end
