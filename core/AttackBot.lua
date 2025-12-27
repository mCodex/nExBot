local HealContext = dofile("/core/heal_context.lua")

-- Safe function calls to prevent "attempt to call global function (a nil value)" errors
local SafeCall = SafeCall or require("core.safe_call")

setDefaultTab("Main")
-- locales
local panelName = "AttackBot"
local currentSettings
local showSettings = false
local showItem = false
local category = 1
local patternCategory = 1
local pattern = 1
local mainWindow

-- ============================================================================
-- BOTCORE INTEGRATION
-- ============================================================================

-- Local analytics wrapper (for fallback if BotCore not available)
local attackAnalytics = storage.attackAnalytics or {
  spells = {},
  runes = {},
  empowerments = 0,
  totalAttacks = 0,
  log = {}
}
storage.attackAnalytics = attackAnalytics

-- Record an attack action (delegates to BotCore.Analytics if available)
local function recordAttackAction(cat, idOrFormula)
  -- Use BotCore.Analytics if available
  if BotCore and BotCore.Analytics then
    BotCore.Analytics.recordAttack(cat, idOrFormula)
    return
  end
  
  -- Fallback to local analytics
  attackAnalytics.totalAttacks = attackAnalytics.totalAttacks + 1
  
  if cat == 1 or cat == 4 or cat == 5 then
    local spellName = tostring(idOrFormula)
    attackAnalytics.spells[spellName] = (attackAnalytics.spells[spellName] or 0) + 1
    if cat == 4 then
      attackAnalytics.empowerments = attackAnalytics.empowerments + 1
    end
  elseif cat == 2 or cat == 3 then
    -- Use string key for runeId to prevent sparse array issues in JSON serialization
    local runeKey = tostring(tonumber(idOrFormula) or 0)
    attackAnalytics.runes[runeKey] = (attackAnalytics.runes[runeKey] or 0) + 1
  end
  
  local log = attackAnalytics.log
  if #log >= 50 then table.remove(log, 1) end
  table.insert(log, { t = now, cat = cat, action = tostring(idOrFormula) })
end

-- Public API for SmartHunt (redirects to BotCore.Analytics if available)
AttackBot = AttackBot or {}
AttackBot.getAnalytics = function()
  if BotCore and BotCore.Analytics then
    return BotCore.Analytics.AttackBot.getAnalytics()
  end
  return attackAnalytics
end
AttackBot.resetAnalytics = function()
  if BotCore and BotCore.Analytics then
    BotCore.Analytics.AttackBot.resetAnalytics()
    return
  end
  attackAnalytics.spells = {}
  attackAnalytics.runes = {}
  attackAnalytics.empowerments = 0
  attackAnalytics.totalAttacks = 0
  attackAnalytics.log = {}
end

-- label library

local categories = {
  "Targeted Spell (exori hur, exori flam, etc)",
  "Area Rune (avalanche, great fireball, etc)",
  "Targeted Rune (sudden death, icycle, etc)",
  "Empowerment (utito tempo, etc)",
  "Absolute Spell (exori, hells core, etc)",
}

local patterns = {
  -- targeted spells
  {
    "1 Sqm Range (exori ico)",
    "2 Sqm Range",
    "3 Sqm Range (strike spells)",
    "4 Sqm Range (exori san)",
    "5 Sqm Range (exori hur)",
    "6 Sqm Range",
    "7 Sqm Range (exori con)",
    "8 Sqm Range",
    "9 Sqm Range",
    "10 Sqm Range"
  },
  -- area runes
  {
    "Cross (explosion)",
    "Bomb (fire bomb)",
    "Ball (gfb, avalanche)"
  },
  -- empowerment/targeted rune
  {
    "1 Sqm Range",
    "2 Sqm Range",
    "3 Sqm Range",
    "4 Sqm Range",
    "5 Sqm Range",
    "6 Sqm Range",
    "7 Sqm Range",
    "8 Sqm Range",
    "9 Sqm Range",
    "10 Sqm Range",
  },
  -- absolute
  {
    "Adjacent (exori, exori gran)",
    "3x3 Wave (vis hur, tera hur)", 
    "Small Area (mas san, exori mas)",
    "Medium Area (mas flam, mas frigo)",
    "Large Area (mas vis, mas tera)",
    "Short Beam (vis lux)", 
    "Large Beam (gran vis lux)", 
    "Sweep (exori min)", -- 8
    "Small Wave (gran frigo hur)",
    "Big Wave (flam hur, frigo hur)",
    "Huge Wave (gran flam hur)",
  }
}

  -- spellPatterns[category][pattern][1 - normal, 2 - safe]
