--[[
  Friend Healer UI & Integration
  
  Uses BotCore.FriendHealer for high-performance healing logic.
  This file handles UI and configuration only.
  
  Features:
    - Shares exhaustion with HealBot via BotCore.Cooldown
    - Priority-based: Self-healing ALWAYS takes precedence
    - Event-driven for instant response to health changes
    - Memoized target selection for performance
]]

setDefaultTab("Main")
local panelName = "newHealer"
local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: title
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('Friend Healer')

  Button
    id: edit
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
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
            {name="Exura Sio",              enabled=true,                            normal = true},
            {name="Exura Gran Mas Res",     enabled=true,                                          area = true},
            {name="Health Item",            enabled=true,                                                      health=true},
            {name="Mana Item",              enabled=true,                                                                  mana=true}
        },
        settings = {
            {type="HealItem",       text="Mana Item ",                   value=268},
            {type="HealScroll",     text="Item Range: ",                 value=6},
            {type="HealItem",       text="Health Item ",                 value=3160},
            {type="HealScroll",     text="Mas Res Players: ",            value=2},
            {type="HealScroll",     text="Heal Friend at: ",             value=80},
            {type="HealScroll",     text="Use Gran Sio at: ",            value=40},
            {type="HealScroll",     text="Min Player HP%: ",             value=80},
            {type="HealScroll",     text="Min Player MP%: ",             value=50},
        },
        conditions = {
            knights = true,
            paladins = true,
            druids = false,
            sorcerers = false,
            party = true,
            guild = false,
            botserver = false,
            friends = false
        }
    }
end

local config = storage[panelName]

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
      manaItem = config.settings[1] and config.settings[1].value or 268,
      itemRange = config.settings[2] and config.settings[2].value or 6,
      healthItem = config.settings[3] and config.settings[3].value or 3160,
      masResPlayers = config.settings[4] and config.settings[4].value or 2,
      healAt = config.settings[5] and config.settings[5].value or 80,
      granSioAt = config.settings[6] and config.settings[6].value or 40,
      minPlayerHp = config.settings[7] and config.settings[7].value or 80,
      minPlayerMp = config.settings[8] and config.settings[8].value or 50,
    },
    -- Priority actions (in order)
    useSio = false,
    useGranSio = false,
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
  if BotCore and BotCore.FriendHealer then
    local bcConfig = buildBotCoreConfig()
    BotCore.FriendHealer.init(bcConfig)
    BotCore.FriendHealer.setEnabled(config.enabled)
    return true
  end
  return false
end

-- Update BotCore when config changes (also syncs HealEngine spells)
local function updateBotCoreConfig()
  if BotCore and BotCore.FriendHealer then
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
-- create entries on the list
for name, health in pairs(config.customPlayers) do
    local widget = UI.createWidget("HealerPlayerEntry", customList.playerList.list)
    widget.remove.onClick = function()
        config.customPlayers[name] = nil
        widget:destroy()
        updateBotCoreConfig()
    end
    widget:setText("["..health.."%]  "..name)
end

customList.playerList.onDoubleClick = function()
    customList.playerList:hide()
end

local function clearFields()
    customList.addPanel.name:setText("friend name")
    customList.addPanel.health:setText("1")
    customList.playerList:show()
end

local function capitalFistLetter(str)
    return (string.gsub(str, "^%l", string.upper))
  end

customList.addPanel.add.onClick = function()
    local name = ""
    local words = string.split(customList.addPanel.name:getText(), " ")
    local health = tonumber(customList.addPanel.health:getText())
    for i, word in ipairs(words) do
      name = name .. " " .. capitalFistLetter(word)
    end

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
        local widget = UI.createWidget("HealerPlayerEntry", customList.playerList.list)
        widget.remove.onClick = function()
            config.customPlayers[name] = nil
            widget:destroy()
            updateBotCoreConfig()
        end
        widget:setText("["..health.."%]  "..name)
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
-- targetSettings
targetSettings.vocations.box.knights:setChecked(config.conditions.knights)
targetSettings.vocations.box.knights.onClick = function(widget)
    config.conditions.knights = not config.conditions.knights
    widget:setChecked(config.conditions.knights)
    validate(widget, 2)
    updateBotCoreConfig()
end

targetSettings.vocations.box.paladins:setChecked(config.conditions.paladins)
targetSettings.vocations.box.paladins.onClick = function(widget)
    config.conditions.paladins = not config.conditions.paladins
    widget:setChecked(config.conditions.paladins)
    validate(widget, 2)
    updateBotCoreConfig()
end

targetSettings.vocations.box.druids:setChecked(config.conditions.druids)
targetSettings.vocations.box.druids.onClick = function(widget)
    config.conditions.druids = not config.conditions.druids
    widget:setChecked(config.conditions.druids)
    validate(widget, 2)
    updateBotCoreConfig()
end

