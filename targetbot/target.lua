local targetbotMacro = nil
local config = nil
lastAction = 0
local cavebotAllowance = 0
local lureEnabled = true
local dangerValue = 0
local looterStatus = ""

local getClient = nExBot.Shared.getClient
local MONSTER_DETECTION_RANGE = 14
local MAX_TARGET_DIST = 12

local function cId(c)
  if not c then return nil end
  local ok, v = pcall(function() return c:getId() end)
  return ok and v or nil
end

local function getNearbyCreatures(playerPos)
  if not playerPos then return {} end

  -- g_map.getSpectatorsInRange (original working call, with pcall safety)
  if g_map and g_map.getSpectatorsInRange then
    local ok, result = pcall(g_map.getSpectatorsInRange, playerPos, false, MONSTER_DETECTION_RANGE, MONSTER_DETECTION_RANGE)
    if ok and type(result) == "table" and #result > 0 then return result end
  end

  -- Fallback: g_map.getSpectators
  if g_map and g_map.getSpectators then
    local ok, result = pcall(g_map.getSpectators, playerPos, false)
    if ok and type(result) == "table" and #result > 0 then return result end
  end

  return {}
end

-- Robust creature validation: safe across all OTClient versions
local function isTargetable(creature)
  if not creature then return false end
  local ok, isDead = pcall(function() return creature:isDead() end)
  if ok and isDead then return false end
  local ok2, removed = pcall(function() return creature:isRemoved() end)
  if ok2 and removed then return false end
  local ok3, isMonster = pcall(function() return creature:isMonster() end)
  if not ok3 or not isMonster then return false end
  local ok4, hp = pcall(function() return creature:getHealthPercent() end)
  if ok4 and hp and hp <= 0 then return false end
  return true
end

-- UI widget setup (must run before macro references ui)
local configWidget = UI.Config()
local ui = UI.createWidget("TargetBotPanel")
ui.list = ui.listPanel.list
TargetBot.targetList = ui.list
TargetBot.Looting.setup()

ui.status.left:setText("Status:")
ui.status.right:setText("Off")
ui.target.left:setText("Target:")
ui.target.right:setText("-")
ui.config.left:setText("Config:")
ui.config.right:setText("-")
ui.danger.left:setText("Danger:")
ui.danger.right:setText("0")

-- Helpers
local function setWidgetText(widget, text)
  if not widget then return end
  pcall(function()
    local cur = widget.getText and widget:getText()
    if cur ~= text then widget:setText(text) end
  end)
end

local function setStatus(text)
  pcall(function() ui.status.right:setText(text) end)
end

