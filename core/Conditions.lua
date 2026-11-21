local panelName = "ConditionPanel"
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
      uturaCost = 100
    }
  end

  local config = HealBotConfig[panelName]
  -- Legacy typo migration: old profiles saved "curePosion" instead of "curePoison"
  if config.curePosion ~= nil and config.curePoison == nil then
    config.curePoison = config.curePosion
    config.curePosion = nil
  end

  Conditions = {
    config = config,
    isOn = function() return config.enabled == true end,
    setOn = function()
      config.enabled = true
      nExBotConfigSave("heal")
    end,
    setOff = function()
      config.enabled = false
      nExBotConfigSave("heal")
    end,
    toggle = function()
      config.enabled = not config.enabled
      nExBotConfigSave("heal")
      return config.enabled
    end,
    getRules = function()
      return {
        { id = "poison", name = "Cure poison", spell = "exana pox", enabled = config.curePoison, cost = config.poisonCost },
        { id = "curse", name = "Cure curse", spell = "exana mort", enabled = config.cureCurse, cost = config.curseCost },
        { id = "bleed", name = "Cure bleeding", spell = "exana kor", enabled = config.cureBleed, cost = config.bleedCost },
        { id = "burn", name = "Cure burning", spell = "exana flam", enabled = config.cureBurn, cost = config.burnCost },
        { id = "electrify", name = "Cure electrify", spell = "exana vis", enabled = config.cureElectrify, cost = config.electrifyCost },
        { id = "paralyse", name = "Cure paralysis", spell = config.paralyseSpell, enabled = config.cureParalyse, cost = config.paralyseCost },
        { id = "haste", name = "Movement haste", spell = config.hasteSpell, enabled = config.holdHaste, cost = config.hasteCost },
        { id = "shield", name = "Magic shield", spell = "utamo vita", enabled = config.holdUtamo, cost = config.utamoCost },
        { id = "invisible", name = "Invisibility", spell = "utana vid", enabled = config.holdUtana, cost = config.utanaCost },
        { id = "regeneration", name = "Regeneration", spell = config.uturaType, enabled = config.holdUtura, cost = config.uturaCost },
      }
    end,
    setRuleEnabled = function(id, enabled)
      local key = ({ poison = "curePoison", curse = "cureCurse", bleed = "cureBleed", burn = "cureBurn",
        electrify = "cureElectrify", paralyse = "cureParalyse", haste = "holdHaste", shield = "holdUtamo",
        invisible = "holdUtana", regeneration = "holdUtura" })[id]
      if not key then return false end
      config[key] = enabled == true
      nExBotConfigSave("heal")
      return true
    end,
    getCondition = function(key)
      return config[key] == true
    end,
    setCondition = function(key, enabled)
      if config[key] == nil then return false end
      config[key] = enabled == true
      nExBotConfigSave("heal")
      return true
    end,
    show = function() end,
  }

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
    if not isInPz() and config.holdUtura and mana() >= config.uturaCost and canCast(config.uturaType) and hppercent() < 90 then say(config.uturaType)
    elseif not isInPz() and config.holdUtana and mana() >= config.utanaCost and (not utanaCast or (now - utanaCast > 120000)) then say("utana vid") utanaCast = now
    end
  end
  
  -- Hold spells handler (50ms - high frequency for responsiveness)
  local function holdSpellsHandler()
    if not config.enabled then return end
    if not isInPz() and config.holdUtamo and mana() >= config.utamoCost and not hasManaShield() then say("utamo vita")
    elseif (not isInPz() and standTime() < 5000 and config.holdHaste and mana() >= config.hasteCost and not hasHaste() and not getSpellCoolDown(config.hasteSpell)) and standTime() < 3000 then say(config.hasteSpell)
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