targetSettings.vocations.box.sorcerers:setChecked(config.conditions.sorcerers)
targetSettings.vocations.box.sorcerers.onClick = function(widget)
    config.conditions.sorcerers = not config.conditions.sorcerers
    widget:setChecked(config.conditions.sorcerers)
    validate(widget, 2)
    updateBotCoreConfig()
end

targetSettings.groups.box.friends:setChecked(config.conditions.friends)
targetSettings.groups.box.friends.onClick = function(widget)
    config.conditions.friends = not config.conditions.friends
    widget:setChecked(config.conditions.friends)
    validate(widget)
    updateBotCoreConfig()
end

targetSettings.groups.box.party:setChecked(config.conditions.party)
targetSettings.groups.box.party.onClick = function(widget)
    config.conditions.party = not config.conditions.party
    widget:setChecked(config.conditions.party)
    validate(widget)
    updateBotCoreConfig()
end

targetSettings.groups.box.guild:setChecked(config.conditions.guild)
targetSettings.groups.box.guild.onClick = function(widget)
    config.conditions.guild = not config.conditions.guild
    widget:setChecked(config.conditions.guild)
    validate(widget)
    updateBotCoreConfig()
end

targetSettings.groups.box.botserver:setChecked(config.conditions.botserver)
targetSettings.groups.box.botserver.onClick = function(widget)
    config.conditions.botserver = not config.conditions.botserver
    widget:setChecked(config.conditions.botserver)
    validate(widget)
    updateBotCoreConfig()
end

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
    for i, child in ipairs(priority.list:getChildren()) do
        if i == 1 then
            child.increment:disable()
        elseif i == 6 then
            child.decrement:disable()
        else
            child.increment:enable()
            child.decrement:enable()
        end
    end
end

for i, action in ipairs(config.priorities) do
    local widget = UI.createWidget("PriorityEntry", priority.list)

    widget:setText(action.name)
    widget.increment.onClick = function()
        local index = priority.list:getChildIndex(widget)
        local table = config.priorities

        priority.list:moveChildToIndex(widget, index-1)
        table[index], table[index-1] = table[index-1], table[index]
        setCrementalButtons()
    end
    widget.decrement.onClick = function()
        local index = priority.list:getChildIndex(widget)
        local table = config.priorities

        priority.list:moveChildToIndex(widget, index+1)
        table[index], table[index+1] = table[index+1], table[index]
        setCrementalButtons()
    end
    widget.enabled:setChecked(action.enabled)
    widget:setColor(action.enabled and "#98BF64" or "#dfdfdf")
    widget.enabled.onClick = function()
        action.enabled = not action.enabled
        widget:setColor(action.enabled and "#98BF64" or "#dfdfdf")
        widget.enabled:setChecked(action.enabled)
        validate(widget, 1)
        -- Sync config changes to BotCore
        updateBotCoreConfig()  
    end
    if action.custom then
        widget.onDoubleClick = function()
            local window = modules.client_textedit.show(widget, {title = "Custom Spell", description = "Enter below formula for a custom healing spell"})
            schedule(50, function() 
              window:raise()
              window:focus() 
            end)
        end
        widget.onTextChange = function(widget,text)
            action.name = text
        end
        widget:setTooltip("Double click to set spell formula.")
    end

    if i == #config.priorities then
        validate(widget, 1)
        setCrementalButtons()
    end
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
      local healAt = config.settings[5] and config.settings[5].value or 80
      local granSioAt = config.settings[6] and config.settings[6].value or 40
      
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
          if action.normal then
            table.insert(friendSpells, {
              name = "exura sio",
              hp = healAt,
              mpCost = 100,
              cd = 1100,
              prio = 2
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

    local masResAmount = config.settings[4].value
    local itemRange = config.settings[2].value
    local healItem = config.settings[3].value
    local manaItem = config.settings[1].value
    local normalHeal = config.customPlayers[name] or config.settings[5].value
    local strongHeal = config.customPlayers[name] and normalHeal/2 or config.settings[6].value

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

    local specText = spec:getText() or ""
    -- Check vocation filter
    if storage.extras and storage.extras.checkPlayer and specText:len() > 0 then
        if specText:find("EK") and not config.conditions.knights or
           specText:find("RP") and not config.conditions.paladins or
           specText:find("ED") and not config.conditions.druids or
           specText:find("MS") and not config.conditions.sorcerers then
           if not config.customPlayers[name] then
               return nil
           end
        end
    end

    local okParty = config.conditions.party and spec:isPartyMember()
    local okFriend = config.conditions.friends and isFriend and isFriend(spec)
    local okGuild = config.conditions.guild and spec:getEmblem() == 1
    local okBotServer = config.conditions.botserver and nExBot and nExBot.BotServerMembers and nExBot.BotServerMembers[name]

    if not (okParty or okFriend or okGuild or okBotServer) and not config.customPlayers[name] then
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

    local minHp = config.settings[7].value
    local minMp = config.settings[8].value

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