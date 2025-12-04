--[[
  ============================================================================
  nExBot Automation Module
  ============================================================================
  
  Comprehensive automation features for convenience.
  
  FEATURES:
  - Anti-Kick (prevent logout due to inactivity)
  - Skin Monsters (auto skin/dust)
  - Auto Open Doors
  - Eat Food
  - Cast Food
  - Buy Bless
  - Hold MWall / Wild Growth
  - Highlight Target
  - Keep Crosshair
  - Train Magic Level
  - Check Players
  - Anti-Push
  - Anti-RS (Login Watcher)
  - Supply Control
  
  Author: nExBot Team
  Version: 2.0.0
  Last Updated: December 2025
  
  ============================================================================
]]

setDefaultTab("Tools")

--[[
  ============================================================================
  PANEL SETUP
  ============================================================================
]]

local panelName = "nexbotExtras"
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Extras')

  Button
    id: settings
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup

]])
ui:setId(panelName)

--[[
  ============================================================================
  STORAGE INITIALIZATION
  ============================================================================
]]

if not storage[panelName] then
  storage[panelName] = {
    enabled = false,
    -- Automation
    AntiKick = false,
    SkinMonsters = false,
    AutoOpenDoors = false,
    EatFood = false,
    CastFood = false,
    BuyBless = false,
    -- Combat
    HoldMwall = false,
    HoldWildGrowth = false,
    HighlightTarget = false,
    KeepCrosshair = false,
    TrainMagic = false,
    -- Safety
    CheckPlayers = false,
    AntiPush = false,
    AntiRs = false,
    SupplyControl = false,
    -- Timers
    MwallTimer = 3,
    WgTimer = 5,
    -- State
    lastActivity = 0,
    antiPushPos = nil
  }
end
local config = storage[panelName]

--[[
  ============================================================================
  UI TOGGLE
  ============================================================================
]]

ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
  storage[panelName] = config
end

--[[
  ============================================================================
  EXTRAS WINDOW
  ============================================================================
]]

local rootWidget = g_ui.getRootWidget()
local extrasWindow = nil

if rootWidget then
  local success, result = pcall(function()
    return UI.createWindow('ExtrasWindow', rootWidget)
  end)
  
  if success and result then
    extrasWindow = result
    extrasWindow:hide()
    
    -- Initialize checkboxes
    local function initCheckbox(id, configKey)
      local checkbox = extrasWindow:recursiveGetChildById(id)
      if checkbox then
        checkbox:setChecked(config[configKey] or false)
        checkbox.onClick = function(widget)
          config[configKey] = widget:isChecked()
          storage[panelName] = config
        end
      end
    end
    
    -- Initialize all checkboxes
    initCheckbox('AntiKick', 'AntiKick')
    initCheckbox('SkinMonsters', 'SkinMonsters')
    initCheckbox('AutoOpenDoors', 'AutoOpenDoors')
    initCheckbox('EatFood', 'EatFood')
    initCheckbox('CastFood', 'CastFood')
    initCheckbox('BuyBless', 'BuyBless')
    initCheckbox('HoldMwall', 'HoldMwall')
    initCheckbox('HoldWildGrowth', 'HoldWildGrowth')
    initCheckbox('HighlightTarget', 'HighlightTarget')
    initCheckbox('KeepCrosshair', 'KeepCrosshair')
    initCheckbox('TrainMagic', 'TrainMagic')
    initCheckbox('CheckPlayers', 'CheckPlayers')
    initCheckbox('AntiPush', 'AntiPush')
    initCheckbox('AntiRs', 'AntiRs')
    initCheckbox('SupplyControl', 'SupplyControl')
    
    -- Close button
    local closeBtn = extrasWindow:recursiveGetChildById('closeButton')
    if closeBtn then
      closeBtn.onClick = function()
        extrasWindow:hide()
      end
    end
    
    extrasWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        storage[panelName] = config
      end
    end
  end
end

