local panelName = "EquipperPanel"

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
  EQUIP_COOLDOWN = 200,    -- ms between equip actions
  missingItem = false,
  lastRule = nil,
  correctEq = false,
  needsEquipCheck = true,
  rulesCache = nil,        -- Cached rules for macro iteration
  rulesCacheDirty = true   -- Flag to rebuild cache
}

-- ============================================================================
-- CACHE MANAGEMENT
-- ============================================================================

-- Invalidate rules cache when rules change
local function invalidateRulesCache()
  EquipState.rulesCacheDirty = true
  EquipState.needsEquipCheck = true
  EquipState.correctEq = false
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

local function isEquipped(id)
    local t = {getNeck(), getHead(), getBody(), getRight(), getLeft(), getLeg(), getFeet(), getFinger(), getAmmo()}
    local ids = {id, getInactiveItemId(id), getActiveItemId(id)}

    for i, slot in pairs(t) do
        if slot and table.find(ids, slot:getId()) then
            return true
        end
    end
    return false
end

local function unequipItem(table)
    local slots = {getHead(), getBody(), getLeg(), getFeet(), getNeck(), getLeft(), getRight(), getFinger(), getAmmo()}

    if type(table) ~= "table" then return end
    for i, slot in ipairs(table) do
        local physicalSlot = slots[i]

        if slot == true and physicalSlot then
            local id = physicalSlot:getId()

            if g_game.getClientVersion() >= 910 then
                -- new tibia
                g_game.equipItemId(id)
            else
                -- old tibia
                local dest
                for i, container in ipairs(getContainers()) do
                    local cname = container:getName()
                    if not containerIsFull(container) then
                        if not cname:find("loot") and (cname:find("backpack") or cname:find("bag") or cname:find("chess")) then
                            dest = container
                        end
                        break
                    end
                end

                if not dest then return true end
                local pos = dest:getSlotPosition(dest:getItemsCount())
                g_game.move(physicalSlot, pos, physicalSlot:getCount())
            end
            return true
        end
    end
    return false
end

local function equipItem(id, slot)
    -- need to correct slots...
    if slot == 2 then
        slot = 4
    elseif slot == 3 then
        slot = 7
    elseif slot == 8 then
        slot = 9
    elseif slot == 5 then
        slot = 2
    elseif slot == 4 then
        slot = 8
    elseif slot == 9 then
        slot = 10
    elseif slot == 7 then
        slot = 5
    end


    if g_game.getClientVersion() >= 910 then
        -- new tibia
        return g_game.equipItemId(id)
    else
        -- old tibia
        local item = findItem(id)
        return moveToSlot(item, slot)
    end
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

EquipManager = macro(100, function()
    if not config.enabled then return end
    
    -- Use cached rules (avoids expensive getChildren() call)
    local rules = getCachedRules()
    if not rules or #rules == 0 then return end
    
    -- Non-blocking cooldown check (prevents flicker)
    local currentTime = now
    if (currentTime - EquipState.lastEquipAction) < EquipState.EQUIP_COOLDOWN then return end
    
    -- Skip if nothing changed and we're already correct
    if not EquipState.needsEquipCheck and EquipState.correctEq then return end

    -- Iterate over cached rules (not UI widgets!)
    for i = 1, #rules do
        local rule = rules[i]
        if rule and rule.enabled then

            -- conditions
            local firstCondition = interpreteCondition(rule.mainCondition, rule.mainValue)
            local optionalCondition = nil
            if rule.relation ~= "-" then
                optionalCondition = interpreteCondition(rule.optionalCondition, rule.optValue)
            end

            -- checks
            if finalCheck(firstCondition, rule.relation, optionalCondition) then

                -- performance edits, loop reset
                local resetLoop = not EquipState.missingItem and EquipState.correctEq and EquipState.lastRule == rule
                if resetLoop then 
                    EquipState.needsEquipCheck = false
                    return 
                end

                -- first check unequip
                if unequipItem(rule.data) == true then
                    EquipState.lastEquipAction = currentTime
                    return
                end

                -- equiploop 
                for slot, item in ipairs(rule.data) do
                    if type(item) == "number" and item > 100 then
                        if not isEquipped(item) then
                            if rule.visible then
                                if findItem(item) then
                                    EquipState.missingItem = false
                                    EquipState.lastEquipAction = currentTime
                                    return equipItem(item, slot)
                                else
                                    EquipState.missingItem = true
                                end
                            else
                                EquipState.missingItem = false
                                EquipState.lastEquipAction = currentTime
                                return equipItem(item, slot)
                            end
                        end
                    end
                end

                EquipState.correctEq = not EquipState.missingItem
                EquipState.lastRule = rule
                EquipState.needsEquipCheck = false
                -- even if nothing was done, exit function to hold rule
                return
            end
        end
    end
    
    EquipState.needsEquipCheck = false
end)