-- Main macro (100ms, vBot 4.8 pure)
targetbotMacro = macro(50, function()
  if not config or not config.isOn or not config.isOn() then return end
  if TargetBot and TargetBot.explicitlyDisabled then return end

  if AttackStateMachine and AttackStateMachine.update then
    pcall(AttackStateMachine.update)
  end

  local Client = getClient()
  local isOnline = Client and Client.isOnline and Client.isOnline() or g_game and g_game.isOnline and g_game.isOnline()
  if not isOnline then return end

  local playerPos = player and player:getPosition()
  if not playerPos then return end

  -- ACL-backed spectator scan with fallback chain
  local creatures = getNearbyCreatures(playerPos)
  local bestTarget = nil
  local bestPriority = 0
  local targets = 0
  local dangerLevel = 0
  local debugReachable = 0
  local debugUnreachable = 0
  local debugNoConfig = 0
  local useReachability = true  -- Can be toggled by config

  for i = 1, #creatures do
    local c = creatures[i]
    if isTargetable(c) then
      local cpos = pcall(function() return c:getPosition() end) and c:getPosition()
      if cpos and cpos.z == playerPos.z then
        local dist = math.max(math.abs(cpos.x - playerPos.x), math.abs(cpos.y - playerPos.y))
        if dist <= MAX_TARGET_DIST then
          -- Proactive reachability check: skip unreachable creatures
          local reachable = true
          local pathLen = 999
          local Reachability = MonsterAI and MonsterAI.Reachability
          
          if useReachability and Reachability and Reachability.isReachable then
            local ok, rReason, rPath = Reachability.isReachable(c)
            reachable = ok
            if ok and rPath then pathLen = #rPath end
          else
            -- Fallback: simple distance-based reachability (always true if on same floor and in range)
            local ok, path = pcall(findPath, playerPos, cpos, 7, {
              ignoreNonPathable = true, ignoreCost = true, ignoreCreatures = true,
            })
            if not ok or not path or #path == 0 then
              reachable = false
            else
              pathLen = #path
            end
          end

          -- Fallback: if too many creatures marked unreachable, disable reachability check
          if not reachable then
            debugUnreachable = debugUnreachable + 1
            -- If more than 50% of creatures are "unreachable", assume reachability is broken
            local totalChecked = debugReachable + debugUnreachable
            if totalChecked > 5 and debugUnreachable / totalChecked > 0.5 then
              useReachability = false
              reachable = true  -- Override: treat as reachable
              pathLen = dist
              print("[TargetBot] Reachability check disabled - too many false negatives")
            end
          else
            debugReachable = debugReachable + 1
          end

          if reachable then
            local cfg = TargetBot.Creature and TargetBot.Creature.getConfigs and TargetBot.Creature.getConfigs(c)
            if cfg and #cfg > 0 then
              local configPrio = cfg[1].priority or 0
              local hp = 100
              pcall(function() hp = c:getHealthPercent() or 100 end)
              local hpBonus = (hp < 25) and (25 - hp) * 2 or 0
              local distBonus = math.max(0, MAX_TARGET_DIST - dist)
              local pathBonus = (pathLen == 1) and 10 or (pathLen <= 3 and 5 or 0)
              local priority = configPrio * 100 + distBonus + hpBonus + pathBonus

              local danger = cfg[1].danger or 0
              dangerLevel = dangerLevel + danger
              targets = targets + 1

              if priority > bestPriority then
                bestPriority = priority
                bestTarget = c
              end
            else
              debugNoConfig = debugNoConfig + 1
            end
          else
            local cfg2 = TargetBot.Creature and TargetBot.Creature.getConfigs and TargetBot.Creature.getConfigs(c)
            if cfg2 and #cfg2 > 0 then
              dangerLevel = dangerLevel + (cfg2[1].danger or 0)
              targets = targets + 1
            end
          end
        end
      end
    end
  end

  dangerValue = dangerLevel
  setWidgetText(ui.danger.right, tostring(dangerLevel))
  
  -- Debug: print reachability stats
  if (now - (targetbotMacro._lastDebug or 0)) > 2000 then
    targetbotMacro._lastDebug = now
    print(string.format("[TargetBot] Creatures: %d | Reachable: %d | Unreachable: %d | NoConfig: %d | BestTarget: %s", 
      #creatures, debugReachable, debugUnreachable, debugNoConfig, bestTarget and bestTarget:getName() or "none"))
    if MonsterAI and MonsterAI.Reachability and MonsterAI.Reachability.getStats then
      local stats = MonsterAI.Reachability.getStats()
      print(string.format("[Reachability] Checks: %d | CacheHits: %d | Blocked: %d | Reachable: %d", 
        stats.checksPerformed, stats.cacheHits, stats.blocked, stats.reachable))
    end
    if AttackStateMachine and AttackStateMachine.getStats then
      local asmStats = AttackStateMachine.getStats()
      print(string.format("[ASM] State: %s | TargetId: %s | Active: %s", 
        asmStats.state, tostring(asmStats.targetId), tostring(asmStats.state ~= "IDLE")))
    end
  end

  if bestTarget then
    local name = pcall(function() return bestTarget:getName() end) and bestTarget:getName() or "?"
    setWidgetText(ui.target.right, name)
    setWidgetText(ui.config.right, pcall(function() return TargetBot.Creature.getConfigs(bestTarget)[1].name end) and TargetBot.Creature.getConfigs(bestTarget)[1].name or "-")
    setStatus("Killing (" .. targets .. ")")
    lastAction = now

    pcall(function()
      if AttackStateMachine and AttackStateMachine.requestAttack then
        AttackStateMachine.requestAttack(bestTarget, bestPriority)
      end
    end)

    pcall(function() TargetBot.Creature.attack({creature = bestTarget, config = (TargetBot.Creature.getConfigs and TargetBot.Creature.getConfigs(bestTarget) or {})[1] or {}}, targets, false) end)

    if TargetBot.walk then TargetBot.walk() end
    return
  end

  setWidgetText(ui.target.right, "-")
  setWidgetText(ui.config.right, "-")

  -- Looting
  local lootDirty = TargetBot.Looting and TargetBot.Looting.isDirty and TargetBot.Looting.isDirty() or (TargetBot.Looting and #TargetBot.Looting.list > 0)
  if lootDirty then
    local lootResult = TargetBot.Looting.process()
    TargetBot.Looting.clearDirty()
    if lootResult then
      lastAction = now
      looterStatus = "Looting"
      setStatus("Looting")
      if TargetBot.walk then TargetBot.walk() end
      return
    end
  end
  looterStatus = ""

  setStatus("Waiting")
  if TargetBot.walk then TargetBot.walk() end
end)

-- External API
TargetBot.hasTargetableMonsters = function()
  local p = player and player:getPosition()
  if not p then return false end
  local creatures = getNearbyCreatures(p)
  for i = 1, #creatures do
    if isTargetable(creatures[i]) then return true end
  end
  return false
end

TargetBot.getTargetableMonsterCount = function()
  local p = player and player:getPosition()
  if not p then return 0 end
  local creatures = getNearbyCreatures(p)
  local n = 0
  for i = 1, #creatures do
    if isTargetable(creatures[i]) then n = n + 1 end
  end
  return n
end

TargetBot.isActive = function()
  return lastAction + 300 > now
end

TargetBot.isCaveBotActionAllowed = function()
  return cavebotAllowance > now
end

TargetBot.setStatus = setStatus

TargetBot.getStatus = function()
  local ok, v = pcall(function() return ui.status.right:getText() end)
  return ok and v or ""
end

TargetBot.allowCaveBot = function(time)
  local prev = cavebotAllowance
  cavebotAllowance = now + time
  -- Emit event when cavebot state changes
  if prev <= now and EventBus then
    pcall(function() EventBus.emit("targetbot:cavebot_allowed", time) end)
  end
end

TargetBot.Danger = function() return dangerValue end
TargetBot.lootStatus = function() return looterStatus end

TargetBot.requestAttack = function(creature, reason, force)
  if not creature then return false end
  if AttackStateMachine == nil then return false end
  if force then return AttackStateMachine.forceAttack(creature) end
  return AttackStateMachine.requestAttack(creature, 1000)
end

TargetBot.disableLuring = function() lureEnabled = false end
TargetBot.enableLuring = function() lureEnabled = true end
TargetBot.canLure = function() return lureEnabled end
TargetBot.canAttack = function() return true end

TargetBot.isOn = function()
  return config and config.isOn and config.isOn()
end

TargetBot.isOff = function()
  return config and config.isOff and config.isOff()
end

TargetBot.stopAttack = function(clearWalk)
  if clearWalk then TargetBot.clearWalk() end
  if autoAttackTarget then autoAttackTarget(nil) end
end

-- Config setup
config = Config.setup("targetbot_configs", configWidget, "json", function(name, enabled, data)
  if enabled and name and name ~= "" then
    if setCharacterProfile then setCharacterProfile("targetbotProfile", name) end
    if UnifiedStorage then UnifiedStorage.set("targetbot.selectedConfig", name) end
  end

  if not data then
    setStatus("Off")
    if targetbotMacro and targetbotMacro.setOff then return targetbotMacro.setOff() end
    return
  end

  TargetBot.Creature.resetConfigs()
  for _, value in ipairs(data["targeting"] or {}) do
    TargetBot.Creature.addConfig(value)
  end
  TargetBot.Looting.update(data["looting"] or {})

  local isUserToggle = (TargetBot._initialized == true)
  local finalEnabled = enabled
  local storedEnabled = UnifiedStorage and UnifiedStorage.get("targetbot.enabled")
  if storedEnabled == nil then storedEnabled = storage.targetbotEnabled end
  if storedEnabled == true or storedEnabled == false then finalEnabled = storedEnabled end

  if not TargetBot._initialized then TargetBot._initialized = true end

  if isUserToggle then
    if enabled == false then
      TargetBot.explicitlyDisabled = true
      finalEnabled = false
      if UnifiedStorage then
        UnifiedStorage.set("targetbot.enabled", false)
        UnifiedStorage.set("targetbot.explicitlyDisabled", true)
      else storage.targetbotEnabled = false end
      storage.targetbotExplicitlyDisabled = true
    elseif enabled == true then
      TargetBot.explicitlyDisabled = false
      finalEnabled = true
      if UnifiedStorage then
        UnifiedStorage.set("targetbot.enabled", true)
        UnifiedStorage.set("targetbot.explicitlyDisabled", false)
      else storage.targetbotEnabled = true end
      storage.targetbotExplicitlyDisabled = false
    end
  else
    if TargetBot.explicitlyDisabled then finalEnabled = false end
  end

  if finalEnabled then setStatus("On") else setStatus("Off") end
  if targetbotMacro and targetbotMacro.setOn then
    targetbotMacro.setOn(finalEnabled)
    targetbotMacro.delay = nil
  end
  if finalEnabled then
    player = g_game and g_game.getLocalPlayer() or player
  end
  lureEnabled = true
end)

-- UI editor buttons
ui.editor.buttons.add.onClick = function()
  TargetBot.Creature.edit(nil, function(newConfig)
    TargetBot.Creature.addConfig(newConfig, true)
    TargetBot.save()
  end)
end

ui.editor.buttons.edit.onClick = function()
  local entry = ui.list:getFocusedChild()
  if not entry then return end
  TargetBot.Creature.edit(entry.value, function(newConfig)
    entry:setText(newConfig.name)
    entry.value = newConfig
    TargetBot.Creature.resetConfigsCache()
    TargetBot.save()
  end)
end

ui.editor.buttons.remove.onClick = function()
  local entry = ui.list:getFocusedChild()
  if not entry then return end
  entry:destroy()
  TargetBot.Creature.resetConfigsCache()
  TargetBot.save()
end

TargetBot.save = function()
  local data = {targeting={}, looting={}}
  for _, entry in ipairs(ui.list:getChildren()) do
    table.insert(data.targeting, entry.value)
  end
  TargetBot.Looting.save(data.looting)
  config.save(data)
end

-- Server "not possible" feedback handler
local UNREACHABLE_PATTERNS = { "sorry, not possible", "there is no way", "creature is not reachable" }

onTextMessage(function(mode, text)
  if not TargetBot or not TargetBot.canAttack or not TargetBot.canAttack() then return end
  if type(text) ~= "string" then return end
  local t = text:lower()
  local isUnreachable = false
  for i = 1, #UNREACHABLE_PATTERNS do
    if t:find(UNREACHABLE_PATTERNS[i], 1, true) then isUnreachable = true; break end
  end
  if not isUnreachable then return end

  local creature = nil
  local C = getClient()
  if C and C.getAttackingCreature then
    local ok, c = pcall(C.getAttackingCreature)
    if ok then creature = c end
  end
  if not creature and g_game and g_game.getAttackingCreature then
    local ok, c = pcall(g_game.getAttackingCreature)
    if ok then creature = c end
  end
  if not creature then return end

  local okMonster, isMonster = pcall(function() return creature:isMonster() end)
  if not okMonster or not isMonster then return end
  local okId, cid = pcall(function() return creature:getId() end)
  if not okId or not cid then return end

  if AttackStateMachine and AttackStateMachine.skipCreature then
    pcall(function() AttackStateMachine.skipCreature(cid, 15000) end)
  end
  -- Also mark in reachability cache so proactive check blocks this creature
  local Reachability = MonsterAI and MonsterAI.Reachability
  if Reachability and Reachability.markBlocked then
    pcall(function() Reachability.markBlocked(cid, "server_rejected", creature) end)
  end
  if AttackStateMachine and AttackStateMachine.stop then
    pcall(AttackStateMachine.stop)
  else
    pcall(function() TargetBot.stopAttack(true) end)
  end
end)