ui.settings.onClick = function(widget)
  if extrasWindow then
    extrasWindow:show()
    extrasWindow:raise()
    extrasWindow:focus()
  else
    warn("[Extras] Extras window not available")
  end
end

--[[
  ============================================================================
  ANTI-KICK (Prevent logout due to inactivity)
  ============================================================================
]]

local lastAntiKick = 0
macro(60000, function()
  if not config.enabled or not config.AntiKick then return end
  if now - lastAntiKick < 60000 then return end
  
  local directions = {North, South, East, West}
  local dir = directions[math.random(1, 4)]
  turn(dir)
  lastAntiKick = now
end)

--[[
  ============================================================================
  AUTO OPEN DOORS
  ============================================================================
]]

local doorIds = {
  5100, 5101, 5102, 5103, 5104, 5105, 5106, 5107, 5108, 5109,
  5110, 5111, 5112, 5113, 5114, 5115, 5116, 5117, 5118, 5119,
  5120, 5121, 5122, 5123, 5124, 5125, 5126, 5127, 5128, 5129,
  1209, 1210, 1211, 1212, 1213, 1214, 1215, 1216, 1217, 1218,
  1219, 1220, 1221, 1222, 1223, 1224, 1225, 1226, 1227, 1228,
  1229, 1230, 1231, 1232, 1233, 1234
}

local doorIdSet = {}
for _, id in ipairs(doorIds) do
  doorIdSet[id] = true
end

macro(200, function()
  if not config.enabled or not config.AutoOpenDoors then return end
  
  local myPos = player:getPosition()
  
  for dx = -1, 1 do
    for dy = -1, 1 do
      if dx ~= 0 or dy ~= 0 then
        local pos = {x = myPos.x + dx, y = myPos.y + dy, z = myPos.z}
        local tile = g_map.getTile(pos)
        if tile then
          local topThing = tile:getTopUseThing()
          if topThing and doorIdSet[topThing:getId()] then
            use(topThing)
            return
          end
        end
      end
    end
  end
end)

--[[
  ============================================================================
  EAT FOOD
  ============================================================================
]]

local foodIds = {
  3607, 3585, 3593, 3582, 3600, 3601, 3599, 3596, 3586, 3592,
  3597, 3583, 3587, 3588, 3589, 3590, 3591, 3723, 8112, 9992,
  3595, 3606, 3578, 3584
}

local lastEatFood = 0
macro(30000, function()
  if not config.enabled or not config.EatFood then return end
  if now - lastEatFood < 30000 then return end
  
  for _, foodId in ipairs(foodIds) do
    if itemAmount(foodId) > 0 then
      useWith(foodId, player)
      lastEatFood = now
      return
    end
  end
end)

--[[
  ============================================================================
  CAST FOOD
  ============================================================================
]]

local castFoodSpells = {
  "exevo pan",
  "conjure food"
}

local lastCastFood = 0
macro(60000, function()
  if not config.enabled or not config.CastFood then return end
  if now - lastCastFood < 60000 then return end
  
  -- Check if we have food
  local hasFood = false
  for _, foodId in ipairs(foodIds) do
    if itemAmount(foodId) > 0 then
      hasFood = true
      break
    end
  end
  
  if not hasFood then
    for _, spell in ipairs(castFoodSpells) do
      if canCast(spell) then
        say(spell)
        lastCastFood = now
        return
      end
    end
  end
end)

--[[
  ============================================================================
  SKIN MONSTERS
  ============================================================================
]]

local skinKnives = {5908, 5942}
local skinItemId = 5908

macro(500, function()
  if not config.enabled or not config.SkinMonsters then return end
  
  local myPos = player:getPosition()
  
  for _, spec in ipairs(getSpectators()) do
    if spec:isDead() and not spec:isPlayer() then
      local specPos = spec:getPosition()
      if myPos.z == specPos.z then
        local distance = math.max(math.abs(myPos.x - specPos.x), math.abs(myPos.y - specPos.y))
        if distance <= 1 then
          for _, knifeId in ipairs(skinKnives) do
            if itemAmount(knifeId) > 0 then
              useWith(knifeId, spec)
              return
            end
          end
        end
      end
    end
  end
end)

