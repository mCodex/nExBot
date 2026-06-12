--[[
  Friend Healer UI & Integration
  
  Uses BotCore.FriendHealer for high-performance healing logic.
  This file handles UI and configuration only.
  
  Features:
    - Shares exhaustion with HealBot via BotCore.Cooldown
    - Priority-based: Self-healing ALWAYS takes precedence
    - Event-driven for instant response to health changes
    - Custom player list persisted per-character via CharacterDB
    - Vocation filtering integrated with VocationUtils
]]

setDefaultTab("Main")
local panelName = "newHealer"
local ui = setupUI([[
NxBotSection
  height: 30

  NxSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    anchors.right: parent.right
    margin-right: 50
    margin-top: 0
    !text: tr('Friend Healer')

  NxButton
    id: edit
    anchors.top: parent.top
    anchors.right: parent.right
    width: 46
    height: 20
    text: Setup
      
]])
ui:setId(panelName)

-- ============================================================================
-- CONFIGURATION (persisted in storage)
-- ============================================================================

-- Validate and migrate old config
if not storage[panelName] or not storage[panelName].priorities then
    storage[panelName] = nil
end

if not storage[panelName] then
    storage[panelName] = {
        enabled = false,
        customPlayers = {},
        vocations = {},
        groups = {},
        priorities = {
            {name="Custom Spell",           enabled=false, custom=true},
            {name="Exura Gran Sio",         enabled=true,              strong = true},
            {name="Exura Tio Sio",          enabled=true,                             medium = true},
            {name="Exura Sio",              enabled=true,                                            normal = true},
            {name="Exura Gran Mas Res",     enabled=true,                                                          area = true},
            {name="Health Item",            enabled=true,                                                                      health=true},
            {name="Mana Item",              enabled=true,                                                                                  mana=true}
        },
        settings = {
            {type="HealItem",       text="Mana Item ",                   value=268},
            {type="HealScroll",     text="Item Range: ",                 value=6},
            {type="HealItem",       text="Health Item ",                 value=3160},
            {type="HealScroll",     text="Mas Res Players: ",            value=2},
            {type="HealScroll",     text="Heal Friend at: ",             value=80},
            {type="HealScroll",     text="Use Gran Sio at: ",            value=40},
            {type="HealScroll",     text="Use Tio Sio at: ",             value=65},
            {type="HealScroll",     text="Min Player HP%: ",             value=80},
            {type="HealScroll",     text="Min Player MP%: ",             value=50},
        },
        conditions = {
            knights = true,
            paladins = true,
            druids = false,
            sorcerers = false,
            monks = false,
            party = true,
            guild = false,
            friends = false
        }
    }
end

local config = storage[panelName]

local function normalizeSettings(settings)
    if type(settings) ~= "table" then
        settings = {}
    end

    local hasTio = false
    for i = 1, #settings do
        local text = settings[i] and settings[i].text
        if text and text:find("Tio Sio") then
            hasTio = true
            break
        end
    end

    if not hasTio then
        table.insert(settings, 7, {type="HealScroll", text="Use Tio Sio at: ", value=65})
    end

    return settings
end

local function getSettingValue(idx, default)
    local entry = config.settings and config.settings[idx]
    if entry and entry.value ~= nil then
        return entry.value
    end
    return default
end

config.settings = normalizeSettings(config.settings)

-- ============================================================================
-- CHARACTERDB INTEGRATION: Per-character custom players list
-- Migrates from shared storage to per-character storage on first load
-- ============================================================================

local function loadCharacterCustomPlayers()
  if not CharacterDB or not CharacterDB.isReady or not CharacterDB.isReady() then
    return
  end
  -- Try to load per-character custom players
  local charPlayers = CharacterDB.get("friendHealer.customPlayers")
  if charPlayers and type(charPlayers) == "table" and #charPlayers > 0 then
    config.customPlayers = charPlayers
  elseif config.customPlayers and #config.customPlayers > 0 then
    -- Migrate existing shared custom players to CharacterDB
    CharacterDB.set("friendHealer.customPlayers", config.customPlayers)
  end
  -- Also load per-character conditions
  local charConditions = CharacterDB.get("friendHealer.conditions")
  if charConditions and type(charConditions) == "table" then
    for k, v in pairs(charConditions) do
      config.conditions[k] = v
    end
  end
end

