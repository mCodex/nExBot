TargetBot.Creature.edit = function(config, callback) -- callback = function(newConfig)
  config = config or {}

  local editor = UI.createWindow('TargetBotCreatureEditorWindow')
  local values = {} -- (key, function returning value of key)

  editor.name:setText(config.name or "")
  table.insert(values, {"name", function() return editor.name:getText() end})

  local addScrollBar = function(id, title, min, max, defaultValue, tooltip)
    local widget = UI.createWidget('TargetBotCreatureEditorScrollBar', editor.content.left)
    widget.scroll.onValueChange = function(scroll, value)
      widget.text:setText(title .. ": " .. value)
    end
    widget.scroll:setRange(min, max)
    if max-min > 1000 then
      widget.scroll:setStep(100)
    elseif max-min > 100 then
      widget.scroll:setStep(10)
    end
    widget.scroll:setValue(config[id] or defaultValue)
    widget.scroll.onValueChange(widget.scroll, widget.scroll:getValue())
    if tooltip then
      widget:setTooltip(tooltip)
    end
    table.insert(values, {id, function() return widget.scroll:getValue() end})
  end

  local addTextEdit = function(id, title, defaultValue, tooltip)
    local widget = UI.createWidget('TargetBotCreatureEditorTextEdit', editor.content.right)
    widget.text:setText(title)
    widget.textEdit:setText(config[id] or defaultValue or "")
    if tooltip then
      widget:setTooltip(tooltip)
    end
    table.insert(values, {id, function() return widget.textEdit:getText() end})
  end

  local addCheckBox = function(id, title, defaultValue, tooltip)
    local widget = UI.createWidget('TargetBotCreatureEditorCheckBox', editor.content.right)
    widget.onClick = function()
      widget:setOn(not widget:isOn())
    end
    widget:setText(title)
    if config[id] == nil then
      widget:setOn(defaultValue)
    else
      widget:setOn(config[id])
    end
    if tooltip then
      widget:setTooltip(tooltip)
    end
    table.insert(values, {id, function() return widget:isOn() end})
  end

  local addItem = function(id, title, defaultItem, tooltip)
    local widget = UI.createWidget('TargetBotCreatureEditorItem', editor.content.right)
    widget.text:setText(title)
    widget.item:setItemId(config[id] or defaultItem)
    if tooltip then
      widget:setTooltip(tooltip)
    end
    table.insert(values, {id, function() return widget.item:getItemId() end})
  end

  editor.cancel.onClick = function()
    editor:destroy()
  end
  editor.onEscape = editor.cancel.onClick

  editor.ok.onClick = function()
    local newConfig = {}
    for _, value in ipairs(values) do
      newConfig[value[1]] = value[2]()
    end
    if newConfig.name:len() < 1 then return end

    -- Parse patterns with exclusion support
    -- Pattern format: "name1, name2, !exclude1, !exclude2"
    -- * = all monsters, ! = exclude pattern
    local includes = {}
    local excludes = {}
    
    for part in string.gmatch(newConfig.name, "[^,]+") do
      local trimmed = part:trim():lower()
      if trimmed:sub(1, 1) == "!" then
        -- Exclusion pattern
        local excludeName = trimmed:sub(2):trim()
        if excludeName:len() > 0 then
          local pattern = "^" .. excludeName:gsub("%*", ".*"):gsub("%?", ".?") .. "$"
          table.insert(excludes, pattern)
        end
      else
        -- Include pattern
        local pattern = "^" .. trimmed:gsub("%*", ".*"):gsub("%?", ".?") .. "$"
        table.insert(includes, pattern)
      end
    end
    
    -- Build include regex
    if #includes > 0 then
      newConfig.regex = table.concat(includes, "|")
    else
      newConfig.regex = "^$"
    end
    
    -- Build exclude regex
    if #excludes > 0 then
      newConfig.excludeRegex = table.concat(excludes, "|")
    else
      newConfig.excludeRegex = nil
    end

    editor:destroy()
    callback(newConfig)
  end

  -- values with tooltips
  addScrollBar("priority", "Priority", 0, 10, 1, "Higher priority = attack first. When multiple creatures match, highest priority wins.")
  addScrollBar("danger", "Danger", 0, 10, 1, "Danger level contribution. Affects emergency decisions and healing priority.")
  addScrollBar("maxDistance", "Max distance", 1, 10, 10, "Maximum distance to target this creature. Creatures beyond this range are ignored.")
  addScrollBar("keepDistanceRange", "Keep distance", 1, 5, 1, "Preferred distance from target when 'Keep Distance' is enabled.")
  addScrollBar("anchorRange", "Anchoring Range", 1, 10, 3, "Maximum distance from anchor point when 'Anchoring' is enabled.")
  addScrollBar("lureMin", "Dynamic lure min", 0, 29, 1, "Start luring when monster count drops below this value.")
  addScrollBar("lureMax", "Dynamic lure max", 1, 30, 3, "Stop luring when monster count reaches this value.")
  addScrollBar("lureDelay", "Dynamic lure delay", 100, 1000, 250, "Delay in ms before CaveBot continues walking during lure.")
  addScrollBar("delayFrom", "Start delay when monsters", 1, 29, 2, "Apply walking delay when monster count is at least this value.")
  addScrollBar("rePositionAmount", "Min tiles to rePosition", 0, 7, 5, "Reposition when fewer than this many walkable tiles around you.")
  addScrollBar("smartPullRange", "Pull Range", 1, 5, 2, "Range (in tiles) to check for nearby monsters. Works with the selected Shape.")
  addScrollBar("smartPullMin", "Pull Min Monsters", 1, 8, 3, "Minimum monsters needed within range. If fewer are present, CaveBot walks to pull more.")
  
  -- Special scrollbar for Shape with name display
  do
    local shapeNames = {
      [1] = "SQUARE",
      [2] = "CIRCLE", 
      [3] = "DIAMOND",
      [4] = "CROSS"
    }
    local widget = UI.createWidget('TargetBotCreatureEditorScrollBar', editor.content.left)
    widget.scroll.onValueChange = function(scroll, value)
      local shapeName = shapeNames[value] or "UNKNOWN"
      widget.text:setText("Pull Shape: " .. shapeName)
    end
    widget.scroll:setRange(1, 4)
    widget.scroll:setValue(config.smartPullShape or 2)
    widget.scroll.onValueChange(widget.scroll, widget.scroll:getValue())
    widget:setTooltip([[Shape for monster distance calculation:

SQUARE (1): Chebyshev distance - includes diagonal tiles equally.
    Default Tibia-style range check. Fast computation.
    
CIRCLE (2): Euclidean distance - true circular area.
    Most accurate for AoE spells. Recommended.
    
DIAMOND (3): Manhattan distance - cross/plus pattern.
    Counts only horizontal + vertical steps.
    
CROSS (4): Cardinal directions only (N/E/S/W).
    Very narrow, line-of-sight style.]])
    table.insert(values, {"smartPullShape", function() return widget.scroll:getValue() end})
  end

  addCheckBox("autoFollow", "Auto Follow", false, "Use the bot's pathfinding to walk closer to the target for chasing. More precise for attacks; disabled when 'Keep Distance' is active. Note: Auto-follow is disabled if 'Avoid Attacks' or 'Re-position' is enabled.")
  addCheckBox("chase", "Chase", true, "Chase the target, walking towards it until adjacent.")
  addCheckBox("keepDistance", "Keep Distance", false, "Maintain a specific distance from the target (set in Keep Distance slider).")
  addCheckBox("anchor", "Anchoring", false, "Stay within a radius of your initial position (set in Anchoring Range slider).")
  addCheckBox("dontLoot", "Don't loot", false, "Skip looting corpses of this creature type.")
  addCheckBox("faceMonster", "Face monsters", false, "Turn to face diagonal monsters for better weapon/spell accuracy.")
  addCheckBox("avoidAttacks", "Avoid wave attacks", false, "Intelligently move out of predicted wave/area attack zones.")
  addCheckBox("dynamicLure", "Dynamic lure", false, "Lure using CaveBot when monster count is below min, stop when above max.")
  addCheckBox("dynamicLureDelay", "Dynamic lure delay", false, "Add walking delay when enough monsters are around (reduces kiting speed).")
  addCheckBox("diamondArrows", "D-Arrows priority", false, "Prioritize targets for Diamond Arrow AoE optimization.")
  addCheckBox("rePosition", "rePosition to better tile", false, "Move to tiles with more open space when cornered.")
  addCheckBox("smartPull", "Pull System", false, [[When enabled, uses CaveBot to walk and pull more monsters if the current pack is too small.
Configure with: Pull Range (how far to check), Min Monsters (threshold), and Shape (accuracy).
Useful for AoE hunting - ensures you always have enough monsters grouped before attacking.]])
  addCheckBox("rpSafe", "RP PVP SAFE - (DA)", false, "Safety mode for Royal Paladins - prevents Diamond Arrow usage near players.")

  -- Attack settings have been moved to AttackBot and are no longer available in TargetBot.
  -- If you need to configure attack spells/runes, use the dedicated AttackBot profile and UI.

end
