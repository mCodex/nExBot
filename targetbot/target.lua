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

-- Persistent macro state (survives across 50ms ticks)
local M = { lastTargetId = nil, lastAsmRequest = 0, ASM_COOLDOWN = 500 }

-- Simple reachability: same floor + findPath attempt, never blocks (let server handle it)
local function checkReachable(playerPos, cpos)
  if not playerPos or not cpos then return true, 999 end
  if cpos.z ~= playerPos.z then return false, 999 end
  local PS = nExBot and nExBot.PathStrategy
  local ok, path = pcall(function()
    if PS and PS.findPath then
      return PS.findPath(playerPos, cpos, { maxSteps = 12, ignoreCreatures = true, ignoreNonPathable = true, ignoreCost = true })
    end
    return findPath(playerPos, cpos, 12, { ignoreCreatures = true, ignoreNonPathable = true, ignoreCost = true })
  end)
  if ok and path and #path > 0 then return true, #path end
  return true, math.max(math.abs(cpos.x - playerPos.x), math.abs(cpos.y - playerPos.y))
end

-- Main macro handler (used by both UnifiedTick and standalone macro)
local targetTickHandler = function()
  if not config or not config.isOn or not config.isOn() then return end
  if TargetBot and TargetBot.explicitlyDisabled then return end
  if zChanging() then return end

  pcall(AttackStateMachine.update)

  local Client = getClient()
  local isOnline = Client and Client.isOnline and Client.isOnline() or g_game and g_game.isOnline and g_game.isOnline()
  if not isOnline then return end

  local playerPos = player and player:getPosition()
  if not playerPos then return end

  local creatures = getNearbyCreatures(playerPos)
  local bestTarget, bestPriority = nil, 0
  local targets, dangerLevel = 0, 0

  for i = 1, #creatures do
    local c = creatures[i]
    repeat
      if not isTargetable(c) then break end

      local cpos = pcall(function() return c:getPosition() end) and c:getPosition()
      if not cpos then break end

      local dist = math.max(math.abs(cpos.x - playerPos.x), math.abs(cpos.y - playerPos.y))
      if dist > MAX_TARGET_DIST then break end

      local reachable, pathLen = checkReachable(playerPos, cpos)
      if not reachable then break end

      local cfg = TargetBot.Creature and TargetBot.Creature.getConfigs and TargetBot.Creature.getConfigs(c)
      if not cfg or #cfg == 0 then break end

      local configPrio = cfg[1].priority or 0
      local hp = 100
      pcall(function() hp = c:getHealthPercent() or 100 end)
      local hpBonus = (hp < 25) and (25 - hp) * 2 or 0
      local distBonus = math.max(0, MAX_TARGET_DIST - dist)
      local pathBonus = (pathLen == 1) and 10 or (pathLen <= 3 and 5 or 0)
      local priority = configPrio * 100 + distBonus + hpBonus + pathBonus

      dangerLevel = dangerLevel + (cfg[1].danger or 0)
      targets = targets + 1

      if priority > bestPriority then
        bestPriority = priority
        bestTarget = c
      end
    until true
  end

  dangerValue = dangerLevel
  setWidgetText(ui.danger.right, tostring(dangerLevel))

  if bestTarget then
    local name = pcall(function() return bestTarget:getName() end) and bestTarget:getName() or "?"
    setWidgetText(ui.target.right, name)
    setWidgetText(ui.config.right, pcall(function() return TargetBot.Creature.getConfigs(bestTarget)[1].name end) and TargetBot.Creature.getConfigs(bestTarget)[1].name or "-")
    setStatus("Killing (" .. targets .. ")")
    lastAction = now

    -- Only call ASM.requestAttack when target ID changes (prevents rapid switching)
    local newId = cId(bestTarget)
    if newId and newId ~= M.lastTargetId and (now - M.lastAsmRequest) >= M.ASM_COOLDOWN then
      M.lastTargetId = newId
      M.lastAsmRequest = now
      pcall(AttackStateMachine.requestAttack, bestTarget, bestPriority)
    end

    pcall(TargetBot.Creature.attack, { creature = bestTarget, config = (TargetBot.Creature.getConfigs and TargetBot.Creature.getConfigs(bestTarget) or {})[1] or {} }, targets, false)
    if TargetBot.walk then TargetBot.walk() end
    return
  end

  M.lastTargetId = nil
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
end

-- Sync persistent state when game target changes (e.g., right-click)
if EventBus and EventBus.on then
  EventBus.on("combat:target", function(creature)
    if creature then
      M.lastTargetId = cId(creature)
    else
      M.lastTargetId = nil
    end
  end)
end

-- Register on UnifiedTick (preferred) or fall back to standalone macro
if UnifiedTick and UnifiedTick.registerTargetingHandler then
  UnifiedTick.registerTargetingHandler("targetbot_main", targetTickHandler, 50)
  targetbotMacro = {
    setOn = function(e) UnifiedTick.setEnabled("targetbot_main", e ~= false) end,
    setOff = function() UnifiedTick.setEnabled("targetbot_main", false) end,
  }
else
  targetbotMacro = macro(50, targetTickHandler)
end

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
