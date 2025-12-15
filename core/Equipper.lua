local panelName = "EquipperPanel"
local HealContext = dofile("/core/heal_context.lua")

-- ============================================================================
-- UI SETUP
-- ============================================================================

local ui = setupUI([[
Panel
  height: 19

  BotSwitch
    id: switch
    anchors.top: parent.top
    anchors.left: parent.left
    text-align: center
    width: 130
    !text: tr('EQ Manager')

  Button
    id: setup
    anchors.top: prev.top
    anchors.left: prev.right
    anchors.right: parent.right
    margin-left: 3
    height: 17
    text: Setup
]])
ui:setId(panelName)

-- ============================================================================
-- STORAGE & STATE (Centralized)
-- ============================================================================

if not storage[panelName] or not storage[panelName].bosses then
    storage[panelName] = {
        enabled = false,
        rules = {},
        bosses = {}
    }
end

local config = storage[panelName]

-- Non-blocking equipment manager state
local EquipState = {
  lastEquipAction = 0,
    EQUIP_COOLDOWN = 250,    -- ms between equip actions (align with macro interval)
  missingItem = false,
  lastRule = nil,
  correctEq = false,
  needsEquipCheck = true,
  rulesCache = nil,        -- Cached rules for macro iteration
    rulesCacheDirty = true,  -- Flag to rebuild cache
    normalizedRules = nil,
    normalizedDirty = true
}

-- ============================================================================
-- CACHE MANAGEMENT
-- ============================================================================

-- Invalidate rules cache when rules change
local function invalidateRulesCache()
  EquipState.rulesCacheDirty = true
  EquipState.needsEquipCheck = true
  EquipState.correctEq = false
    EquipState.normalizedDirty = true
end

-- Get cached rules (avoids repeated getChildren calls in macro)
local function getCachedRules()
  if EquipState.rulesCacheDirty or not EquipState.rulesCache then
    EquipState.rulesCache = config.rules
    EquipState.rulesCacheDirty = false
  end
  return EquipState.rulesCache
end

ui.switch:setOn(config.enabled)
ui.switch.onClick = function(widget)
  config.enabled = not config.enabled
  widget:setOn(config.enabled)
end

local conditions = { -- always add new conditions at the bottom
    "Item is available and not worn.", -- nothing 1
    "Monsters around is more than: ", -- spinbox 2
    "Monsters around is less than: ", -- spinbox 3
    "Health precent is below:", -- spinbox 4
    "Health precent is above:", -- spinbox 5
    "Mana precent is below:", -- spinbox 6
    "Mana precent is above:", -- spinbox 7
    "Target name is:", -- BotTextEdit 8
    "Hotkey is being pressed:", -- BotTextEdit 9
    "Player is paralyzed", -- nothing 10
    "Player is in protection zone", -- nothing 11
    "Players around is more than:", -- spinbox 12
    "Players around is less than:", -- spinbox 13
    "TargetBot Danger is Above:", -- spinbox 14
    "Blacklist player in range (sqm)", -- spinbox 15
    "Target is Boss", -- nothing 16
    "Player is NOT in protection zone", -- nothing 17
    "CaveBot is ON, TargetBot is OFF" -- nothing 18
}

local conditionNumber = 1
local optionalConditionNumber = 2

local mainWindow = UI.createWindow("EquipWindow")
mainWindow:hide()

ui.setup.onClick = function()
    mainWindow:show()
    mainWindow:raise()
    mainWindow:focus()
end

local inputPanel = mainWindow.inputPanel
local listPanel = mainWindow.listPanel
local namePanel = mainWindow.profileName
local eqPanel = mainWindow.setup
local bossPanel = mainWindow.bossPanel

local slotWidgets = {eqPanel.head, eqPanel.body, eqPanel.legs, eqPanel.feet, eqPanel.neck, eqPanel["left-hand"], eqPanel["right-hand"], eqPanel.finger, eqPanel.ammo} -- back is disabled