--[[
  ============================================================================
  HIGHLIGHT TARGET
  ============================================================================
]]

local highlightedTarget = nil

onAttackingCreatureChange(function(creature)
  -- Remove old highlight
  if highlightedTarget and highlightedTarget.setMarked then
    highlightedTarget:setMarked('')
  end
  
  if config.enabled and config.HighlightTarget and creature then
    highlightedTarget = creature
    if creature.setMarked then
      creature:setMarked('red')
    end
  else
    highlightedTarget = nil
  end
end)

--[[
  ============================================================================
  ANTI-PUSH
  ============================================================================
]]

local lastAntiPushPos = nil

onPlayerPositionChange(function(newPos, oldPos)
  if not config.enabled or not config.AntiPush then return end
  if player:isWalking() then
    lastAntiPushPos = newPos
    return
  end
  
  -- Check if we were pushed (position changed without walking)
  if lastAntiPushPos then
    if newPos.x ~= lastAntiPushPos.x or newPos.y ~= lastAntiPushPos.y then
      -- Was pushed, try to walk back
      schedule(100, function()
        if not player:isWalking() then
          autoWalk(lastAntiPushPos, 5, {marginMin = 0, marginMax = 0})
        end
      end)
    end
  end
  
  lastAntiPushPos = newPos
end)

--[[
  ============================================================================
  CHECK PLAYERS (Alert when player detected)
  ============================================================================
]]

local checkedPlayers = {}
local lastPlayerCheck = 0

macro(500, function()
  if not config.enabled or not config.CheckPlayers then return end
  if now - lastPlayerCheck < 500 then return end
  lastPlayerCheck = now
  
  local myPos = player:getPosition()
  
  for _, spec in ipairs(getSpectators()) do
    if spec:isPlayer() and spec ~= player then
      local name = spec:getName()
      if not checkedPlayers[name] then
        checkedPlayers[name] = true
        
        -- Alert
        playSound("/sounds/Player.ogg")
        warn("[Check Players] Player detected: " .. name)
        
        if nExBot and nExBot.EventBus then
          nExBot.EventBus:emit("extras:playerDetected", name)
        end
      end
    end
  end
end)

-- Reset checked players periodically
onPlayerPositionChange(function(newPos, oldPos)
  if newPos.z ~= oldPos.z then
    checkedPlayers = {}
  end
end)

--[[
  ============================================================================
  ANTI-RS (Login Watcher)
  ============================================================================
]]

local antiRsEnabled = false
local antiRsLogoutTime = 0

macro(1000, function()
  if not config.enabled or not config.AntiRs then return end
  
  local myPos = player:getPosition()
  
  for _, spec in ipairs(getSpectators()) do
    if spec:isPlayer() and spec ~= player then
      -- Player detected, prepare to logout
      antiRsEnabled = true
      antiRsLogoutTime = now + 3000  -- 3 seconds delay
      
      warn("[Anti-RS] Player detected! Will logout in 3 seconds...")
      
      if nExBot and nExBot.EventBus then
        nExBot.EventBus:emit("extras:antiRsTriggered", spec:getName())
      end
      
      break
    end
  end
  
  -- Execute logout if time reached
  if antiRsEnabled and now >= antiRsLogoutTime then
    antiRsEnabled = false
    
    -- Stop cavebot if available
    if CaveBot and CaveBot.setOff then
      CaveBot:setOff()
    end
    
    -- Try to logout
    if g_game.safeLogout then
      g_game.safeLogout()
    end
    
    warn("[Anti-RS] Logging out due to player detection!")
  end
end)

--[[
  ============================================================================
  HOLD MWALL / WILD GROWTH
  ============================================================================
]]

local mwallPositions = {}
local wgPositions = {}