-- Defer loading until player is available
schedule(500, loadCharacterCustomPlayers)

-- Save custom players to both storage and CharacterDB
local function saveCustomPlayers()
  if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
    CharacterDB.set("friendHealer.customPlayers", config.customPlayers)
  end
end

-- ============================================================================
-- BOTCORE INTEGRATION: Build config for FriendHealer module
-- ============================================================================

-- Convert UI config to BotCore format (pure function)
local function buildBotCoreConfig()
  local bcConfig = {
    enabled = config.enabled,
    customPlayers = config.customPlayers or {},
    conditions = config.conditions or {},
    settings = {
            manaItem = getSettingValue(1, 268),
            itemRange = getSettingValue(2, 6),
            healthItem = getSettingValue(3, 3160),
            masResPlayers = getSettingValue(4, 2),
            healAt = getSettingValue(5, 80),
            granSioAt = getSettingValue(6, 40),
            tioSioAt = getSettingValue(7, 65),
            minPlayerHp = getSettingValue(8, 80),
            minPlayerMp = getSettingValue(9, 50),
    },
    -- Priority actions (in order)
    useSio = false,
    useGranSio = false,
    useTioSio = false,
    useMasRes = false,
    useHealthItem = false,
    useManaItem = false,
    customSpell = false,
    customSpellName = nil
  }
  
  -- Map priorities
  for _, p in ipairs(config.priorities or {}) do
    if p.enabled then
      if p.strong then bcConfig.useGranSio = true end
      if p.medium then bcConfig.useTioSio = true end
      if p.normal then bcConfig.useSio = true end
      if p.area then bcConfig.useMasRes = true end
      if p.health then bcConfig.useHealthItem = true end
      if p.mana then bcConfig.useManaItem = true end
      if p.custom then 
        bcConfig.customSpell = true 
        bcConfig.customSpellName = p.name
      end
    end
  end
  
  return bcConfig
end

-- Initialize BotCore FriendHealer if available
local function initBotCoreHealer()
  if BotCore and BotCore.FriendHealer and BotCore.FriendHealer.init then
    local bcConfig = buildBotCoreConfig()
    BotCore.FriendHealer.init(bcConfig)
    if BotCore.FriendHealer.setEnabled then
      BotCore.FriendHealer.setEnabled(config.enabled)
    end
    return true
  end
  return false
end

-- Update BotCore when config changes (also syncs HealEngine spells)
local function updateBotCoreConfig()
  if BotCore and BotCore.FriendHealer and BotCore.FriendHealer.init then
    local bcConfig = buildBotCoreConfig()
    BotCore.FriendHealer.init(bcConfig)
    -- Sync spells to HealEngine
    if BotCore.FriendHealer.syncHealEngineSpells then
      BotCore.FriendHealer.syncHealEngineSpells()
    end
  end
end

-- Macro handle so we can fully stop the engine when unused
local friendHealerMacro = nil

local function syncFriendHealerState()
    -- Update BotCore FriendHealer
    if BotCore and BotCore.FriendHealer and BotCore.FriendHealer.setEnabled then
        BotCore.FriendHealer.setEnabled(config.enabled)
        -- Also sync spell configuration
        if BotCore.FriendHealer.syncHealEngineSpells then
            BotCore.FriendHealer.syncHealEngineSpells()
        end
    end
    -- Update HealEngine directly too
    if HealEngine and HealEngine.setFriendHealingEnabled then
        HealEngine.setFriendHealingEnabled(config.enabled)
    end
    -- Update macro state
    if friendHealerMacro and friendHealerMacro.setOn then
        friendHealerMacro:setOn(config.enabled)
    end
end
local healerWindow = UI.createWindow('FriendHealer')
healerWindow:hide()
healerWindow:setId(panelName)

ui.title:setOn(config.enabled)
ui.title.onClick = function(widget)
    config.enabled = not config.enabled
    widget:setOn(config.enabled)
    syncFriendHealerState()
end

-- Initialize integration on load so unused friend heal stays disabled by default
initBotCoreHealer()
syncFriendHealerState()

ui.edit.onClick = function()
    healerWindow:show()
    healerWindow:raise()
    healerWindow:focus()
end

local conditions = healerWindow.conditions
local targetSettings = healerWindow.targetSettings
local customList = healerWindow.customList
local priority = healerWindow.priority