local function setCondition(first, n)
    local widget
    local spinBox 
    local textEdit

    if first then
        widget = inputPanel.condition.description.text
        spinBox = inputPanel.condition.spinbox
        textEdit = inputPanel.condition.text
    else
        widget = inputPanel.optionalCondition.description.text
        spinBox = inputPanel.optionalCondition.spinbox
        textEdit = inputPanel.optionalCondition.text
    end

    -- reset values after change
    spinBox:setValue(0)
    textEdit:setText('')

    if n == 1 or n == 10 or n == 11 or n == 16 or n == 17 or n == 18 then
        spinBox:hide()
        textEdit:hide()
    elseif n == 9 or n == 8 then
        spinBox:hide()
        textEdit:show()
        if n == 9 then
            textEdit:setWidth(75)
        else
            textEdit:setWidth(200)
        end
    else
        spinBox:show()
        textEdit:hide()
    end
    widget:setText(conditions[n])
end

local function resetFields()
    conditionNumber = 1
    optionalConditionNumber = 2
    setCondition(false, optionalConditionNumber)
    setCondition(true, conditionNumber)
    for i, widget in ipairs(slotWidgets) do
        widget:setItemId(0)
        widget:setChecked(false)
    end
    local children = listPanel.list:getChildren()
    for i = 1, #children do
        children[i].display = false
    end
    namePanel.profileName:setText("")
    inputPanel.condition.text:setText('')
    inputPanel.condition.spinbox:setValue(0)
    inputPanel.useSecondCondition:setText('-')
    inputPanel.optionalCondition.text:setText('')
    inputPanel.optionalCondition.spinbox:setValue(0)
    inputPanel.optionalCondition:hide()
    bossPanel:hide()
    listPanel:show()
    mainWindow.bossList:setText('Boss List')
    bossPanel.name:setText('')
end
resetFields()

mainWindow.closeButton.onClick = function()
    resetFields()
    mainWindow:hide()
end

inputPanel.optionalCondition:hide()
inputPanel.useSecondCondition.onOptionChange = function(widget, option, data)
    if option ~= "-" then
        inputPanel.optionalCondition:show()
    else
        inputPanel.optionalCondition:hide()
    end
end

-- add default text & windows
setCondition(true, 1)
setCondition(false, 2)

-- in/de/crementation buttons
inputPanel.condition.nex.onClick = function()
    local max = #conditions

    if inputPanel.optionalCondition:isVisible() then
        if conditionNumber == max then
            if optionalConditionNumber == 1 then
                conditionNumber = 2
            else
                conditionNumber = 1
            end
        else
            local futureNumber = conditionNumber + 1
            local safeFutureNumber = conditionNumber + 2 > max and 1 or conditionNumber + 2
            conditionNumber = futureNumber ~= optionalConditionNumber and futureNumber or safeFutureNumber
        end
    else
        conditionNumber = conditionNumber == max and 1 or conditionNumber + 1
        if optionalConditionNumber == conditionNumber then
            optionalConditionNumber = optionalConditionNumber == max and 1 or optionalConditionNumber + 1
            setCondition(false, optionalConditionNumber)
        end
    end
    setCondition(true, conditionNumber)
end

inputPanel.condition.pre.onClick = function()
    local max = #conditions

    if inputPanel.optionalCondition:isVisible() then
        if conditionNumber == 1 then
            if optionalConditionNumber == max then
                conditionNumber = max-1
            else
                conditionNumber = max
            end
        else
            local futureNumber = conditionNumber - 1
            local safeFutureNumber = conditionNumber - 2 < 1 and max or conditionNumber - 2
            conditionNumber = futureNumber ~= optionalConditionNumber and futureNumber or safeFutureNumber
        end
    else
        conditionNumber = conditionNumber == 1 and max or conditionNumber - 1
        if optionalConditionNumber == conditionNumber then
            optionalConditionNumber = optionalConditionNumber == 1 and max or optionalConditionNumber - 1
            setCondition(false, optionalConditionNumber)
        end
    end
    setCondition(true, conditionNumber)
end

