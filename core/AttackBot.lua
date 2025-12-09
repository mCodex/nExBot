setDefaultTab('main')
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
-- ANALYTICS SYSTEM
-- ============================================================================

-- Initialize or restore analytics from storage
local attackAnalytics = storage.attackAnalytics or {
  spells = {},      -- { [spellName] = count }
  runes = {},       -- { [runeId] = count }
  empowerments = 0, -- Total buff casts
  totalAttacks = 0, -- Total attacks executed
  log = {}          -- Recent actions log (last 50)
}
storage.attackAnalytics = attackAnalytics

-- Record an attack action
local function recordAttackAction(category, idOrFormula)
  attackAnalytics.totalAttacks = attackAnalytics.totalAttacks + 1
  
  -- Category 1, 4, 5 = spells (targeted, empowerment, absolute)
  if category == 1 or category == 4 or category == 5 then
    local spellName = tostring(idOrFormula)
    attackAnalytics.spells[spellName] = (attackAnalytics.spells[spellName] or 0) + 1
    if category == 4 then
      attackAnalytics.empowerments = attackAnalytics.empowerments + 1
    end
  -- Category 2, 3 = runes (area, targeted)
  elseif category == 2 or category == 3 then
    local runeId = tonumber(idOrFormula) or 0
    attackAnalytics.runes[runeId] = (attackAnalytics.runes[runeId] or 0) + 1
  end
  
  -- Keep recent log (last 50)
  local log = attackAnalytics.log
  if #log >= 50 then
    table.remove(log, 1)
  end
  table.insert(log, {
    t = now,
    cat = category,
    action = tostring(idOrFormula)
  })
end

-- Public API for SmartHunt
AttackBot = AttackBot or {}
AttackBot.getAnalytics = function()
  return attackAnalytics
end
AttackBot.resetAnalytics = function()
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
      enabled = false,
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

-- finding correct table, manual unfortunately
local setActiveProfile = function()
  local n = AttackBotConfig.currentBotProfile
  currentSettings = AttackBotConfig[panelName][n]
  -- Save character's profile preference
  setCharacterProfile("attackProfile", n)
end
setActiveProfile()

if not currentSettings.AntiRsRange then
  currentSettings.AntiRsRange = 5 
end

local setProfileName = function()
  ui.name:setText(currentSettings.name)
end

-- small UI elements
ui.title.onClick = function(widget)
  currentSettings.enabled = not currentSettings.enabled
  widget:setOn(currentSettings.enabled)
  nExBotConfigSave("atk")
end
  
ui.settings.onClick = function(widget)
  mainWindow:show()
  mainWindow:raise()
  mainWindow:focus()