local spellPatterns = {
  {}, -- blank, wont be used
  -- Area Runes,
  { 
    {     -- cross
     [[ 
      010
      111
      010
     ]],
     -- cross SAFE
     [[
       01110
       01110
       11111
       11111
       11111
       01110
       01110
     ]]
    },
    { -- bomb
      [[
        111
        111
        111
      ]],
      -- bomb SAFE
      [[
        11111
        11111
        11111
        11111
        11111
      ]]
    },
    { -- ball
      [[
        0011100
        0111110
        1111111
        1111111
        1111111
        0111110
        0011100
      ]],
      -- ball SAFE
      [[
        000111000
        001111100
        011111110
        111111111
        111111111
        111111111
        011111110
        001111100
        000111000
      ]]
    },
  },
  {}, -- blank, wont be used
  -- Absolute
  {
    {-- adjacent
      [[
        111
        111
        111
      ]],
      -- adjacent SAFE
      [[
        11111
        11111
        11111
        11111
        11111
      ]]
    },
    { -- 3x3 Wave
      [[
        0000NNN0000
        0000NNN0000
        0000NNN0000
        00000N00000
        WWW00N00EEE
        WWWWW0EEEEE
        WWW00S00EEE
        00000S00000
        0000SSS0000
        0000SSS0000
        0000SSS0000
      ]],
      -- 3x3 Wave SAFE
      [[
        0000NNNNN0000
        0000NNNNN0000
        0000NNNNN0000
        0000NNNNN0000
        WWWW0NNN0EEEE
        WWWWWNNNEEEEE
        WWWWWW0EEEEEE
        WWWWWSSSEEEEE
        WWWW0SSS0EEEE
        0000SSSSS0000
        0000SSSSS0000
        0000SSSSS0000
        0000SSSSS0000
      ]]
    },
    { -- small area
      [[
        0011100
        0111110
        1111111
        1111111
        1111111
        0111110
        0011100
      ]],
      -- small area SAFE
      [[
        000111000
        001111100
        011111110
        111111111
        111111111
        111111111
        011111110
        001111100
        000111000
      ]]
    },
    { -- medium area
      [[
        00000100000
        00011111000
        00111111100
        01111111110
        01111111110
        11111111111
        01111111110
        01111111110
        00111111100
        00001110000
        00000100000
      ]],
      -- medium area SAFE
      [[
        0000011100000
        0000111110000
        0001111111000
        0011111111100
        0111111111110
        0111111111110
        1111111111111
        0111111111110
        0111111111110
        0011111111100
        0001111111000
        0000111110000
        0000011100000
      ]]
    },
    { -- large area
      [[
        0000001000000
        0000011100000
        0000111110000
        0001111111000
        0011111111100
        0111111111110
        1111111111111
        0111111111110
        0011111111100
        0001111111000
        0000111110000
        0000011100000
        0000001000000
      ]],
      -- large area SAFE
      [[
        000000010000000
        000000111000000
        000001111100000
        000011111110000
        000111111111000
        001111111111100
        011111111111110
        111111111111111
        011111111111110
        001111111111100
        000111111111000
        000011111110000
        000001111100000
        000000111000000
        000000010000000
      ]]
    },
    { -- short beam
      [[
        00000N00000
        00000N00000
        00000N00000
        00000N00000
        00000N00000
        WWWWW0EEEEE
        00000S00000
        00000S00000
        00000S00000
        00000S00000
        00000S00000
      ]],
      -- short beam SAFE
      [[
        00000NNN00000
        00000NNN00000
        00000NNN00000
        00000NNN00000
        00000NNN00000
        WWWWWNNNEEEEE
        WWWWWW0EEEEEE
        00000SSS00000
        00000SSS00000
        00000SSS00000
        00000SSS00000
        00000SSS00000
        00000SSS00000
      ]]
    },
    { -- large beam
      [[
        0000000N0000000
        0000000N0000000
        0000000N0000000
        0000000N0000000
        0000000N0000000
        0000000N0000000
        0000000N0000000
        WWWWWWW0EEEEEEE
        0000000S0000000
        0000000S0000000
        0000000S0000000
        0000000S0000000
        0000000S0000000
        0000000S0000000
        0000000S0000000
      ]],
      -- large beam SAFE
      [[
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        WWWWWWWNNNEEEEEEE
        WWWWWWWW0EEEEEEEE
        WWWWWWWSSSEEEEEEE
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
      ]],
    },
    {}, -- sweep, wont be used
    { -- small wave
      [[
        00NNN00
        00NNN00
        WW0N0EE
        WWW0EEE
        WW0S0EE
        00SSS00
        00SSS00
      ]],
      -- small wave SAFE
      [[
        00NNNNN00
        00NNNNN00
        WWNNNNNEE
        WWWWNEEEE
        WWWW0EEEE
        WWWWSEEEE
        WWSSSSSEE
        00SSSSS00
        00SSSSS00
      ]]
    },
    { -- large wave
      [[
        000NNNNN000
        000NNNNN000
        0000NNN0000
        WW00NNN00EE
        WWWW0N0EEEE
        WWWWW0EEEEE
        WWWW0S0EEEE
        WW00SSS00EE
        0000SSS0000
        000SSSSS000
        000SSSSS000
      ]],
      [[
        000NNNNNNN000
        000NNNNNNN000
        000NNNNNNN000
        WWWWNNNNNEEEE
        WWWWNNNNNEEEE
        WWWWWNNNEEEEE
        WWWWWW0EEEEEE
        WWWWWSSSEEEEE
        WWWWSSSSSEEEE
        WWWWSSSSSEEEE
        000SSSSSSS000
        000SSSSSSS000
        000SSSSSSS000
      ]]
    },
    { -- huge wave
      [[
        0000NNNNN0000
        0000NNNNN0000
        00000NNN00000
        00000NNN00000
        WW0000N0000EE
        WWWW00N00EEEE
        WWWWWW0EEEEEE
        WWWW00S00EEEE
        WW0000S0000EE
        00000SSS00000
        00000SSS00000
        0000SSSSS0000
        0000SSSSS0000
      ]],
      [[
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        0000000NNN0000000
        WWWWWWWNNNEEEEEEE
        WWWWWWWW0EEEEEEEE
        WWWWWWWSSSEEEEEEE
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
        0000000SSS0000000
      ]]
    }
  }
}

-- direction patterns
local ek = (voc() == 1 or voc() == 11) and true

local posN = ek and [[
  111
  000
  000
]] or [[
  00011111000
  00011111000
  00011111000
  00011111000
  00000100000
  00000000000
  00000000000
  00000000000
  00000000000
  00000000000
  00000000000
]]

local posE = ek and [[
  001
  001
  001
]] or   [[
  00000000000
  00000000000
  00000000000
  00000001111
  00000001111
  00000011111
  00000001111
  00000001111
  00000000000
  00000000000
  00000000000
]]
local posS = ek and [[
  000
  000
  111
]] or   [[
  00000000000
  00000000000
  00000000000
  00000000000
  00000000000
  00000000000
  00000100000
  00011111000
  00011111000
  00011111000
  00011111000
]]
local posW = ek and [[
  100
  100
  100
]] or   [[
  00000000000
  00000000000
  00000000000
  11110000000
  11110000000
  11111000000
  11110000000
  11110000000
  00000000000
  00000000000
  00000000000
]]