inputPanel.optionalCondition.nex.onClick = function()
    local max = #conditions

    if optionalConditionNumber == max then
        if conditionNumber == 1 then
            optionalConditionNumber = 2
        else
            optionalConditionNumber = 1
        end
    else
        local futureNumber = optionalConditionNumber + 1
        local safeFutureNumber = optionalConditionNumber + 2 > max and 1 or optionalConditionNumber + 2
        optionalConditionNumber = futureNumber ~= conditionNumber and futureNumber or safeFutureNumber
    end
    setCondition(false, optionalConditionNumber)
end

inputPanel.optionalCondition.pre.onClick = function()
    local max = #conditions

    if optionalConditionNumber == 1 then
        if conditionNumber == max then
            optionalConditionNumber = max-1
        else
            optionalConditionNumber = max
        end
    else
        local futureNumber = optionalConditionNumber - 1
        local safeFutureNumber = optionalConditionNumber - 2 < 1 and max or optionalConditionNumber - 2
        optionalConditionNumber = futureNumber ~= conditionNumber and futureNumber or safeFutureNumber
    end
    setCondition(false, optionalConditionNumber)
end

listPanel.up.onClick = function(widget)
    local focused = listPanel.list:getFocusedChild()
    local n = listPanel.list:getChildIndex(focused)
    local t = config.rules

    t[n], t[n-1] = t[n-1], t[n]
    if n-1 == 1 then
      widget:setEnabled(false)
    end
    listPanel.down:setEnabled(true)
    listPanel.list:moveChildToIndex(focused, n-1)
    listPanel.list:ensureChildVisible(focused)
    invalidateRulesCache()  -- Priority changed
end

listPanel.down.onClick = function(widget)
    local focused = listPanel.list:getFocusedChild()    
    local n = listPanel.list:getChildIndex(focused)
    local t = config.rules

    t[n], t[n+1] = t[n+1], t[n]
    if n + 1 == listPanel.list:getChildCount() then
      widget:setEnabled(false)
    end
    listPanel.up:setEnabled(true)
    listPanel.list:moveChildToIndex(focused, n+1)
    listPanel.list:ensureChildVisible(focused)
    invalidateRulesCache()  -- Priority changed
end

eqPanel.cloneEq.onClick = function(widget)
    eqPanel.head:setItemId(getHead() and getHead():getId() or 0)
    eqPanel.body:setItemId(getBody() and getBody():getId() or 0)
    eqPanel.legs:setItemId(getLeg() and getLeg():getId() or 0)
    eqPanel.feet:setItemId(getFeet() and getFeet():getId() or 0)  
    eqPanel.neck:setItemId(getNeck() and getNeck():getId() or 0)   
    eqPanel["left-hand"]:setItemId(getLeft() and getLeft():getId() or 0)
    eqPanel["right-hand"]:setItemId(getRight() and getRight():getId() or 0)
    eqPanel.finger:setItemId(getFinger() and getFinger():getId() or 0)    
    eqPanel.ammo:setItemId(getAmmo() and getAmmo():getId() or 0)    
end

eqPanel.default.onClick = resetFields

-- buttons disabled by default
listPanel.up:setEnabled(false)
listPanel.down:setEnabled(false)

-- correct background image
for i, widget in ipairs(slotWidgets) do
    widget:setTooltip("Right click to set as slot to unequip")
    widget.onItemChange = function(widget)
        local selfId = widget:getItemId()
        widget:setOn(selfId > 100)
        if widget:isChecked() then
            widget:setChecked(selfId < 100)
        end
    end
    widget.onMouseRelease = function(widget, mousePos, mouseButton)
        if mouseButton == 2 then
            local clearItem = widget:isChecked() == false
            widget:setChecked(not widget:isChecked())
            if clearItem then
                widget:setItemId(0)
            end
        end
    end
end

inputPanel.condition.description.onMouseWheel = function(widget, mousePos, scroll)
    if scroll == 1 then
        inputPanel.condition.nex.onClick()
    else
        inputPanel.condition.pre.onClick()
    end
end

inputPanel.optionalCondition.description.onMouseWheel = function(widget, mousePos, scroll)
    if scroll == 1 then
        inputPanel.optionalCondition.nex.onClick()
    else
        inputPanel.optionalCondition.pre.onClick()
    end
end

