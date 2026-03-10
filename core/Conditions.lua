setDefaultTab("HP")
local panelName = "ConditionPanel"
local ui = setupUI([[
NxBotSection
  height: 28

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
    height: 28
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
      config.poisonCost = tonumber(text)
    end

    conditionsWindow.Cure.curse.cost:setText(config.curseCost)
    conditionsWindow.Cure.curse.cost.onTextChange = function(widget, text)
      config.curseCost = tonumber(text)
    end

    conditionsWindow.Cure.bleed.cost:setText(config.bleedCost)
    conditionsWindow.Cure.bleed.cost.onTextChange = function(widget, text)
      config.bleedCost = tonumber(text)
    end

    conditionsWindow.Cure.burn.cost:setText(config.burnCost)
    conditionsWindow.Cure.burn.cost.onTextChange = function(widget, text)
      config.burnCost = tonumber(text)
    end

    conditionsWindow.Cure.electrify.cost:setText(config.electrifyCost)
    conditionsWindow.Cure.electrify.cost.onTextChange = function(widget, text)
      config.electrifyCost = tonumber(text)
    end

    conditionsWindow.Cure.paralyse.cost:setText(config.paralyseCost)
    conditionsWindow.Cure.paralyse.cost.onTextChange = function(widget, text)
      config.paralyseCost = tonumber(text)
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
      config.hasteCost = tonumber(text)
    end

    conditionsWindow.Hold.utamo.cost:setText(config.utamoCost)
    conditionsWindow.Hold.utamo.cost.onTextChange = function(widget, text)
      config.utamoCost = tonumber(text)
    end

    conditionsWindow.Hold.utana.cost:setText(config.utanaCost)
    conditionsWindow.Hold.utana.cost.onTextChange = function(widget, text)
      config.utanaCost = tonumber(text)
    end

    conditionsWindow.Hold.utura.cost:setText(config.uturaCost)
    conditionsWindow.Hold.utura.cost.onTextChange = function(widget, text)
      config.uturaCost = tonumber(text)
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
  
  -- Cure conditions handler (500ms)
  local function cureConditionsHandler()
    if not config.enabled or modules.game_cooldown.isGroupCooldownIconActive(2) then return end
    if hppercent() > 95 then
      if config.curePoison and mana() >= config.poisonCost and isPoisioned() then say("exana pox") 
      elseif config.cureCurse and mana() >= config.curseCost and isCursed() then say("exana mort") 
      elseif config.cureBleed and mana() >= config.bleedCost and isBleeding() then say("exana kor")
      elseif config.cureBurn and mana() >= config.burnCost and isBurning() then say("exana flam") 
      elseif config.cureElectrify and mana() >= config.electrifyCost and isEnergized() then say("exana vis") 
      end
    end
    if (not config.ignoreInPz or not isInPz()) and config.holdUtura and mana() >= config.uturaCost and canCast(config.uturaType) and hppercent() < 90 then say(config.uturaType)
    elseif (not config.ignoreInPz or not isInPz()) and config.holdUtana and mana() >= config.utanaCost and (not utanaCast or (now - utanaCast > 120000)) then say("utana vid") utanaCast = now
    end
  end
  
  -- Hold spells handler (50ms - high frequency for responsiveness)
  local function holdSpellsHandler()
    if not config.enabled then return end
    if (not config.ignoreInPz or not isInPz()) and config.holdUtamo and mana() >= config.utamoCost and not hasManaShield() then say("utamo vita")
    elseif ((not config.ignoreInPz or not isInPz()) and standTime() < 5000 and config.holdHaste and mana() >= config.hasteCost and not hasHaste() and not getSpellCoolDown(config.hasteSpell) and (not target() or not config.stopHaste or TargetBot.isCaveBotActionAllowed())) and standTime() < 3000 then say(config.hasteSpell)
    elseif config.cureParalyse and mana() >= config.paralyseCost and isParalyzed() and not getSpellCoolDown(config.paralyseSpell) then say(config.paralyseSpell)
    end
  end
  
  -- Use UnifiedTick if available (reduces macro overhead)
  if UnifiedTick and UnifiedTick.register then
    UnifiedTick.register("conditions_cure", {
      interval = 500,
      priority = UnifiedTick.Priority and UnifiedTick.Priority.NORMAL or 50,
      handler = cureConditionsHandler,
      group = "conditions"
    })
    
    UnifiedTick.register("conditions_hold_spells", {
      interval = 50,
      priority = UnifiedTick.Priority and UnifiedTick.Priority.HIGH or 75,
      handler = holdSpellsHandler,
      group = "conditions"
    })
  else
    -- Fallback to traditional macros
    macro(500, cureConditionsHandler)
    macro(50, holdSpellsHandler)
  end