-- AttackBotConfig
-- create blank profiles 
if not AttackBotConfig[panelName] or not AttackBotConfig[panelName][1] or #AttackBotConfig[panelName] ~= 5 then
  AttackBotConfig[panelName] = {
    [1] = {
      enabled = true,  -- Enable by default so user doesn't have to manually toggle
      attackTable = {},
      ignoreMana = true,
      Kills = false,
      Rotate = false,
      name = "Profile #1",
      Cooldown = true,
      Visible = true,
      pvpMode = false,
      KillsAmount = 1,
      PvpSafe = true,
      BlackListSafe = false,
      AntiRsRange = 5
    },
    [2] = {
      enabled = false,
      attackTable = {},
      ignoreMana = true,
      Kills = false,
      Rotate = false,
      name = "Profile #2",
      Cooldown = true,
      Visible = true,
      pvpMode = false,
      KillsAmount = 1,
      PvpSafe = true,
      BlackListSafe = false,
      AntiRsRange = 5
    },
    [3] = {
      enabled = false,
      attackTable = {},
      ignoreMana = true,
      Kills = false,
      Rotate = false,
      name = "Profile #3",
      Cooldown = true,
      Visible = true,
      pvpMode = false,
      KillsAmount = 1,
      PvpSafe = true,
      BlackListSafe = false,
      AntiRsRange = 5
    },
    [4] = {
      enabled = false,
      attackTable = {},
      ignoreMana = true,
      Kills = false,
      Rotate = false,
      name = "Profile #4",
      Cooldown = true,
      Visible = true,
      pvpMode = false,
      KillsAmount = 1,
      PvpSafe = true,
      BlackListSafe = false,
      AntiRsRange = 5
    },
    [5] = {
      enabled = false,
      attackTable = {},
      ignoreMana = true,
      Kills = false,
      Rotate = false,
      name = "Profile #5",
      Cooldown = true,
      Visible = true,
      pvpMode = false,
      KillsAmount = 1,
      PvpSafe = true,
      BlackListSafe = false,
      AntiRsRange = 5
    },
  }
end

-- Load character-specific profile if available
local charProfile = getCharacterProfile("attackProfile")
if charProfile and charProfile >= 1 and charProfile <= 5 then
  AttackBotConfig.currentBotProfile = charProfile
elseif not AttackBotConfig.currentBotProfile or AttackBotConfig.currentBotProfile == 0 or AttackBotConfig.currentBotProfile > 5 then 
  AttackBotConfig.currentBotProfile = 1
end

-- create panel UI
ui = UI.createWidget("AttackBotBotPanel")
if not ui then
  warn("[AttackBot] Failed to create UI widget AttackBotBotPanel")
  return
end

-- finding correct table, manual unfortunately
local setActiveProfile = function()
  local n = AttackBotConfig.currentBotProfile
  currentSettings = AttackBotConfig[panelName][n]
  -- Save character's profile preference
  setCharacterProfile("attackProfile", n)
end
setActiveProfile()

-- Ensure currentSettings is initialized (fallback if profile is nil)
if not currentSettings then
  AttackBotConfig.currentBotProfile = 1
  setActiveProfile()
end

if not currentSettings.AntiRsRange then
  currentSettings.AntiRsRange = 5 
end

local setProfileName = function()
  if ui.name then
    ui.name:setText(currentSettings.name)
  end
end

-- small UI elements
if ui.title then
  ui.title.onClick = function(widget)
    currentSettings.enabled = not currentSettings.enabled
    widget:setOn(currentSettings.enabled)
    nExBotConfigSave("atk")
  end
end
  
if ui.settings then
  ui.settings.onClick = function(widget)
    mainWindow:show()
    mainWindow:raise()
    mainWindow:focus()
  end