-- Track magic walls
onAddThing(function(tile, thing)
  if not thing:isItem() then return end
  
  local itemId = thing:getId()
  local pos = tile:getPosition()
  local posKey = pos.x .. "," .. pos.y .. "," .. pos.z
  
  -- Magic Wall (ID varies by server)
  if itemId == 2129 or itemId == 2130 then
    mwallPositions[posKey] = {
      pos = pos,
      time = now
    }
  end
  
  -- Wild Growth
  if itemId == 2130 or itemId == 2131 then
    wgPositions[posKey] = {
      pos = pos,
      time = now
    }
  end
end)

macro(1000, function()
  if not config.enabled then return end
  
  local currentTime = now
  
  -- Check magic walls
  if config.HoldMwall then
    local mwallTimer = (config.MwallTimer or 3) * 1000
    for posKey, data in pairs(mwallPositions) do
      if currentTime - data.time >= (20000 - mwallTimer) then
        -- Recast magic wall
        if canCast("adori mas flam") then
          useWith(3180, data.pos)  -- Magic wall rune
        end
        mwallPositions[posKey] = nil
      end
    end
  end
  
  -- Check wild growth
  if config.HoldWildGrowth then
    local wgTimer = (config.WgTimer or 5) * 1000
    for posKey, data in pairs(wgPositions) do
      if currentTime - data.time >= (45000 - wgTimer) then
        -- Recast wild growth
        if canCast("adori max vis") then
          useWith(3156, data.pos)  -- Wild growth rune
        end
        wgPositions[posKey] = nil
      end
    end
  end
end)

--[[
  ============================================================================
  PUBLIC API
  ============================================================================
]]

Extras = {
  isOn = function() return config.enabled end,
  isOff = function() return not config.enabled end,
  
  setOn = function()
    config.enabled = true
    ui.title:setOn(true)
    storage[panelName] = config
  end,
  
  setOff = function()
    config.enabled = false
    ui.title:setOn(false)
    storage[panelName] = config
  end,
  
  -- Feature toggles
  setAntiKick = function(enabled)
    config.AntiKick = enabled
    storage[panelName] = config
  end,
  
  setAutoOpenDoors = function(enabled)
    config.AutoOpenDoors = enabled
    storage[panelName] = config
  end,
  
  setEatFood = function(enabled)
    config.EatFood = enabled
    storage[panelName] = config
  end,
  
  setCastFood = function(enabled)
    config.CastFood = enabled
    storage[panelName] = config
  end,
  
  setSkinMonsters = function(enabled)
    config.SkinMonsters = enabled
    storage[panelName] = config
  end,
  
  setHoldMwall = function(enabled)
    config.HoldMwall = enabled
    storage[panelName] = config
  end,
  
  setHoldWildGrowth = function(enabled)
    config.HoldWildGrowth = enabled
    storage[panelName] = config
  end,
  
  setHighlightTarget = function(enabled)
    config.HighlightTarget = enabled
    storage[panelName] = config
  end,
  
  setCheckPlayers = function(enabled)
    config.CheckPlayers = enabled
    storage[panelName] = config
  end,
  
  setAntiPush = function(enabled)
    config.AntiPush = enabled
    storage[panelName] = config
  end,
  
  setAntiRs = function(enabled)
    config.AntiRs = enabled
    storage[panelName] = config
  end,
  
  -- Status checks
  isAntiKick = function() return config.AntiKick end,
  isAutoOpenDoors = function() return config.AutoOpenDoors end,
  isEatFood = function() return config.EatFood end,
  isSkinMonsters = function() return config.SkinMonsters end,
  isHoldMwall = function() return config.HoldMwall end,
  isCheckPlayers = function() return config.CheckPlayers end,
  isAntiPush = function() return config.AntiPush end,
  isAntiRs = function() return config.AntiRs end,
  
  -- Show window
  show = function()
    if extrasWindow then
      extrasWindow:show()
      extrasWindow:raise()
      extrasWindow:focus()
    end
  end
}

logInfo("[Automation] Module loaded")