end

  mainWindow = UI.createWindow("AttackBotWindow")
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
      local type = regexMatch(patterns[patternCategory][pattern], regex)[1][1]:trim()
      regex = [[^[^ ]+]]
      local categoryName = regexMatch(categories[category], regex)[1][1]:trim():lower()
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

    -- public functions
    AttackBot = {} -- global table
  
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
    if category == 1 or category == 3 then
      local name = getTarget() and getTarget():getName()
      if #t ~= 0 and not table.find(t, name, true) then
        return 0
      end
    end
    for i, spec in pairs(getSpectators()) do
      local specHp = spec:getHealthPercent()
      local name = spec:getName():lower()
      monsters = spec:isMonster() and specHp >= minHp and specHp <= maxHp and (#t == 0 or table.find(t, name, true)) and
                 (g_game.getClientVersion() < 960 or spec:getType() < 3) and monsters + 1 or monsters
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
local function useRuneOnTarget(runeId, targetCreatureOrTile)
  lastAttackTime = now -- Update attack time for non-blocking cooldown
  
  -- Method 1: Use inventory item with target (works without open backpack - like hotkeys)
  if g_game.useInventoryItemWith then
    g_game.useInventoryItemWith(runeId, targetCreatureOrTile)
    return true
  end
  
  -- Method 2: Fallback - find rune in open containers and use with target
  local rune = findItem(runeId)
  if rune then
    g_game.useWith(rune, targetCreatureOrTile)
    return true
  end
  
  return false
end

function executeAttackBotAction(categoryOrPos, idOrFormula, cooldown)
  cooldown = cooldown or 0
  lastAttackTime = now -- Update attack time for non-blocking cooldown
  
  -- Record analytics before executing
  recordAttackAction(categoryOrPos, idOrFormula)
  
  if categoryOrPos == 4 or categoryOrPos == 5 or categoryOrPos == 1 then
    cast(idOrFormula, cooldown)
  elseif categoryOrPos == 3 then 
    useRuneOnTarget(idOrFormula, target())
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
local ENTRY_CACHE_TTL = 500  -- Refresh every 500ms

-- Monster count cache to avoid recounting for similar patterns
local monsterCountCache = {}
local lastMonsterCacheTime = 0
local MONSTER_CACHE_TTL = 100  -- Valid for 100ms (one tick)

local function getMonsterCountCached(category, posOrCreature, pattern, minHp, maxHp, safePattern, monsters)
  -- Invalidate cache if too old
  if now - lastMonsterCacheTime > MONSTER_CACHE_TTL then
    monsterCountCache = {}
    lastMonsterCacheTime = now
  end
  
  -- Generate cache key
  local key = category .. "_" .. minHp .. "_" .. maxHp .. "_" .. tostring(pattern)
  
  if monsterCountCache[key] ~= nil then
    return monsterCountCache[key]
  end
  
  local count = getMonstersInArea(category, posOrCreature, pattern, minHp, maxHp, safePattern, monsters)
  monsterCountCache[key] = count
  return count
end

macro(100, function()
  if not currentSettings.enabled then return end
  
  -- Early exits (ordered by likelihood/speed)
  local currentTarget = target()
  if not currentTarget then return end
  if isInPz() then return end
  if modules.game_cooldown.isGroupCooldownIconActive(1) then return end

  -- Cache attack entries (avoid repeated getChildren calls)
  if now - lastEntryCacheTime > ENTRY_CACHE_TTL then
    cachedAttackEntries = panel.entryList:getChildren()
    cachedEntriesCount = #cachedAttackEntries
    lastEntryCacheTime = now
  end
  
  if cachedEntriesCount == 0 then return end

  -- Training dummy check
  if currentSettings.Training then
    local targetName = currentTarget:getName()
    if targetName and targetName:lower():find("training") then return end
  end

  -- Non-blocking cooldown for older clients
  if isOldClient or not currentSettings.Cooldown then
    if (now - lastAttackTime) < 400 then return end
  end

  -- Direction calculation (reuse pre-allocated table) - only if rotation enabled
  local bestSide = 0
  local bestDir = DIR_NORTH
  
  if currentSettings.Rotate then
    local playerPos = pos()
    directionCounts[1] = getCreaturesInArea(playerPos, posN, 2)  -- North
    directionCounts[2] = getCreaturesInArea(playerPos, posE, 2)  -- East
    directionCounts[3] = getCreaturesInArea(playerPos, posS, 2)  -- South
    directionCounts[4] = getCreaturesInArea(playerPos, posW, 2)  -- West
    
    -- Find best direction (unrolled for performance)
    if directionCounts[1] > bestSide then bestSide = directionCounts[1]; bestDir = DIR_NORTH end
    if directionCounts[2] > bestSide then bestSide = directionCounts[2]; bestDir = DIR_EAST end
    if directionCounts[3] > bestSide then bestSide = directionCounts[3]; bestDir = DIR_SOUTH end
    if directionCounts[4] > bestSide then bestSide = directionCounts[4]; bestDir = DIR_WEST end

    if player:getDirection() ~= bestDir and bestSide > 0 then
      turn(bestDir)
      return
    end
  end

  -- Cache current mana percent (avoid repeated calls)
  local currentMana = manapercent()
  
  -- Cache target data
  local targetHp = currentTarget:getHealthPercent()
  local targetPos = currentTarget:getPosition()
  local targetDist = distanceFromPlayer(targetPos)
  local targetCanShoot = currentTarget:canShoot()

  -- Pre-calculate safety checks once
  local playersInRange = nil  -- Lazy evaluated
  local blacklistCheck = nil  -- Lazy evaluated
  local killsCheck = nil      -- Lazy evaluated

  for i = 1, cachedEntriesCount do
    local child = cachedAttackEntries[i]
    local entry = child.params
    
    -- Skip disabled entries or insufficient mana (fast checks first)
    if not entry.enabled then goto continue end
    if currentMana < entry.mana then goto continue end
    
    local attackData = entry.itemId > 100 and entry.itemId or entry.spell
    
    -- For runes: skip visibility check if using inventory method (works without open BP)
    local runeAvailable = entry.itemId > 100 and (not currentSettings.Visible or g_game.useInventoryItemWith or findItem(entry.itemId))
    local canUseAttack = (type(attackData) == "string" and canCast(entry.spell, not currentSettings.ignoreMana, not currentSettings.Cooldown)) or runeAvailable
    
    if not canUseAttack then goto continue end
    
    -- PVP scenario
    if currentSettings.pvpMode and targetHp >= entry.minHp and targetHp <= entry.maxHp and targetCanShoot then
      if entry.category == 2 then
        warn("[AttackBot] Area Runes cannot be used in PVP situation!")
        goto continue
      else
        return executeAttackBotAction(entry.category, attackData, entry.cooldown)
      end
    end
    
    -- Empowerment
    if entry.category == 4 and not isBuffed() then
      local monsterAmount = getMonsterCountCached(entry.category, nil, nil, entry.minHp, entry.maxHp, false, entry.monsters)
      local countMatch = entry.orMore and monsterAmount >= entry.count or monsterAmount == entry.count
      if countMatch and targetDist <= entry.pattern then
        return executeAttackBotAction(entry.category, attackData, entry.cooldown)
      end
    -- Targeted spells/runes (category 1, 3)
    elseif entry.category == 1 or entry.category == 3 then
      local monsterAmount = getMonsterCountCached(entry.category, nil, nil, entry.minHp, entry.maxHp, false, entry.monsters)
      local countMatch = entry.orMore and monsterAmount >= entry.count or monsterAmount == entry.count
      if countMatch and targetDist <= entry.pattern then
        return executeAttackBotAction(entry.category, attackData, entry.cooldown)
      end
    -- Absolute spells (category 5)
    elseif entry.category == 5 then
      local pCat = entry.patternCategory
      local pattern = entry.pattern
      local anchorParam = (pattern == 2 or pattern == 6 or pattern == 7 or pattern > 9) and player or pos()
      local safe = currentSettings.PvpSafe and spellPatterns[pCat][entry.pattern][2] or false
      local monsterAmount = pCat ~= 8 and getMonsterCountCached(entry.category, anchorParam, spellPatterns[pCat][entry.pattern][1], entry.minHp, entry.maxHp, safe, entry.monsters)
      
      local countMatch = false
      if pattern == 8 then
        -- Sweep pattern uses bestSide
        countMatch = bestSide >= entry.count
        if countMatch and currentSettings.PvpSafe then
          playersInRange = playersInRange or getPlayers(2)
          if playersInRange > 0 then countMatch = false end
        end
      else
        countMatch = entry.orMore and monsterAmount >= entry.count or monsterAmount == entry.count
      end
      
      if countMatch then
        -- Lazy evaluate safety checks
        if currentSettings.BlackListSafe then
          blacklistCheck = blacklistCheck or isBlackListedPlayerInRange(currentSettings.AntiRsRange)
          if blacklistCheck then goto continue end
        end
        if currentSettings.Kills then
          killsCheck = killsCheck or killsToRs()
          if killsCheck <= currentSettings.KillsAmount then goto continue end
        end
        return executeAttackBotAction(entry.category, attackData, entry.cooldown)
      end
    -- Area runes (category 2)
    elseif entry.category == 2 then
      local pCat = entry.patternCategory
      local safe = currentSettings.PvpSafe and spellPatterns[pCat][entry.pattern][2] or false
      local data = getBestTileByPattern(spellPatterns[pCat][entry.pattern][1], entry.minHp, entry.maxHp, safe, entry.monsters)
      
      if data and data.amount then
        local countMatch = entry.orMore and data.amount >= entry.count or data.amount == entry.count
        if countMatch then
          -- Lazy evaluate safety checks
          if currentSettings.BlackListSafe then
            blacklistCheck = blacklistCheck or isBlackListedPlayerInRange(currentSettings.AntiRsRange)
            if blacklistCheck then goto continue end
          end
          if currentSettings.Kills then
            killsCheck = killsCheck or killsToRs()
            if killsCheck <= currentSettings.KillsAmount then goto continue end
          end
          return useRuneOnTarget(attackData, g_map.getTile(data.pos):getTopUseThing())
        end
      end
    end
    
    ::continue::
  end
end)