namePanel.profileName.onTextChange = function(widget, text)
    local button = inputPanel.add
    text = text:lower()
    
    -- Check against config.rules directly (not UI children)
    local isOverwrite = false
    for i = 1, #config.rules do
        if config.rules[i].name:lower() == text then
            isOverwrite = true
            break
        end
    end
    
    button:setText(isOverwrite and "Overwrite" or "Add Rule")
    button:setTooltip(isOverwrite and ("Overwrite existing rule named: " .. text) or ("Add new rule to the list: " .. text))
end

-- Populate Equipment Setup slots when editing a rule (double-click)
local function loadRuleToSlots(data)
    for i, value in ipairs(data) do
        local widget = slotWidgets[i]
        if value == false then
            widget:setChecked(false)
            widget:setItemId(0)
        elseif value == true then
            widget:setChecked(true)
            widget:setItemId(0)
        else
            widget:setChecked(false)
            widget:setItemId(value)       
        end
    end
end

-- ============================================================================
-- RULES LIST UI (Optimized - no destroyChildren flicker)
-- ============================================================================

-- Widget cache to avoid recreating widgets
local ruleWidgetCache = {}

-- Create or update a single rule widget
local function createOrUpdateRuleWidget(list, rule, index)
  local widgetId = "rule_" .. index
  local widget = ruleWidgetCache[widgetId]
  
  -- Reuse existing widget or create new one
  if not widget or not widget:getParent() then
    widget = UI.createWidget('Rule', list)
    ruleWidgetCache[widgetId] = widget
  end
  
  widget:setId(rule.name)
  widget:setText(rule.name)
  widget.ruleData = rule
  
  -- Update visual state without recreating
  widget.visible:setColor(rule.visible and "green" or "red")
  widget.enabled:setChecked(rule.enabled)
  
  -- Set up event handlers (only if not already set)
  if not widget._handlersSet then
    widget.remove.onClick = function()
      local ruleIndex = table.find(config.rules, rule)
      if ruleIndex then
        table.remove(config.rules, ruleIndex)
      end
      widget:destroy()
      ruleWidgetCache[widgetId] = nil
      listPanel.up:setEnabled(false)
      listPanel.down:setEnabled(false)
      invalidateRulesCache()
      refreshRules()
    end
    
    widget.visible.onClick = function()
      rule.visible = not rule.visible
      widget.visible:setColor(rule.visible and "green" or "red")
    end
    
    widget.enabled.onClick = function()
      rule.enabled = not rule.enabled
      widget.enabled:setChecked(rule.enabled)
      invalidateRulesCache()
    end
    
    -- Hover preview disabled - Equipment Setup only shows when editing (double-click)
    
    widget.onDoubleClick = function(w)
      local ruleData = w.ruleData
      w.display = true
      loadRuleToSlots(ruleData.data)
      conditionNumber = ruleData.mainCondition
      optionalConditionNumber = ruleData.optionalCondition
      setCondition(false, optionalConditionNumber)
      setCondition(true, conditionNumber)
      inputPanel.useSecondCondition:setOption(ruleData.relation)
      namePanel.profileName:setText(rule.name)

      if type(ruleData.mainValue) == "string" then
        inputPanel.condition.text:setText(ruleData.mainValue)
      elseif type(ruleData.mainValue) == "number" then
        inputPanel.condition.spinbox:setValue(ruleData.mainValue)
      end

      if type(ruleData.optValue) == "string" then
        inputPanel.optionalCondition.text:setText(ruleData.optValue)
      elseif type(ruleData.optValue) == "number" then
        inputPanel.optionalCondition.spinbox:setValue(ruleData.optValue)
      end
    end
    
    widget.onClick = function()
      local panel = listPanel
      local childCount = #panel.list:getChildren()
      local focusedChild = panel.list:getFocusedChild()
      local focusedIndex = focusedChild and panel.list:getChildIndex(focusedChild) or 0
      
      if childCount == 1 then
        panel.up:setEnabled(false)
        panel.down:setEnabled(false)
      elseif focusedIndex == 1 then
        panel.up:setEnabled(false)
        panel.down:setEnabled(true)
      elseif focusedIndex == childCount then
        panel.up:setEnabled(true)
        panel.down:setEnabled(false)
      else
        panel.up:setEnabled(true)
        panel.down:setEnabled(true)
      end
    end
    
    widget._handlersSet = true
  end
  
  return widget
