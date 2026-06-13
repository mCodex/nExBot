setDefaultTab("HP")
local panelName = "ConditionPanel"
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
    !text: tr('Conditions')

  NxButton
    id: conditionList
    anchors.top: parent.top
    anchors.right: parent.right
    width: 46
    height: 20
    text: Setup
      
  ]])
  ui:setId(panelName)

  if not HealBotConfig[panelName] then
    HealBotConfig[panelName] = {
      enabled = false,
      curePoison = false,
      poisonCost = 20,
      cureCurse = false,
      curseCost = 80,
      cureBleed = false,
      bleedCost = 45,
      cureBurn = false,
      burnCost = 30,
      cureElectrify = false,
      electrifyCost = 22,
      cureParalyse = false,
      paralyseCost = 40,
      paralyseSpell = "utani hur",
      holdHaste = false,
      hasteCost = 40,
      hasteSpell = "utani hur",
      holdUtamo = false,
      utamoCost = 40,
      holdUtana = false,
      utanaCost = 440,
      holdUtura = false,
      uturaType = "",
      uturaCost = 100,
      ignoreInPz = true,
      stopHaste = false
    }
  end

  local config = HealBotConfig[panelName]

  ui.title:setOn(config.enabled)
  ui.title.onClick = function(widget)
    config.enabled = not config.enabled
    widget:setOn(config.enabled)
    nExBotConfigSave("heal")
  end
  
  ui.conditionList.onClick = function(widget)
    conditionsWindow:show()
    conditionsWindow:raise()
    conditionsWindow:focus()
  end



  local rootWidget = g_ui.getRootWidget()
  if rootWidget then
    conditionsWindow = UI.createWindow('ConditionsWindow', rootWidget)
    conditionsWindow:hide()
    

    conditionsWindow.onVisibilityChange = function(widget, visible)
      if not visible then
        nExBotConfigSave("heal")
      end
    end

    -- text edits
    conditionsWindow.Cure.poison.cost:setText(config.poisonCost)
    conditionsWindow.Cure.poison.cost.onTextChange = function(widget, text)
      local v = tonumber(text)
      if v == nil then
        widget:setText(tostring(config.poisonCost))
      else
        config.poisonCost = v
      end
    end

    conditionsWindow.Cure.curse.cost:setText(config.curseCost)
    conditionsWindow.Cure.curse.cost.onTextChange = function(widget, text)
      local v = tonumber(text)
      if v == nil then
        widget:setText(tostring(config.curseCost))
      else
        config.curseCost = v
      end
    end

    conditionsWindow.Cure.bleed.cost:setText(config.bleedCost)
    conditionsWindow.Cure.bleed.cost.onTextChange = function(widget, text)
      local v = tonumber(text)
      if v == nil then
        widget:setText(tostring(config.bleedCost))
      else
        config.bleedCost = v
      end
    end

    conditionsWindow.Cure.burn.cost:setText(config.burnCost)
    conditionsWindow.Cure.burn.cost.onTextChange = function(widget, text)
      local v = tonumber(text)
      if v == nil then
        widget:setText(tostring(config.burnCost))
      else
        config.burnCost = v
      end
    end

    conditionsWindow.Cure.electrify.cost:setText(config.electrifyCost)
    conditionsWindow.Cure.electrify.cost.onTextChange = function(widget, text)
      local v = tonumber(text)
      if v == nil then
        widget:setText(tostring(config.electrifyCost))
      else
        config.electrifyCost = v
      end
    end

    conditionsWindow.Cure.paralyse.cost:setText(config.paralyseCost)
    conditionsWindow.Cure.paralyse.cost.onTextChange = function(widget, text)
      local v = tonumber(text)
      if v == nil then
        widget:setText(tostring(config.paralyseCost))
      else
        config.paralyseCost = v
      end
    end

    conditionsWindow.Cure.paralyseSpell.spell:setText(config.paralyseSpell)
    conditionsWindow.Cure.paralyseSpell.spell.onTextChange = function(widget, text)
      config.paralyseSpell = text
    end

    conditionsWindow.Hold.hasteSpell.spell:setText(config.hasteSpell)
    conditionsWindow.Hold.hasteSpell.spell.onTextChange = function(widget, text)
      config.hasteSpell = text
    end

    conditionsWindow.Hold.haste.cost:setText(config.hasteCost)
    conditionsWindow.Hold.haste.cost.onTextChange = function(widget, text)
      local v = tonumber(text)
      if v == nil then
        widget:setText(tostring(config.hasteCost))
      else
        config.hasteCost = v
      end
    end

    conditionsWindow.Hold.utamo.cost:setText(config.utamoCost)
    conditionsWindow.Hold.utamo.cost.onTextChange = function(widget, text)
      local v = tonumber(text)
      if v == nil then
        widget:setText(tostring(config.utamoCost))
      else
        config.utamoCost = v
      end
    end

    conditionsWindow.Hold.utana.cost:setText(config.utanaCost)
    conditionsWindow.Hold.utana.cost.onTextChange = function(widget, text)
      local v = tonumber(text)
      if v == nil then
        widget:setText(tostring(config.utanaCost))
      else
        config.utanaCost = v
      end
    end

    conditionsWindow.Hold.utura.cost:setText(config.uturaCost)
    conditionsWindow.Hold.utura.cost.onTextChange = function(widget, text)
      local v = tonumber(text)
      if v == nil then
        widget:setText(tostring(config.uturaCost))
      else
        config.uturaCost = v
      end
    end

    -- combo box
    conditionsWindow.Hold.UturaType:setOption(config.uturaType)
    conditionsWindow.Hold.UturaType.onOptionChange = function(widget)
      config.uturaType = widget:getCurrentOption().text
    end

    -- checkboxes
    conditionsWindow.Cure.poison.toggle:setChecked(config.curePoison)
    conditionsWindow.Cure.poison.toggle.onClick = function(widget)
      config.curePoison = not config.curePoison
      widget:setChecked(config.curePoison)
    end

    conditionsWindow.Cure.curse.toggle:setChecked(config.cureCurse)
    conditionsWindow.Cure.curse.toggle.onClick = function(widget)
      config.cureCurse = not config.cureCurse
      widget:setChecked(config.cureCurse)
    end

    conditionsWindow.Cure.bleed.toggle:setChecked(config.cureBleed)
    conditionsWindow.Cure.bleed.toggle.onClick = function(widget)
      config.cureBleed = not config.cureBleed
      widget:setChecked(config.cureBleed)
    end

    conditionsWindow.Cure.burn.toggle:setChecked(config.cureBurn)
    conditionsWindow.Cure.burn.toggle.onClick = function(widget)
      config.cureBurn = not config.cureBurn
      widget:setChecked(config.cureBurn)
    end

    conditionsWindow.Cure.electrify.toggle:setChecked(config.cureElectrify)
    conditionsWindow.Cure.electrify.toggle.onClick = function(widget)
      config.cureElectrify = not config.cureElectrify
      widget:setChecked(config.cureElectrify)
    end

    conditionsWindow.Cure.paralyse.toggle:setChecked(config.cureParalyse)
    conditionsWindow.Cure.paralyse.toggle.onClick = function(widget)
      config.cureParalyse = not config.cureParalyse
      widget:setChecked(config.cureParalyse)
    end

    conditionsWindow.Hold.haste.toggle:setChecked(config.holdHaste)
    conditionsWindow.Hold.haste.toggle.onClick = function(widget)
      config.holdHaste = not config.holdHaste
      widget:setChecked(config.holdHaste)
    end

    conditionsWindow.Hold.utamo.toggle:setChecked(config.holdUtamo)
    conditionsWindow.Hold.utamo.toggle.onClick = function(widget)
      config.holdUtamo = not config.holdUtamo
      widget:setChecked(config.holdUtamo)
    end

    conditionsWindow.Hold.utana.toggle:setChecked(config.holdUtana)
    conditionsWindow.Hold.utana.toggle.onClick = function(widget)
      config.holdUtana = not config.holdUtana
      widget:setChecked(config.holdUtana)
    end

    conditionsWindow.Hold.utura.toggle:setChecked(config.holdUtura)
    conditionsWindow.Hold.utura.toggle.onClick = function(widget)
      config.holdUtura = not config.holdUtura
      widget:setChecked(config.holdUtura)
    end

    conditionsWindow.Hold.IgnoreInPz:setChecked(config.ignoreInPz)
    conditionsWindow.Hold.IgnoreInPz.onClick = function(widget)
      config.ignoreInPz = not config.ignoreInPz
      widget:setChecked(config.ignoreInPz)
    end

    conditionsWindow.Hold.StopHaste:setChecked(config.stopHaste)
    conditionsWindow.Hold.StopHaste.onClick = function(widget)
      config.stopHaste = not config.stopHaste
      widget:setChecked(config.stopHaste)
    end

    -- buttons
    conditionsWindow.closeButton.onClick = function(widget)
      conditionsWindow:hide()
    end

    Conditions = {}
    Conditions.show = function()
      conditionsWindow:show()
      conditionsWindow:raise()
      conditionsWindow:focus()
    end
  end

  local utanaCast = nil

  local function actionLimiter()
    return BotCore and BotCore.ActionRateLimiter
  end

  local function castConditionSpell(spell, interval)
    local limiter = actionLimiter()
    if limiter and limiter.castSpell then
      return limiter.castSpell(spell, {
        interval = interval or 250,
        globalKey = "conditions:spell"
      })
    end
    say(spell)
    return true
  end

  local function healingGroupReady()
    if BotCore and BotCore.Cooldown and BotCore.Cooldown.isHealingOnCooldown then
      return not BotCore.Cooldown.isHealingOnCooldown()
    end
    if modules and modules.game_cooldown and modules.game_cooldown.isGroupCooldownIconActive then
      return not modules.game_cooldown.isGroupCooldownIconActive(2)
    end
    return true
  end

  -- Single condition spell handler. Cast at most one spell per tick to avoid
  -- cure/hold races sending multiple talk packets in the same frame.
  local nowMs = nExBot and nExBot.Shared and nExBot.Shared.nowMs or function() return now or (os.clock() * 1000) end
  local function conditionSpellsHandler()
    if not config.enabled then return end

    local canUseHold = not config.ignoreInPz or not isInPz()

    if healingGroupReady() and hppercent() > 95 then
      if config.curePoison and mana() >= config.poisonCost and isPoisioned() and castConditionSpell("exana pox") then return end
      if config.cureCurse and mana() >= config.curseCost and isCursed() and castConditionSpell("exana mort") then return end
      if config.cureBleed and mana() >= config.bleedCost and isBleeding() and castConditionSpell("exana kor") then return end
      if config.cureBurn and mana() >= config.burnCost and isBurning() and castConditionSpell("exana flam") then return end
      if config.cureElectrify and mana() >= config.electrifyCost and isEnergized() and castConditionSpell("exana vis") then return end
    end

    if canUseHold and config.holdUtura and mana() >= config.uturaCost and canCast(config.uturaType) and hppercent() < 90 and castConditionSpell(config.uturaType) then
      return
    end

    if canUseHold and config.holdUtana and mana() >= config.utanaCost and (not utanaCast or (nowMs() - utanaCast > 120000)) and castConditionSpell("utana vid") then
      utanaCast = nowMs()
      return
    end

    if canUseHold and config.holdUtamo and mana() >= config.utamoCost and not hasManaShield() and castConditionSpell("utamo vita") then
      return
    end

    if canUseHold and standTime() < 3000 and config.holdHaste and mana() >= config.hasteCost and not hasHaste() and not getSpellCoolDown(config.hasteSpell) and (not target() or not config.stopHaste or TargetBot.isCaveBotActionAllowed()) and castConditionSpell(config.hasteSpell) then
      return
    end

    if healingGroupReady() and config.cureParalyse and mana() >= config.paralyseCost and isParalyzed() and not getSpellCoolDown(config.paralyseSpell) then
      castConditionSpell(config.paralyseSpell)
    end
  end
  
  -- Use UnifiedTick if available (reduces macro overhead)
  if UnifiedTick and UnifiedTick.register then
    UnifiedTick.register("conditions_spells", {
      interval = 100,
      priority = UnifiedTick.Priority and UnifiedTick.Priority.HIGH or 75,
      handler = conditionSpellsHandler,
      group = "conditions"
    })
  else
    -- Fallback to traditional macros
    macro(100, conditionSpellsHandler)
  end