end

  mainWindow = UI.createWindow("AttackBotWindow")
  if not mainWindow then
    warn("[AttackBot] Failed to create main window AttackBotWindow")
    return
  end
  mainWindow:hide()

  local panel = mainWindow.mainPanel
  local settingsUI = mainWindow.settingsPanel

  mainWindow.onVisibilityChange = function(widget, visible)
    if not visible then
      currentSettings.attackTable = {}
      for i, child in ipairs(panel.entryList:getChildren()) do
        table.insert(currentSettings.attackTable, child.params)
      end
      nExBotConfigSave("atk")
    end
  end

  -- main panel

    -- functions
    function toggleSettings()
      panel:setVisible(not showSettings)
      mainWindow.shooterLabel:setVisible(not showSettings)
      settingsUI:setVisible(showSettings)
      mainWindow.settingsLabel:setVisible(showSettings)
      mainWindow.settings:setText(showSettings and "Back" or "Settings")
    end
    toggleSettings()

    mainWindow.settings.onClick = function()
      showSettings = not showSettings
      toggleSettings()
    end

    function toggleItem()
      panel.monsters:setWidth(showItem and 405 or 341)
      panel.itemId:setVisible(showItem)
      panel.spellName:setVisible(not showItem)
    end
    toggleItem()

    function setCategoryText()
      panel.category.description:setText(categories[category])
    end
    setCategoryText()

    function setPatternText()
      panel.range.description:setText(patterns[patternCategory][pattern])
    end
    setPatternText()

    -- in/de/crementation buttons
    panel.previousCategory.onClick = function()
      if category == 1 then
        category = #categories
      else
        category = category - 1
      end

      showItem = (category == 2 or category == 3) and true or false
      patternCategory = category == 4 and 3 or category == 5 and 4 or category
      pattern = 1
      toggleItem()
      setPatternText()
      setCategoryText()
    end
    panel.nextCategory.onClick = function()
      if category == #categories then
        category = 1 
      else
        category = category + 1
      end

      showItem = (category == 2 or category == 3) and true or false
      patternCategory = category == 4 and 3 or category == 5 and 4 or category
      pattern = 1
      toggleItem()
      setPatternText()
      setCategoryText()
    end
    panel.previousSource.onClick = function()
      warn("[AttackBot] TODO, reserved for future use.")
    end
    panel.nextSource.onClick = function()
      warn("[AttackBot] TODO, reserved for future use.")
    end
    panel.previousRange.onClick = function()
      local t = patterns[patternCategory]
      if pattern == 1 then
        pattern = #t 
      else
        pattern = pattern - 1
      end
      setPatternText()
    end
    panel.nextRange.onClick = function()
      local t = patterns[patternCategory]
      if pattern == #t then
        pattern = 1 
      else
        pattern = pattern + 1
      end
      setPatternText()
    end
    -- eo in/de/crementation

  ------- [[core table function]] -------
    function setupWidget(widget)
      local params = widget.params

      widget:setText(params.description)
      if params.itemId > 0 then
        widget.spell:setVisible(false)
        widget.id:setVisible(true)
        widget.id:setItemId(params.itemId)
      end
      widget:setTooltip(params.tooltip)
      widget.remove.onClick = function()
        panel.up:setEnabled(false)
        panel.down:setEnabled(false)
        widget:destroy()
      end
      widget.enabled:setChecked(params.enabled)
      widget.enabled.onClick = function()
        params.enabled = not params.enabled
        widget.enabled:setChecked(params.enabled)
      end
      -- will serve as edit
      widget.onDoubleClick = function(widget)
        panel.manaPercent:setValue(params.mana)
        panel.creatures:setValue(params.count)
        panel.minHp:setValue(params.minHp)
        panel.maxHp:setValue(params.maxHp)
        panel.cooldown:setValue(params.cooldown)
        showItem = params.itemId > 100 and true or false
        panel.itemId:setItemId(params.itemId)
        panel.spellName:setText(params.spell or "")
        panel.orMore:setChecked(params.orMore)
        toggleItem()
        category = params.category
        patternCategory = params.patternCategory
        pattern = params.pattern
        setPatternText()
        setCategoryText()
        widget:destroy()
      end
      widget.onClick = function(widget)
        if #panel.entryList:getChildren() == 1 then
          panel.up:setEnabled(false)
          panel.down:setEnabled(false)
        elseif panel.entryList:getChildIndex(widget) == 1 then
          panel.up:setEnabled(false)
          panel.down:setEnabled(true)
        elseif panel.entryList:getChildIndex(widget) == panel.entryList:getChildCount() then
          panel.up:setEnabled(true)
          panel.down:setEnabled(false)
        else
          panel.up:setEnabled(true)
          panel.down:setEnabled(true)
        end
      end
    end


    -- refreshing values
    function refreshAttacks()
      if not currentSettings.attackTable then return end

      panel.entryList:destroyChildren()
      for i, entry in pairs(currentSettings.attackTable) do
        local label = UI.createWidget("AttackEntry", panel.entryList)
        label.params = entry
        setupWidget(label)
      end
    end
    refreshAttacks()
    panel.up:setEnabled(false)
    panel.down:setEnabled(false)

    -- adding values
    panel.addEntry.onClick = function(wdiget)
      -- first variables
      local creatures = panel.monsters:getText():lower()
      local monsters = (creatures:len() == 0 or creatures == "*" or creatures == "monster names") and true or string.split(creatures, ",")
      local mana = panel.manaPercent:getValue()
      local count = panel.creatures:getValue()
      local minHp = panel.minHp:getValue()
      local maxHp = panel.maxHp:getValue()
      local cooldown = panel.cooldown:getValue()
      local itemId = panel.itemId:getItemId()
      local spell = panel.spellName:getText()
      local tooltip = monsters ~= true and creatures
      local orMore = panel.orMore:isChecked()

      -- validation
      if showItem and itemId < 100 then
        return warn("[AttackBot]: please fill item ID!")
      elseif not showItem and (spell:lower() == "spell name" or spell:len() == 0) then
        return warn("[AttackBot]: please fill spell name!")
      end

      local regex = patternCategory ~= 1 and [[^[^\(]+]] or [[^[^R]+]]
      local matchResult = SafeCall.regexMatch(patterns[patternCategory][pattern], regex)
      local type = matchResult and matchResult[1] and matchResult[1][1]:trim() or ""
      regex = [[^[^ ]+]]
      local categoryMatch = SafeCall.regexMatch(categories[category], regex)
      local categoryName = categoryMatch and categoryMatch[1] and categoryMatch[1][1]:trim():lower() or ""
      local specificMonsters = monsters == true and "Any Creatures" or "Creatures"
      local attackType = showItem and "rune "..itemId or spell

      local countDescription = orMore and count.."+" or count

      local params = {
        creatures = creatures,
        monsters = monsters,
        mana = mana,
        count = count,
        minHp = minHp,
        maxHp = maxHp,
        cooldown = cooldown,
        itemId = itemId,
        spell = spell,
        enabled = true,
        category = category,
        patternCategory = patternCategory,
        pattern = pattern,
        tooltip = tooltip,
        orMore = orMore,
        description = '['..type..'] '..countDescription.. ' '..specificMonsters..': '..attackType..', '..categoryName..' ('..minHp..'%-'..maxHp..'%)'
      }

      local label = UI.createWidget("AttackEntry", panel.entryList)
      label.params = params
      setupWidget(label)
      resetFields()
    end

    -- moving values
    -- up
    panel.up.onClick = function(widget)
      local focused = panel.entryList:getFocusedChild()
      local n = panel.entryList:getChildIndex(focused)

      if n-1 == 1 then
        widget:setEnabled(false)
      end
      panel.down:setEnabled(true)
      panel.entryList:moveChildToIndex(focused, n-1)
      panel.entryList:ensureChildVisible(focused)
    end
    -- down
    panel.down.onClick = function(widget)
      local focused = panel.entryList:getFocusedChild()
      local n = panel.entryList:getChildIndex(focused)

      if n + 1 == panel.entryList:getChildCount() then
        widget:setEnabled(false)
      end
      panel.up:setEnabled(true)
      panel.entryList:moveChildToIndex(focused, n+1)
      panel.entryList:ensureChildVisible(focused)
    end

  -- [[settings panel]] --
  settingsUI.profileName.onTextChange = function(widget, text)
    currentSettings.name = text
    setProfileName()
  end
  settingsUI.IgnoreMana.onClick = function(widget)
    currentSettings.ignoreMana = not currentSettings.ignoreMana
    settingsUI.IgnoreMana:setChecked(currentSettings.ignoreMana)
  end
  settingsUI.Rotate.onClick = function(widget)
    currentSettings.Rotate = not currentSettings.Rotate
    settingsUI.Rotate:setChecked(currentSettings.Rotate)
  end
  settingsUI.Kills.onClick = function(widget)
    currentSettings.Kills = not currentSettings.Kills
    settingsUI.Kills:setChecked(currentSettings.Kills)
  end
  settingsUI.Cooldown.onClick = function(widget)
    currentSettings.Cooldown = not currentSettings.Cooldown
    settingsUI.Cooldown:setChecked(currentSettings.Cooldown)
  end
  settingsUI.Visible.onClick = function(widget)
    currentSettings.Visible = not currentSettings.Visible
    settingsUI.Visible:setChecked(currentSettings.Visible)
  end
  settingsUI.PvpMode.onClick = function(widget)
    currentSettings.pvpMode = not currentSettings.pvpMode
    settingsUI.PvpMode:setChecked(currentSettings.pvpMode)
  end
  settingsUI.PvpSafe.onClick = function(widget)
    currentSettings.PvpSafe = not currentSettings.PvpSafe
    settingsUI.PvpSafe:setChecked(currentSettings.PvpSafe)
  end
  settingsUI.Training.onClick = function(widget)
    currentSettings.Training = not currentSettings.Training
    settingsUI.Training:setChecked(currentSettings.Training)
  end
  settingsUI.BlackListSafe.onClick = function(widget)
    currentSettings.BlackListSafe = not currentSettings.BlackListSafe
    settingsUI.BlackListSafe:setChecked(currentSettings.BlackListSafe)
  end
  settingsUI.KillsAmount.onValueChange = function(widget, value)
    currentSettings.KillsAmount = value
  end
  settingsUI.AntiRsRange.onValueChange = function(widget, value)
    currentSettings.AntiRsRange = value
  end


   -- window elements
  mainWindow.closeButton.onClick = function()
    showSettings = false
    toggleSettings()
    resetFields()
    mainWindow:hide()
  end

  -- core functions
  function resetFields()
    showItem = false
    toggleItem()
    pattern = 1
    patternCategory = 1
    category = 1
    setPatternText()
    setCategoryText()
    panel.manaPercent:setText(1)
    panel.creatures:setText(1)
    panel.minHp:setValue(0)
    panel.maxHp:setValue(100)
    panel.cooldown:setText(1)
    panel.monsters:setText("monster names")
    panel.itemId:setItemId(0)
    panel.spellName:setText("spell name")
    panel.orMore:setChecked(false)
  end
  resetFields()

  function loadSettings()
    -- BOT panel
    ui.title:setOn(currentSettings.enabled)
    setProfileName()
    -- main panel
    refreshAttacks()
    -- settings
    settingsUI.profileName:setText(currentSettings.name)
    settingsUI.Visible:setChecked(currentSettings.Visible)
    settingsUI.Cooldown:setChecked(currentSettings.Cooldown)
    settingsUI.PvpMode:setChecked(currentSettings.pvpMode)
    settingsUI.PvpSafe:setChecked(currentSettings.PvpSafe)
    settingsUI.BlackListSafe:setChecked(currentSettings.BlackListSafe)
    settingsUI.AntiRsRange:setValue(currentSettings.AntiRsRange)
    settingsUI.IgnoreMana:setChecked(currentSettings.ignoreMana)
    settingsUI.Rotate:setChecked(currentSettings.Rotate)
    settingsUI.Kills:setChecked(currentSettings.Kills)
    settingsUI.KillsAmount:setValue(currentSettings.KillsAmount)
    settingsUI.Training:setChecked(currentSettings.Training)
  end
  loadSettings()

  local activeProfileColor = function()
    for i=1,5 do
      if i == AttackBotConfig.currentBotProfile then
        ui[i]:setColor("green")
      else
        ui[i]:setColor("white")
      end
    end
  end
  activeProfileColor()

  local profileChange = function()
    setActiveProfile()
    activeProfileColor()
    loadSettings()
    resetFields()
    nExBotConfigSave("atk")
  end

  for i=1,5 do
    local button = ui[i]
      button.onClick = function()
      AttackBotConfig.currentBotProfile = i
      profileChange()
    end
  end

    -- public functions (preserve existing analytics API)
    AttackBot = AttackBot or {}
  
    AttackBot.isOn = function()
      return currentSettings.enabled
    end
    
    AttackBot.isOff = function()
      return not currentSettings.enabled
    end
    
    AttackBot.setOff = function()
      currentSettings.enabled = false
      ui.title:setOn(currentSettings.enabled)
      nExBotConfigSave("atk")
    end
    
    AttackBot.setOn = function()
      currentSettings.enabled = true
      ui.title:setOn(currentSettings.enabled)
      nExBotConfigSave("atk")
    end
    
    AttackBot.getActiveProfile = function()
      return AttackBotConfig.currentBotProfile -- returns number 1-5
    end
  
    AttackBot.setActiveProfile = function(n)
      if not n or not tonumber(n) or n < 1 or n > 5 then
        return error("[AttackBot] wrong profile parameter! should be 1 to 5 is " .. n)
      else
        AttackBotConfig.currentBotProfile = n
        profileChange()
      end
    end

    AttackBot.show = function()
      mainWindow:show()
      mainWindow:raise()
      mainWindow:focus()
    end

-- ============================================================================
-- COOLDOWN MANAGEMENT
-- ============================================================================

local cooldowns = {}

local function nowMs()
  if now then return now end
  if g_clock and g_clock.millis then return g_clock.millis() end
  return os.time() * 1000
end

-- Check individual action cooldown
local function ready(key, cd)
  if not key then return true end
  local last = cooldowns[key] or 0
  return (nowMs() - last) >= (cd or 1000)
end

-- Mark action as used
local function stamp(key)
  if key then
    cooldowns[key] = nowMs()
  end
end

-- otui covered, now support functions
function getPattern(category, pattern, safe)
  safe = safe and 2 or 1

  return spellPatterns[category][pattern][safe]
end


function getMonstersInArea(category, posOrCreature, pattern, minHp, maxHp, safePattern, monsterNamesTable)
  -- monsterNamesTable can be nil
  local monsters = 0
  local t = {}
  if monsterNamesTable == true or not monsterNamesTable then
    t = {}
  else
    t = monsterNamesTable
  end

  if safePattern then
    for i, spec in pairs(getSpectators(posOrCreature, safePattern)) do
      if spec ~= player and (spec:isPlayer() and not spec:isPartyMember()) then
        return 0
      end
    end
  end 

  if category == 1 or category == 3 or category == 4 then
    -- Anchor to provided creature/position or fallback to current target
    local anchorTarget = posOrCreature or SafeCall.getTarget()
    local anchorName = anchorTarget and (type(anchorTarget) == "table" and nil or (anchorTarget.getName and anchorTarget:getName())) or nil
    if category == 1 or category == 3 then
      if #t ~= 0 and anchorName and not table.find(t, anchorName, true) then
        return 0
      end
    end

    -- Use spectators relative to anchor when possible
    local spectators = nil
    if posOrCreature and pattern and type(pattern) == "number" then
      spectators = getSpectators(posOrCreature, pattern) or {}
    else
      spectators = SafeCall.global("getSpectators") or {}
    end
    local counted = 0

    for i, spec in pairs(spectators) do
      if spec ~= player then
        local specHp = spec:getHealthPercent()
        local name = spec:getName():lower()
        local withinRadius = true
        local dist = nil
        if posOrCreature and pattern and type(pattern) == "number" then
          local ok, aPos = pcall(function()
            if type(posOrCreature) == "table" then return posOrCreature end
            if posOrCreature.getPosition then return posOrCreature:getPosition() end
            return nil
          end)
          if ok and aPos then
            local sPos = spec:getPosition()
            local dx = math.abs(sPos.x - aPos.x)
            local dy = math.abs(sPos.y - aPos.y)
            local dz = math.abs((sPos.z or 0) - (aPos.z or 0))
            dist = math.max(dx, dy, dz)
            withinRadius = dist <= pattern
          else
            withinRadius = false
          end
        end
        local isMonster = spec:isMonster() and withinRadius and specHp >= minHp and specHp <= maxHp and (#t == 0 or table.find(t, name, true)) and
                   (g_game.getClientVersion() < 960 or spec:getType() < 3)
        if isMonster then
          monsters = monsters + 1
          counted = counted + 1
        end

      end
    end

    return monsters
  end

  for i, spec in pairs(getSpectators(posOrCreature, pattern)) do
      if spec ~= player then
        local specHp = spec:getHealthPercent()
        local name = spec:getName():lower()
        monsters = spec:isMonster() and specHp >= minHp and specHp <= maxHp and (#t == 0 or table.find(t, name)) and
                   (g_game.getClientVersion() < 960 or spec:getType() < 3) and monsters + 1 or monsters
      end
  end

  return monsters
end

-- for area runes only
-- should return valid targets number (int) and position
function getBestTileByPattern(pattern, minHp, maxHp, safePattern, monsterNamesTable)
  local tiles = g_map.getTiles(posz())
  local targetTile = {amount=0,pos=false}

  for i, tile in pairs(tiles) do
    local tPos = tile:getPosition()
    local distance = distanceFromPlayer(tPos)
    if tile:canShoot() and tile:isWalkable() and distance < 4 then
      local amount = getMonstersInArea(2, tPos, pattern, minHp, maxHp, safePattern, monsterNamesTable)
      if amount > targetTile.amount then
        targetTile = {amount=amount,pos=tPos}
      end
    end
  end

  return targetTile.amount > 0 and targetTile or false
end

-- Use rune on target - works even with closed backpack (hotkey-style)
-- Uses BotCore.Items for consolidated item usage
local function useRuneOnTarget(runeId, targetCreatureOrTile)
  lastAttackTime = now -- Update attack time for non-blocking cooldown
  -- debug logs removed
  
  -- Simplified like vBot for better OTCv8 compatibility
  if useWith and targetCreatureOrTile then
    local ok, res = pcall(useWith, runeId, targetCreatureOrTile)
    if ok then return true end
  end
  
  -- Fallback methods
  if BotCore and BotCore.Items and BotCore.Items.useOn then
    local ok, res = pcall(BotCore.Items.useOn, runeId, targetCreatureOrTile)
    if ok and res then return true end
  end
  
  if g_game.useInventoryItemWith then
    local ok, res = pcall(g_game.useInventoryItemWith, runeId, targetCreatureOrTile)
    if ok then return true end
  end
  
  local rune = SafeCall.findItem(runeId)
  if rune then
    local ok, res = pcall(g_game.useWith, rune, targetCreatureOrTile)
    if ok then return true end
  end
  
  return false
end

function executeAttackBotAction(categoryOrPos, idOrFormula, cooldown)
  cooldown = cooldown or 0
  lastAttackTime = now -- Update attack time for non-blocking cooldown
  
  -- Mark action as used for cooldown tracking
  stamp(tostring(idOrFormula))
  
  -- Record analytics before executing
  recordAttackAction(categoryOrPos, idOrFormula)
  
  if categoryOrPos == 4 or categoryOrPos == 5 or categoryOrPos == 1 then
    cast(idOrFormula, cooldown)
  elseif categoryOrPos == 3 then 
    useRuneOnTarget(idOrFormula, SafeCall.target())
  end
end

-- support function covered, now the main loop
-- State for non-blocking delay
local lastAttackTime = 0
local ATTACK_COOLDOWN = 100

-- Pre-allocated direction data (avoid table creation per tick)
local directionCounts = {0, 0, 0, 0}  -- N, E, S, W
local DIR_NORTH, DIR_EAST, DIR_SOUTH, DIR_WEST = 0, 1, 2, 3

-- Cache client version check (doesn't change at runtime)
local isOldClient = g_game.getClientVersion() < 960

-- Cache for attack table children (invalidated when entries change)
local cachedAttackEntries = nil
local cachedEntriesCount = 0
local lastEntryCacheTime = 0
local ENTRY_CACHE_TTL = 300  -- Refresh every 300ms for fresher lists

-- Monster count cache to avoid recounting for similar patterns
local monsterCountCache = { ts = 0, values = {} }
local MONSTER_CACHE_TTL = 80  -- Slightly tighter TTL for responsiveness

local function resetMonsterCache()
  monsterCountCache.ts = now
  monsterCountCache.values = {}
end

local function getMonsterCountCached(category, posOrCreature, pattern, minHp, maxHp, safePattern, monsters)
  if now - (monsterCountCache.ts or 0) > MONSTER_CACHE_TTL then
    resetMonsterCache()
  end

  local key = category .. "_" .. minHp .. "_" .. maxHp .. "_" .. tostring(pattern)
  local cached = monsterCountCache.values[key]
  if cached ~= nil then
    return cached
  end

  local count = getMonstersInArea(category, posOrCreature, pattern, minHp, maxHp, safePattern, monsters)
  monsterCountCache.values[key] = count
  return count
end

local attackMacro = macro(100, function()
  attackBotMain()
end)

-- ============================================================================
-- SIMPLIFIED ATTACKBOT - HIGH PERFORMANCE & ACCURACY
-- ============================================================================

-- Per-tick cache for expensive computations
local lastAutoRotate = 0
local rotationCooldown = 500 -- ms
local ATTACK_DEBUG = false -- set to true to enable debug logs

local function newAttackCache()
  return {
    monstersInArea = {}, -- key -> number
    bestTileByPattern = {}, -- key -> {amount=, pos=}
    now = now
  }
end

local function cacheKeyForArea(category, posOrCreature, pattern, minHp, maxHp, safePattern, monsterNamesTable)
  -- Create a stable key for caching getMonstersInArea
  local p = posOrCreature and (type(posOrCreature) == "table" and (posOrCreature.x..":"..posOrCreature.y..":"..posOrCreature.z) or tostring(posOrCreature)) or "nil"
  local namesKey = monsterNamesTable == true and "any" or (monsterNamesTable and table.concat(monsterNamesTable, ",") or "")
  return table.concat({tostring(category), p, tostring(pattern or "nil"), tostring(minHp), tostring(maxHp), tostring(safePattern), namesKey}, "|")
end

local function cacheKeyForPattern(pattern)
  return tostring(pattern)
end

-- Pure evaluator using caching and vBot semantics
local function evaluateEntry(entry, context, cache)
  if not entry.enabled then return false end

  -- Mana check
  if context.mana < entry.mana then return false end

  -- Cooldown check
  if not ready(entry.key or tostring(entry.itemId or entry.spell), entry.cooldown or 1000) then return false end

  -- Target checks
  if not context.target then return false end
  local targetHp = context.target:getHealthPercent()
  local targetDist = distanceFromPlayer(context.target:getPosition())

  -- Safety checks (early exit)
  if context.settings.BlackListSafe and isBlackListedPlayerInRange(context.settings.AntiRsRange) then return false end
  if context.settings.Kills and killsToRs() <= context.settings.KillsAmount then return false end

  -- PVP mode: disallow area runes in pvp situations
  if context.settings.pvpMode and entry.category == 2 and targetHp >= entry.minHp and targetHp <= entry.maxHp and context.target:canShoot() then
    return false
  end

  -- HP condition for attack entries
  if targetHp < entry.minHp or targetHp > entry.maxHp then return false end

  -- Category-specific checks
  if entry.category == 2 then
    -- Area rune: use pattern-based search
    local pat = getPattern(entry.patternCategory, entry.pattern, context.settings.PvpSafe)
    local pKey = cacheKeyForPattern(entry.patternCategory..":"..entry.pattern..":"..tostring(context.settings.PvpSafe))
    local data = cache.bestTileByPattern[pKey]
    if not data then
      data = getBestTileByPattern(pat, entry.minHp, entry.maxHp, context.settings.PvpSafe, entry.monsters)
      cache.bestTileByPattern[pKey] = data
    end
    local monsterAmount = data and data.amount or 0

    if entry.orMore then return monsterAmount >= entry.count else return monsterAmount == entry.count end
  end

  -- For targeted/empowerment/absolute entries
  if entry.category == 1 or entry.category == 3 or entry.category == 4 or entry.category == 5 then
    -- Special-case: Absolute category
    if entry.category == 5 then
      -- For sweep (pattern == 8), we already handle directional counts above
      if entry.pattern == 8 then
        local cacheKeyN = "dirN:"..entry.minHp..":"..entry.maxHp
        local cacheKeyE = "dirE:"..entry.minHp..":"..entry.maxHp
        local cacheKeyS = "dirS:"..entry.minHp..":"..entry.maxHp
        local cacheKeyW = "dirW:"..entry.minHp..":"..entry.maxHp

        local monstersN = cache.monstersInArea[cacheKeyN]
        local monstersE = cache.monstersInArea[cacheKeyE]
        local monstersS = cache.monstersInArea[cacheKeyS]
        local monstersW = cache.monstersInArea[cacheKeyW]

        if monstersN == nil then
          monstersN = getMonstersInArea(2, pos(), posN, entry.minHp, entry.maxHp, false, entry.monsters)
          cache.monstersInArea[cacheKeyN] = monstersN
        end
        if monstersE == nil then
          monstersE = getMonstersInArea(2, pos(), posE, entry.minHp, entry.maxHp, false, entry.monsters)
          cache.monstersInArea[cacheKeyE] = monstersE
        end
        if monstersS == nil then
          monstersS = getMonstersInArea(2, pos(), posS, entry.minHp, entry.maxHp, false, entry.monsters)
          cache.monstersInArea[cacheKeyS] = monstersS
        end
        if monstersW == nil then
          monstersW = getMonstersInArea(2, pos(), posW, entry.minHp, entry.maxHp, false, entry.monsters)
          cache.monstersInArea[cacheKeyW] = monstersW
        end

        local bestSide = math.max(monstersN, monstersE, monstersS, monstersW)
        local bestDir = nil
        if bestSide == monstersN then bestDir = 0
        elseif bestSide == monstersE then bestDir = 1
        elseif bestSide == monstersS then bestDir = 2
        elseif bestSide == monstersW then bestDir = 3
        end
        -- require no players nearby if PvP safe is enabled
        local players = SafeCall.getPlayers and SafeCall.getPlayers(2) or {}
        local playersNearby = (#players > 0)
        if bestSide >= entry.count and (not context.settings.PvpSafe or not playersNearby) then
          -- store best sweep direction for executeAttack to use (rotation)
          cache.bestSweepDir = bestDir
          cache.bestSweepSide = bestSide
          -- reset rotation attempts when best direction changes
          cache.rotationAttemptsDir = bestDir
          cache.rotationAttempts = 0
          cache.rotationAttemptsStart = now
          return true
        else
          return false
        end
      end

      -- For other absolute patterns, follow vBot behavior and use pattern shapes
      local pCat = entry.patternCategory
      local pattern = entry.pattern
      local anchorParam = (pattern == 2 or pattern == 6 or pattern == 7 or pattern > 9) and player or pos()
      local safe = context.settings.PvpSafe and spellPatterns[pCat][entry.pattern][2] or false
      local patternShape = spellPatterns[pCat][entry.pattern][1]
      local cacheKey = cacheKeyForArea(entry.category, anchorParam, patternShape, entry.minHp, entry.maxHp, safe, entry.monsters)
      local monsterAmount = cache.monstersInArea[cacheKey]
      if monsterAmount == nil then
        monsterAmount = getMonstersInArea(entry.category, anchorParam, patternShape, entry.minHp, entry.maxHp, safe, entry.monsters)
        cache.monstersInArea[cacheKey] = monsterAmount
      end

      if entry.orMore then return monsterAmount >= entry.count else return monsterAmount == entry.count end
    end

    -- Fallback for targeted/empowerment entries
    -- Anchor targeted/emp entries to the current target and respect numeric pattern as a radius
    local posArg = (entry.category == 1 or entry.category == 3) and context.target or nil
    local patternArg = (entry.category == 1 or entry.category == 3) and entry.pattern or nil
    local key = cacheKeyForArea(entry.category, posArg, patternArg, entry.minHp, entry.maxHp, false, entry.monsters)
    local monsterAmount = cache.monstersInArea[key]
    if monsterAmount == nil then
      monsterAmount = getMonstersInArea(entry.category, posArg, patternArg, entry.minHp, entry.maxHp, false, entry.monsters)
      cache.monstersInArea[key] = monsterAmount
    end

    -- For targeted categories, also ensure target is within configured range
    if entry.category == 1 or entry.category == 3 then
      if targetDist > entry.pattern then return false end
    end
    if entry.orMore then return monsterAmount >= entry.count else return monsterAmount == entry.count end
  end

  return true
end

-- Replace previous shouldExecuteEntry reference with evaluateEntry where used
local function shouldExecuteEntry(entry, context)
  local cache = context._attackCache or newAttackCache()
  context._attackCache = cache
  return evaluateEntry(entry, context, cache)
end

-- Pure function: Execute attack action
local function executeAttack(entry, context)
  -- Mark action as used for cooldown tracking
  stamp(entry.key or tostring(entry.itemId or entry.spell))
  
  recordAttackAction(entry.category, entry.itemId > 100 and entry.itemId or entry.spell)
  
  if entry.category == 1 or entry.category == 4 or entry.category == 5 then
    -- For Absolute Sweep (category 5, pattern 8) respect rotation setting
    if entry.category == 5 and entry.pattern == 8 and context and context._attackCache and context._attackCache.bestSweepDir and context.settings and context.settings.Rotate then
      local desired = context._attackCache.bestSweepDir
      if player:getDirection() ~= desired then
        -- Prevent rapid oscillation by enforcing a small cooldown
        if now - lastAutoRotate < rotationCooldown then
          return -- defer, don't rotate yet
        end

        -- Rotation attempt window and throttling (avoid starvation)
        local cache = context._attackCache
        if cache then
          if cache.rotationAttemptsDir ~= desired then
            cache.rotationAttemptsDir = desired
            cache.rotationAttempts = 0
            cache.rotationAttemptsStart = now
          else
            if cache.rotationAttemptsStart and now - cache.rotationAttemptsStart > 3000 then
              cache.rotationAttempts = 0
              cache.rotationAttemptsStart = now
            end
          end

          local MAX_ROTATE_ATTEMPTS = 3
          if (cache.rotationAttempts or 0) >= MAX_ROTATE_ATTEMPTS then
            -- allow attack to proceed without rotating
          else
            -- Rotate towards best side and defer attack to next tick
            turn(desired)
            lastAutoRotate = now
            cache.rotationAttempts = (cache.rotationAttempts or 0) + 1
            return
          end
        else
          -- No cache available: rotate normally
          turn(desired)
          lastAutoRotate = now
          return
        end
      end
    end
    -- Spells
    cast(entry.spell, entry.cooldown)
    if context and context._attackCache then context._attackCache.rotationAttempts = 0 end
  elseif entry.category == 3 then
    -- Targeted runes
    local okTargeted = useRuneOnTarget(entry.itemId, context.target)
    if okTargeted and context and context._attackCache then context._attackCache.rotationAttempts = 0 end
  elseif entry.category == 2 then
    -- Area runes - prefer cached best tile when available
    local pat = spellPatterns[entry.patternCategory][entry.pattern][context.settings.PvpSafe and 2 or 1]
    local pKey = cacheKeyForPattern(entry.patternCategory..":"..entry.pattern..":"..tostring(context.settings.PvpSafe))
    local data = context and context._attackCache and context._attackCache.bestTileByPattern and context._attackCache.bestTileByPattern[pKey]
    if not data then
      data = getBestTileByPattern(pat, entry.minHp, entry.maxHp, context.settings.PvpSafe, entry.monsters)
    end
    if data and data.pos then
      local okArea = useRuneOnTarget(entry.itemId, g_map.getTile(data.pos):getTopUseThing())
      if okArea and context and context._attackCache then context._attackCache.rotationAttempts = 0 end
    end
  end
end

-- Main simplified attack function
function attackBotMain()
  -- Safety checks
  if not currentSettings or not currentSettings.enabled then return end
  if not panel or not panel.entryList then return end
  if not target() then return end
  if SafeCall.isInPz() then return end
  
  -- Cooldown gating
  if BotCore and BotCore.Cooldown and BotCore.Cooldown.isAttackOnCooldown() then return end
  if modules.game_cooldown.isGroupCooldownIconActive(1) then return end
  
  -- Healing priority checks disabled per user request (do not block attacks on critical/danger)
  -- if HealContext and HealContext.isCritical and HealContext.isCritical() then return end
  -- if HealContext and HealContext.isDanger and HealContext.isDanger() then return end
  if BotCore and BotCore.Priority and not BotCore.Priority.canAttack() then return end
  
  -- Training dummy check
  if currentSettings.Training and target():getName():lower():find("training") then return end
  
  -- Build context and per-tick cache
  local context = {
    target = target(),
    mana = manapercent(),
    settings = currentSettings
  }
  context._attackCache = newAttackCache()

  -- Get entries
  local entries = panel.entryList:getChildren()

  -- Precompute unique availability for spells/items to avoid repeated expensive checks
  local availableSpells = {}
  local availableItems = {}
  local canCastCaller = SafeCall.getCachedCaller("canCast")
  for _, child in ipairs(entries) do
    local entry = child.params
    if not entry then goto precontinue end
    if entry.itemId and entry.itemId > 100 then
      if availableItems[entry.itemId] == nil then
        availableItems[entry.itemId] = (not currentSettings.Visible) or SafeCall.findItem(entry.itemId)
      end
    else
      local spellKey = (entry.spell or ""):lower()
      if availableSpells[spellKey] == nil then
        local ok = nil
        if canCastCaller then
          ok = canCastCaller(spellKey, not currentSettings.ignoreMana, not currentSettings.Cooldown)
        end
        -- If canCast is unavailable (nil), fallback to true to avoid blocking due to startup/load order
        if ok == nil then ok = true end
        availableSpells[spellKey] = ok and true or false
      end
    end
    ::precontinue::
  end



  -- Execute first valid entry (priority order)
  for _, child in ipairs(entries) do
    local entry = child.params
    if not entry then goto continue end

    -- Resource availability check (item present or spell castable)
    local available = false
    if entry.itemId and entry.itemId > 100 then
      available = availableItems[entry.itemId]
    else
      available = availableSpells[entry.spell or ""]
    end

    if not available then
    else
      local should = shouldExecuteEntry(entry, context)
      if not should then
      end
      if should then
        executeAttack(entry, context)
        return
      end
    end
    ::continue::
  end
end