end

local function refreshRules()
  local list = listPanel.list
  local existingChildren = list:getChildren()
  local rulesCount = #config.rules
  
  -- Remove excess widgets (if rules were deleted)
  for i = rulesCount + 1, #existingChildren do
    local widget = existingChildren[i]
    if widget then
      widget:destroy()
      ruleWidgetCache["rule_" .. i] = nil
    end
  end
  
  -- Create or update widgets for each rule
  for i, rule in ipairs(config.rules) do
    createOrUpdateRuleWidget(list, rule, i)
  end
  
  -- Invalidate macro cache
  invalidateRulesCache()
end
refreshRules()

inputPanel.add.onClick = function(widget)
    local mainVal
    local optVal
    local t = {}
    local relation = inputPanel.useSecondCondition:getText()
    local profileName = namePanel.profileName:getText()
    if profileName:len() == 0 then
        return warn("Please fill profile name!")
    end

    for i, widget in ipairs(slotWidgets) do
        local checked = widget:isChecked()
        local id = widget:getItemId()

        if checked then
            table.insert(t, true) -- unequip selected slot
        elseif id then
            table.insert(t, id) -- equip selected item
        else
            table.insert(t, false) -- ignore slot
        end
    end

    if conditionNumber == 1 then
        mainVal = nil
    elseif conditionNumber == 8 then
        mainVal = inputPanel.condition.text:getText()
        if mainVal:len() == 0 then
            return warn("[nExBot Equipper] Please fill the name of the creature.")
        end
    elseif conditionNumber == 9 then
        mainVal = inputPanel.condition.text:getText()
        if mainVal:len() == 0 then
            return warn("[nExBot Equipper] Please set correct hotkey.")
        end
    else
        mainVal = inputPanel.condition.spinbox:getValue()
    end

    if relation ~= "-" then
        if optionalConditionNumber == 1 then
            optVal = nil
        elseif optionalConditionNumber == 8 then
            optVal = inputPanel.optionalCondition.text:getText()
            if optVal:len() == 0 then
                return warn("[nExBot Equipper] Please fill the name of the creature.")
            end
        elseif optionalConditionNumber == 9 then
            optVal = inputPanel.optionalCondition.text:getText()
            if optVal:len() == 0 then
                return warn("[nExBot Equipper] Please set correct hotkey.")
            end
        else
            optVal = inputPanel.optionalCondition.spinbox:getValue()
        end
    end

    local index
    for i, v in ipairs(config.rules) do
        if v.name == profileName then
            index = i   -- search if there's already rule with this name
        end
    end

    local ruleData = {
        name = profileName, 
        data = t,
        enabled = true,
        visible = true,
        mainCondition = conditionNumber,
        optionalCondition = optionalConditionNumber,
        mainValue = mainVal,
        optValue = optVal,
        relation = relation,
    }

    if index then
        config.rules[index] = ruleData -- overwrite
    else
        table.insert(config.rules, ruleData) -- create new one
    end

    -- Reset display flag on all children
    local children = listPanel.list:getChildren()
    for i = 1, #children do
        children[i].display = false
    end
    
    resetFields()
    invalidateRulesCache()  -- Important: invalidate cache after rule changes
    refreshRules()
end

mainWindow.bossList.onClick = function(widget)
    if bossPanel:isVisible() then
        bossPanel:hide()
        listPanel:show()
        widget:setText('Boss List')
    else
        bossPanel:show()
        listPanel:hide()
        widget:setText('Rule List')

    end
end

-- create boss labels
for i, v in ipairs(config.bosses) do
    local widget = UI.createWidget("BossLabel", bossPanel.list)
    widget:setText(v)
    widget.remove.onClick = function()
        table.remove(config.bosses, table.find(config.bosses, v))
        widget:destroy()
    end
end