-- customList
-- DRY: Helper to create a player entry widget
local function createPlayerEntry(name, health)
    local widget = UI.createWidget("HealerPlayerEntry", customList.playerList.list)
    widget.remove.onClick = function()
        config.customPlayers[name] = nil
        widget:destroy()
        saveCustomPlayers()
        updateBotCoreConfig()
    end
    widget:setText("["..health.."%]  "..name)
    return widget
end

for name, health in pairs(config.customPlayers) do
    createPlayerEntry(name, health)
end

customList.playerList.onDoubleClick = function()
    customList.playerList:hide()
end

local function clearFields()
    customList.addPanel.name:setText("friend name")
    customList.addPanel.health:setText("1")
    customList.playerList:show()
end

-- Use Shared.properCase for name formatting (fixes leading space bug)
local properCase = nExBot and nExBot.Shared and nExBot.Shared.properCase or function(str)
  local words = {}
  for word in str:gmatch("%S+") do
    words[#words + 1] = word:sub(1,1):upper() .. word:sub(2)
  end
  return table.concat(words, " ")
end

customList.addPanel.add.onClick = function()
    local rawName = customList.addPanel.name:getText()
    local name = properCase(rawName)
    local health = tonumber(customList.addPanel.health:getText())

    if not health then    
        clearFields()
        return warn("[Friend Healer] Please enter health percent value!")
    end

    if name:len() == 0 or name:lower() == "friend name" then   
        clearFields()
        return warn("[Friend Healer] Please enter friend name to be added!")
    end

    if config.customPlayers[name] or config.customPlayers[name:lower()] then 
        clearFields()
        return warn("[Friend Healer] Player already added to custom list.")
    else
        config.customPlayers[name] = health
        createPlayerEntry(name, health)
        saveCustomPlayers()
        updateBotCoreConfig()
    end

    clearFields()
end

local function validate(widget, category)
    local list = widget:getParent()
    local label = list:getParent().title
    -- 1 - priorities | 2 - vocation
    category = category or 0

    if category == 2 and not storage.extras.checkPlayer then
        label:setColor("#d9321f")
        label:setTooltip("! WARNING ! \nTurn on check players in extras to use this feature!")
        return
    else
        label:setColor("#dfdfdf")
        label:setTooltip("")
    end

    local checked = false
    for i, child in ipairs(list:getChildren()) do
        if category == 1 and child.enabled:isChecked() or child:isChecked() then
            checked = true
        end
    end

    if not checked then
        label:setColor("#d9321f")
        label:setTooltip("! WARNING ! \nNo category selected!")
    else
        label:setColor("#dfdfdf")
        label:setTooltip("")
    end
end
-- DRY: Generic checkbox binder for condition toggles
local function bindConditionCheckbox(widget, conditionKey, category)
  widget:setChecked(config.conditions[conditionKey])
  widget.onClick = function(w)
    config.conditions[conditionKey] = not config.conditions[conditionKey]
    w:setChecked(config.conditions[conditionKey])
    validate(w, category or 0)
    updateBotCoreConfig()
    -- Persist to CharacterDB if available
    if CharacterDB and CharacterDB.isReady and CharacterDB.isReady() then
      CharacterDB.set("friendHealer.conditions", config.conditions)
    end
  end
end

-- Vocation checkboxes (category 2 = requires checkPlayer)
bindConditionCheckbox(targetSettings.vocations.box.knights, "knights", 2)
bindConditionCheckbox(targetSettings.vocations.box.paladins, "paladins", 2)
bindConditionCheckbox(targetSettings.vocations.box.druids, "druids", 2)
bindConditionCheckbox(targetSettings.vocations.box.sorcerers, "sorcerers", 2)
bindConditionCheckbox(targetSettings.vocations.box.monks, "monks", 2)

-- Group checkboxes (category 0 = no special requirement)
bindConditionCheckbox(targetSettings.groups.box.friends, "friends")
bindConditionCheckbox(targetSettings.groups.box.party, "party")
bindConditionCheckbox(targetSettings.groups.box.guild, "guild")

validate(targetSettings.vocations.box.knights)
validate(targetSettings.groups.box.friends)
validate(targetSettings.vocations.box.sorcerers, 2)

-- conditions
for i, setting in ipairs(config.settings) do
    local widget = UI.createWidget(setting.type, conditions.box)
    local text = setting.text
    local val = setting.value
    widget.text:setText(text)

    if setting.type == "HealScroll" then
        widget.text:setText(widget.text:getText()..val)
        if not (text:find("Range") or text:find("Mas Res")) then
            widget.text:setText(widget.text:getText().."%")
        end
        widget.scroll:setValue(val)
        widget.scroll.onValueChange = function(scroll, value)
            setting.value = value
            widget.text:setText(text..value)
            if not (text:find("Range") or text:find("Mas Res")) then
                widget.text:setText(widget.text:getText().."%")
            end
            -- Sync config changes to BotCore when settings change
            updateBotCoreConfig()
        end
        if text:find("Range") or text:find("Mas Res") then
            widget.scroll:setMaximum(10)
        end
    else
        widget.item:setItemId(val)
        widget.item:setShowCount(false)
        widget.item.onItemChange = function(widget)
            setting.value = widget:getItemId()
            -- Sync config changes to BotCore when item changes
            updateBotCoreConfig()
        end
    end
end



-- priority and toggles
local function setCrementalButtons()
    local children = priority.list:getChildren()
    local count = #children
    for i, child in ipairs(children) do
        if i == 1 then
            child.increment:disable()
        elseif i == count then
            child.decrement:disable()
        else
            child.increment:enable()
            child.decrement:enable()
        end
    end
end

-- Helper to create a priority entry widget
local function createPriorityWidget(action, index)
    local widget = UI.createWidget("PriorityEntry", priority.list)

    widget:setText(action.name)
    widget.increment.onClick = function()
        local idx = priority.list:getChildIndex(widget)
        local tbl = config.priorities

        priority.list:moveChildToIndex(widget, idx-1)
        tbl[idx], tbl[idx-1] = tbl[idx-1], tbl[idx]
        setCrementalButtons()
        updateBotCoreConfig()
    end
    widget.decrement.onClick = function()
        local idx = priority.list:getChildIndex(widget)
        local tbl = config.priorities

        priority.list:moveChildToIndex(widget, idx+1)
        tbl[idx], tbl[idx+1] = tbl[idx+1], tbl[idx]
        setCrementalButtons()
        updateBotCoreConfig()
    end
    widget.enabled:setChecked(action.enabled)
    widget:setColor(action.enabled and "#98BF64" or "#dfdfdf")
    widget.enabled.onClick = function()
        action.enabled = not action.enabled
        widget:setColor(action.enabled and "#98BF64" or "#dfdfdf")
        widget.enabled:setChecked(action.enabled)
        validate(widget, 1)
        updateBotCoreConfig()  
    end
    
    -- Show remove button for custom spells
    if action.custom then
        widget.remove:show()
        widget.remove.onClick = function()
            -- Remove from config
            local idx = priority.list:getChildIndex(widget)
            table.remove(config.priorities, idx)
            widget:destroy()
            setCrementalButtons()
            validate(priority.list:getFirstChild(), 1)
            updateBotCoreConfig()
        end
        widget.onDoubleClick = function()
            local window = modules.client_textedit.show(widget, {title = "Custom Spell", description = "Enter below formula for a custom healing spell"})
            schedule(50, function() 
              window:raise()
              window:focus() 
            end)
        end
        widget.onTextChange = function(w, text)
            action.name = text
            updateBotCoreConfig()
        end
        widget:setTooltip("Double click to edit. X to remove.")
    end
    
    return widget
end

-- Build initial priority list
for i, action in ipairs(config.priorities) do
    createPriorityWidget(action, i)
    
    if i == #config.priorities then
        validate(priority.list:getFirstChild(), 1)
        setCrementalButtons()
    end
end

-- Add Custom Spell button handler
priority.addSpellButton.onClick = function()
    -- Create new custom spell entry
    local newSpell = {
        name = "Custom Spell " .. (#config.priorities + 1),
        enabled = true,
        custom = true
    }
    table.insert(config.priorities, newSpell)
    local widget = createPriorityWidget(newSpell, #config.priorities)
    setCrementalButtons()
    updateBotCoreConfig()
    
    -- Open text edit for the new spell
    schedule(100, function()
        local window = modules.client_textedit.show(widget, {title = "Custom Spell", description = "Enter below formula for a custom healing spell"})
        schedule(50, function() 
            window:raise()
            window:focus() 
        end)
    end)
end

-- ============================================================================
-- BOTCORE-POWERED FRIEND HEALER
-- Uses BotCore.FriendHealer for high-performance healing with shared exhaustion
-- ============================================================================

-- Track if BotCore is available
local useBotCore = false

-- Initialize on load
schedule(100, function()
  useBotCore = initBotCoreHealer()
  syncFriendHealerState()
  if useBotCore then
    -- BotCore high-performance mode enabled
    -- Configure HealEngine friend spells based on UI priorities
    if HealEngine and HealEngine.setFriendSpells then
      local friendSpells = {}
    local healAt = getSettingValue(5, 80)
    local granSioAt = getSettingValue(6, 40)
      
      for i, action in ipairs(config.priorities or {}) do
        if action.enabled then
          if action.strong then
            table.insert(friendSpells, {
              name = "exura gran sio",
              hp = granSioAt,
              mpCost = 140,
              cd = 1100,
              prio = 1
            })
          end
          if action.medium then
                        local tioSioAt = getSettingValue(7, 65)
            table.insert(friendSpells, {
              name = "exura tio sio",
              hp = tioSioAt,
              mpCost = 120,
              cd = 1100,
              prio = 2
            })
          end
          if action.normal then
            table.insert(friendSpells, {
              name = "exura sio",
              hp = healAt,
              mpCost = 100,
              cd = 1100,
              prio = 3
            })
          end
          if action.custom and action.name and action.name ~= "Custom Spell" then
            table.insert(friendSpells, {
              name = action.name,
              hp = healAt,
              mpCost = 50,
              cd = 1100,
              prio = 3
            })
          end
        end
      end
      
      if #friendSpells > 0 then
        HealEngine.setFriendSpells(friendSpells)
      end
    end
  end
end)

-- Legacy fallback functions (used when BotCore is not available)
local lastItemUse = now

local function legacyHealAction(spec, targetsInRange)
    local name = spec:getName()
    local health = spec:getHealthPercent()
    local mana = spec:getManaPercent()
    local dist = distanceFromPlayer(spec:getPosition())
    targetsInRange = targetsInRange or 0

    local masResAmount = getSettingValue(4, 2)
    local itemRange = getSettingValue(2, 6)
    local healItem = getSettingValue(3, 3160)
    local manaItem = getSettingValue(1, 268)
    local normalHeal = config.customPlayers[name] or getSettingValue(5, 80)
    local strongHeal = config.customPlayers[name] and normalHeal/2 or getSettingValue(6, 40)
    local mediumHeal = getSettingValue(7, 65)

    -- Check healing cooldown (shared with HealBot via BotCore)
    local canHeal = true
    if BotCore and BotCore.Cooldown and BotCore.Cooldown.isHealingOnCooldown then
        canHeal = not BotCore.Cooldown.isHealingOnCooldown()
    elseif modules and modules.game_cooldown then
        canHeal = not modules.game_cooldown.isGroupCooldownIconActive(2)
    end
    if not canHeal then return end

    for i, action in ipairs(config.priorities) do
        if action.enabled then
            if action.area and masResAmount <= targetsInRange and canCast("exura gran mas res") then
                return say("exura gran mas res")
            end
            if action.mana and findItem(manaItem) and mana <= normalHeal and dist <= itemRange and now - lastItemUse > 1000 then
                lastItemUse = now
                if BotCore and BotCore.Cooldown then BotCore.Cooldown.markPotionUsed() end
                return SafeCall.useWith(manaItem, spec)
            end
            if action.health and findItem(healItem) and health <= normalHeal and dist <= itemRange and now - lastItemUse > 1000 then
                lastItemUse = now
                if BotCore and BotCore.Cooldown then BotCore.Cooldown.markPotionUsed() end
                return SafeCall.useWith(healItem, spec)
            end
            if action.strong and health <= strongHeal then
                local canCastGranSio = true
                if modules and modules.game_cooldown then
                    canCastGranSio = not modules.game_cooldown.isCooldownIconActive(131)
                end
                if canCastGranSio then
                    return say('exura gran sio "'..name)
                end
            end
            if action.medium and health <= mediumHeal and canCast('exura tio sio "'..name) then
                return say('exura tio sio "'..name)
            end
            if (action.normal or action.custom) and health <= normalHeal and canCast('exura sio "'..name) then
                return say('exura sio "'..name)
            end
        end
    end
end

local function legacyIsCandidate(spec)
    if spec:isLocalPlayer() or not spec:isPlayer() then 
        return nil 
    end
    if not spec:canShoot() then
        return false
    end
    
    local name = spec:getName()
    local curHp = spec:getHealthPercent()
    if curHp == 100 or (config.customPlayers[name] and curHp > config.customPlayers[name]) then
        return false
    end

    -- Vocation filter (map-based for DRY/KISS)
    local vocConditionMap = {
      EK = "knights", RP = "paladins", ED = "druids",
      MS = "sorcerers", MN = "monks"
    }
    if storage.extras and storage.extras.checkPlayer and VocationUtils and VocationUtils.getCreatureVocationShort then
        local short = VocationUtils.getCreatureVocationShort(spec)
        local condKey = short and vocConditionMap[short]
        if condKey and not config.conditions[condKey] and not config.customPlayers[name] then
            return nil
        end
    end

    local okParty = config.conditions.party and spec:isPartyMember()
    local okFriend = config.conditions.friends and isFriend and isFriend(spec)
    local okGuild = config.conditions.guild and spec:getEmblem() == 1

    if not (okParty or okFriend or okGuild) and not config.customPlayers[name] then
        return nil
    end

    local health = config.customPlayers[name] and curHp/2 or curHp
    local dist = distanceFromPlayer(spec:getPosition())

    return health, dist
end

-- ============================================================================
-- MAIN MACRO: Uses BotCore when available, falls back to legacy
-- ============================================================================

friendHealerMacro = macro(100, function()
    if not config.enabled then return end
    
    -- Update BotCore config on each tick (in case settings changed)
    if useBotCore and BotCore and BotCore.FriendHealer then
        -- Let BotCore handle everything
        local actionTaken = BotCore.FriendHealer.tick()
        -- If BotCore handled the heal, skip legacy fallback
        if actionTaken then return end
    end
    
    -- Only use legacy fallback if BotCore is not available
    -- This prevents double-healing attempts
    if useBotCore then return end
    
    -- Legacy fallback (only when BotCore is unavailable)
    
    -- Check healing cooldown
    if modules and modules.game_cooldown and modules.game_cooldown.isGroupCooldownIconActive(2) then 
        return 
    end

    local minHp = getSettingValue(8, 80)
    local minMp = getSettingValue(9, 50)

    -- Safety: Don't heal friends if self needs healing
    if hppercent() <= minHp or manapercent() <= minMp then return end

    local healTarget = {creature=nil, hp=100}
    local inMasResRange = 0

    -- Scan spectators
    local spectators = {}
    if getSpectators then
        local ok, specs = pcall(getSpectators)
        if ok and specs then spectators = specs end
    elseif SafeCall and SafeCall.global then
        spectators = SafeCall.global("getSpectators") or {}
    end
    
    for i, spec in ipairs(spectators) do
        local health, dist = legacyIsCandidate(spec)
        if dist then
            inMasResRange = dist <= 3 and inMasResRange+1 or inMasResRange
            if health < healTarget.hp then
                healTarget = {creature = spec, hp = health}
            end
        end
    end

    -- Execute heal
    if healTarget.creature then
        return legacyHealAction(healTarget.creature, inMasResRange)
    end
end)

syncFriendHealerState()

-- ============================================================================
-- EVENT-DRIVEN HEALING
-- Note: EventBus handlers are registered by BotCore.FriendHealer module
-- This section only provides legacy fallback when EventBus is unavailable
-- ============================================================================

-- Fallback: Hook into creature health changes for instant response (legacy only)
-- Only register if EventBus is NOT available (FriendHealer handles EventBus)
if onCreatureHealthPercentChange and not EventBus then
    onCreatureHealthPercentChange(function(creature, newHp, oldHp)
        if not config.enabled then return end
        if not creature then return end
        
        -- Skip non-players and local player
        local ok, isPlayer = pcall(function() return creature:isPlayer() end)
        if not ok or not isPlayer then return end
        local ok2, isLocal = pcall(function() return creature:isLocalPlayer() end)
        if ok2 and isLocal then return end
        
        -- Only react to significant health drops
        local drop = (oldHp or 100) - (newHp or 100)
        if drop < 10 then return end
        
        -- Use BotCore event handler if available
        if useBotCore and BotCore and BotCore.FriendHealer then
            BotCore.FriendHealer.onFriendHealthChange(creature, newHp, oldHp)
        end
    end)
end