bossPanel.add.onClick = function()
    local name = bossPanel.name:getText()

    if name:len() == 0 then
        return warn("[Equipped] Please enter boss name!")
    elseif table.find(config.bosses, name:lower(), true) then
        return warn("[Equipper] Boss already added!")
    end

    local widget = UI.createWidget("BossLabel", bossPanel.list)
    widget:setText(name)
    widget.remove.onClick = function()
        table.remove(config.bosses, table.find(config.bosses, name))
        widget:destroy()
    end    

    table.insert(config.bosses, name)
    bossPanel.name:setText('')
end

local function interpreteCondition(n, v)

    if n == 1 then
        return true
    elseif n == 2 then
        return getMonsters() > v
    elseif n == 3 then
        return getMonsters() < v
    elseif n == 4 then
        return hppercent() < v
    elseif n == 5 then
        return hppercent() > v
    elseif n == 6 then
        return manapercent() < v
    elseif n == 7 then
        return manapercent() > v
    elseif n == 8 then
        return target() and target():getName():lower() == v:lower() or false
    elseif n == 9 then
        return g_keyboard.isKeyPressed(v)
    elseif n == 10 then
        return isParalyzed()
    elseif n == 11 then
        return isInPz()
    elseif n == 12 then
        return getPlayers() > v
    elseif n == 13 then
        return getPlayers() < v
    elseif n == 14 then
        return TargetBot.Danger() > v and TargetBot.isOn()
    elseif n == 15 then
        return isBlackListedPlayerInRange(v)
    elseif n == 16 then
        return target() and table.find(config.bosses, target():getName():lower(), true) and true or false
    elseif n == 17 then
        return not isInPz()
    elseif n == 18 then
        return CaveBot.isOn() and TargetBot.isOff()
    end
end

local function finalCheck(first,relation,second)
    if relation == "-" then
        return first
    elseif relation == "and" then
        return first and second
    elseif relation == "or" then
        return first or second
    end
end

-- ============================================================================
-- SLOT / INVENTORY HELPERS (pure-ish, cached per tick)
-- ============================================================================

local SLOT_ACCESSORS = {
    [1] = getHead,
    [2] = getBody,
    [3] = getLeg,
    [4] = getFeet,
    [5] = getNeck,
    [6] = getLeft,
    [7] = getRight,
    [8] = getFinger,
    [9] = getAmmo,
}

-- Map UI slot index → client slot id (keeps legacy mapping but centralized)
local SLOT_MAP = {
    [1] = 1,  -- head
    [2] = 4,  -- body
    [3] = 7,  -- legs
    [4] = 8,  -- feet
    [5] = 2,  -- neck
    [6] = 6,  -- left hand
    [7] = 5,  -- right hand
    [8] = 9,  -- finger
    [9] = 10, -- ammo
}

local DEFENSIVE_SLOTS = {
    [2] = true, -- body
    [6] = true, -- left hand (often shield)
    [7] = true, -- right hand (weapon/shield)
}

local function slotHasItem(slotIdx)
    local f = SLOT_ACCESSORS[slotIdx]
    if not f then return nil end
    return f()
end

local function slotHasItemId(slotIdx, itemId)
    local item = slotHasItem(slotIdx)
    if not item then return false end
    local ids = {itemId, getInactiveItemId(itemId), getActiveItemId(itemId)}
    return table.find(ids, item:getId()) and true or false
end

local function buildInventoryIndex()
    local idx = {}
    for _, container in ipairs(getContainers()) do
        local items = container:getItems()
        if items then
            for _, it in ipairs(items) do
                local id = it:getId()
                if not idx[id] then idx[id] = {} end
                table.insert(idx[id], it)
            end
        end
    end
    return idx
end

local function snapshotContext()
    return {
        hp = hppercent(),
        mp = manapercent(),
        monsters = getMonsters(),
        players = getPlayers(),
        target = target() and target():getName():lower() or nil,
        inPz = isInPz(),
        paralyzed = isParalyzed(),
        danger = (TargetBot and TargetBot.Danger and TargetBot.Danger()) or 0,
        cavebotOn = CaveBot and CaveBot.isOn and CaveBot.isOn() or false,
        targetbotOn = TargetBot and TargetBot.isOn and TargetBot.isOn() or false,
    }
end

-- Safety guard: avoid stripping defensive gear when exposed
local SAFETY = {
    minHp = 35,
    maxDanger = 50,
}

local function isUnsafeToUnequip(ctx)
    if ctx.inPz then return false end
    if ctx.hp <= SAFETY.minHp then return true end
    if ctx.danger >= SAFETY.maxDanger then return true end
    return false
end

local function unequipSlot(slotIdx)
    local item = slotHasItem(slotIdx)
    if not item then return false end

    if g_game.getClientVersion() >= 910 then
        g_game.equipItemId(item:getId())
        return true
    end

    -- legacy move to first suitable container
    local dest
    for _, container in ipairs(getContainers()) do
        local cname = container:getName()
        if not containerIsFull(container) and not cname:find("loot") and (cname:find("backpack") or cname:find("bag") or cname:find("chess")) then
            dest = container
            break
        end
    end
    if not dest then return false end
    local pos = dest:getSlotPosition(dest:getItemsCount())
    return g_game.move(item, pos, item:getCount())
end

local function equipSlot(slotIdx, itemId)
    local mappedSlot = SLOT_MAP[slotIdx] or slotIdx
    if g_game.getClientVersion() >= 910 then
        return g_game.equipItemId(itemId, mappedSlot)
    else
        local item = findItem(itemId)
        if not item then return false end
        return moveToSlot(item, mappedSlot)
    end
end

-- ============================================================================
-- CONDITIONS (table-driven)
-- ============================================================================

local conditionFns = {
    [1]  = function(ctx, v) return true end,
    [2]  = function(ctx, v) return ctx.monsters > v end,
    [3]  = function(ctx, v) return ctx.monsters < v end,
    [4]  = function(ctx, v) return ctx.hp < v end,
    [5]  = function(ctx, v) return ctx.hp > v end,
    [6]  = function(ctx, v) return ctx.mp < v end,
    [7]  = function(ctx, v) return ctx.mp > v end,
    [8]  = function(ctx, v) return ctx.target and v and ctx.target == v:lower() end,
    [9]  = function(ctx, v) return v and g_keyboard.isKeyPressed(v) end,
    [10] = function(ctx, v) return ctx.paralyzed end,
    [11] = function(ctx, v) return ctx.inPz end,
    [12] = function(ctx, v) return ctx.players > v end,
    [13] = function(ctx, v) return ctx.players < v end,
    [14] = function(ctx, v) return (ctx.danger or 0) > v and ctx.targetbotOn end,
    [15] = function(ctx, v) return isBlackListedPlayerInRange(v) end,
    [16] = function(ctx, v) return ctx.target and table.find(config.bosses, ctx.target, true) and true or false end,
    [17] = function(ctx, v) return not ctx.inPz end,
    [18] = function(ctx, v) return ctx.cavebotOn and not ctx.targetbotOn end,
}

local function evalCondition(id, value, ctx)
    local fn = conditionFns[id]
    if not fn then return false end
    return fn(ctx, value)
end

local function rulePasses(rule, ctx)
    local mainOk = evalCondition(rule.mainCondition, rule.mainValue, ctx)
    if rule.relation == "-" then return mainOk end
    local optOk = evalCondition(rule.optionalCondition, rule.optValue, ctx)
    if rule.relation == "and" then return mainOk and optOk end
    if rule.relation == "or" then return mainOk or optOk end
    return mainOk
end

-- ============================================================================
-- RULE NORMALIZATION (precompute slot plans)
-- ============================================================================

local function normalizeRule(rule)
    local slots = {}
    for idx, val in ipairs(rule.data or {}) do
        if val == true then
            slots[#slots + 1] = {slotIdx = idx, mode = "unequip"}
        elseif type(val) == "number" and val > 100 then
            slots[#slots + 1] = {slotIdx = idx, mode = "equip", itemId = val}
        end
    end
    return {
        name = rule.name,
        enabled = rule.enabled ~= false,
        visible = rule.visible ~= false,
        mainCondition = rule.mainCondition,
        optionalCondition = rule.optionalCondition,
        mainValue = rule.mainValue,
        optValue = rule.optValue,
        relation = rule.relation or "-",
        slots = slots,
    }
end

local function getNormalizedRules()
    if EquipState.normalizedDirty or not EquipState.normalizedRules then
        local raw = getCachedRules() or {}
        local norm = {}
        for i = 1, #raw do
            norm[#norm + 1] = normalizeRule(raw[i])
        end
        EquipState.normalizedRules = norm
        EquipState.normalizedDirty = false
    end
    return EquipState.normalizedRules
end

-- ============================================================================
-- ACTION PLANNING (pure decision-making)
-- ============================================================================

local function computeAction(rule, ctx, inventoryIndex)
    local missing = false

    -- First, process unequips (priority: don’t strip defenses when unsafe)
    for _, slotPlan in ipairs(rule.slots) do
        if slotPlan.mode == "unequip" then
            local hasItem = slotHasItem(slotPlan.slotIdx)
            if hasItem then
                if DEFENSIVE_SLOTS[slotPlan.slotIdx] and isUnsafeToUnequip(ctx) then
                    missing = true -- treat as pending to avoid turning correctEq true
                else
                    return {kind = "unequip", slotIdx = slotPlan.slotIdx}, missing
                end
            end
        end
    end

    -- Then, process equips (first missing slot gets action)
    for _, slotPlan in ipairs(rule.slots) do
        if slotPlan.mode == "equip" and slotPlan.itemId then
            if not slotHasItemId(slotPlan.slotIdx, slotPlan.itemId) then
                local hasItem = inventoryIndex[slotPlan.itemId] ~= nil
                if hasItem then
                    return {kind = "equip", slotIdx = slotPlan.slotIdx, itemId = slotPlan.itemId}, missing
                else
                    missing = true
                end
            end
        end
    end

    return nil, missing
end


local function markChild(child)
    if mainWindow:isVisible() then
        local children = listPanel.list:getChildren()
        for i = 1, #children do
            local c = children[i]
            if c ~= child then
                c:setColor('white')
            end
        end
        if child then child:setColor('green') end
    end
end

-- Subscribe to equipment change events from EventBus
if EventBus then
  EventBus.on("equipment:change", function(slotId, slotName, newId, oldId, item)
    EquipState.needsEquipCheck = true
    EquipState.correctEq = false
  end, 50)
end

-- ============================================================================
-- MAIN EQUIPMENT MACRO (Optimized)
-- Uses cached rules instead of UI children iteration
-- ============================================================================

EquipManager = macro(250, function()
    if not config.enabled then return end

    -- Skip gear swaps during critical healing/danger to avoid conflicts
    if HealContext and HealContext.isCritical and HealContext.isCritical() then
        return
    end

    local rules = getNormalizedRules()
    if not rules or #rules == 0 then return end

    local currentTime = now
    if (currentTime - EquipState.lastEquipAction) < EquipState.EQUIP_COOLDOWN then return end

    if not EquipState.needsEquipCheck and EquipState.correctEq then return end

    local ctx = snapshotContext()
    local inventoryIndex = buildInventoryIndex()

    for i = 1, #rules do
        local rule = rules[i]
        if rule.enabled and rulePasses(rule, ctx) then
            local action, missing = computeAction(rule, ctx, inventoryIndex)

            if action then
                if action.kind == "unequip" then
                    if unequipSlot(action.slotIdx) then
                        EquipState.lastEquipAction = currentTime
                        EquipState.correctEq = false
                        EquipState.needsEquipCheck = true
                        EquipState.lastRule = rule
                        return
                    end
                elseif action.kind == "equip" then
                    if equipSlot(action.slotIdx, action.itemId) then
                        EquipState.lastEquipAction = currentTime
                        EquipState.correctEq = false
                        EquipState.needsEquipCheck = true
                        EquipState.lastRule = rule
                        return
                    end
                end
            else
                EquipState.missingItem = missing or false
                EquipState.correctEq = not missing
                EquipState.needsEquipCheck = missing
                EquipState.lastRule = rule
                return
            end
        end
    end

    EquipState.needsEquipCheck = false
end)