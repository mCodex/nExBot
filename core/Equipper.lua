local panelName = "EquipperPanel"
local HealContext = dofile("/core/heal_context.lua")
local EquipperService = dofile("/core/equipper_service.lua")
-- EquipperService loaded if available; keep silent on load

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
        bosses = {},
        activeRule = nil
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

-- ============================================================================
-- RULE NORMALIZATION (precompute slot plans)
-- ============================================================================

-- Delegate normalization to EquipperService for testability and clarity
local function normalizeRule(rule)
  return EquipperService.normalizeRule(rule)
end

local function getNormalizedRules()
    if EquipState.normalizedDirty or not EquipState.normalizedRules then
        local raw = getCachedRules() or {}
        if EquipperService and EquipperService.normalizeRules then
            EquipState.normalizedRules = EquipperService.normalizeRules(raw)
        else
            -- EquipperService missing; using fallback normalization
            local norm = {}
            for i = 1, #raw do
                -- basic fallback normalization
                local r = raw[i]
                local slots = {}
                for idx, val in ipairs(r.data or {}) do
                    if val == true then
                        slots[#slots + 1] = {slotIdx = idx, mode = "unequip"}
                    elseif type(val) == "number" and val > 100 then
                        slots[#slots + 1] = {slotIdx = idx, mode = "equip", itemId = val}
                    end
                end
                norm[#norm + 1] = {
                    name = r.name,
                    enabled = r.enabled ~= false,
                    visible = r.visible ~= false,
                    mainCondition = r.mainCondition,
                    optionalCondition = r.optionalCondition,
                    mainValue = r.mainValue,
                    optValue = r.optValue,
                    relation = r.relation or "-",
                    slots = slots,
                }
            end
            EquipState.normalizedRules = norm
        end
        EquipState.normalizedDirty = false
    end
    return EquipState.normalizedRules
end

-- Get the currently active rule (first enabled rule by index)
-- Return enabled rules in priority order (pure)
local function getEnabledRules()
    if EquipperService and EquipperService.getEnabledRules then
        return EquipperService.getEnabledRules(config)
    end
    local rules = getNormalizedRules() or {}
    local out = {}
    for i, r in ipairs(rules) do
        if r.enabled then out[#out + 1] = r end
    end
    return out
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
    "CaveBot is ON, TargetBot is OFF", -- nothing 18
    "HealBot is enabled", -- nothing 19
    "HealBot is disabled" -- nothing 20
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

    if n == 1 or n == 10 or n == 11 or n == 16 or n == 17 or n == 18 or n == 19 or n == 20 then
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
local refreshRules -- forward-declared so handlers can close over it

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
    widget.enabled:setChecked(rule.enabled and true or false)
  
  -- Set up event handlers (only if not already set)
        if not widget._handlersSet then
        widget.remove.onClick = function()
            local r = widget.ruleData
            local ruleIndex = table.find(config.rules, r)
            if ruleIndex then
                table.remove(config.rules, ruleIndex)
                if config.activeRule and config.activeRule > #config.rules then
                    config.activeRule = nil
                end
            end
            widget:destroy()
            ruleWidgetCache[widgetId] = nil
            listPanel.up:setEnabled(false)
            listPanel.down:setEnabled(false)
            invalidateRulesCache()
            refreshRules()
        end

        widget.visible.onClick = function()
            local r = widget.ruleData
            r.visible = not r.visible
            widget.visible:setColor(r.visible and "green" or "red")
        end

        widget.enabled.onClick = function()
            local r = widget.ruleData
            r.enabled = not r.enabled
            widget.enabled:setChecked(r.enabled and true or false)
            invalidateRulesCache()
            refreshRules()
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

refreshRules = function()
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
        index = #config.rules
    end

    -- Keep existing enabled flags; clear legacy activeRule pointer
    config.activeRule = nil

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

-- `interpreteCondition` removed: condition evaluation now delegated to `EquipperService.evalCondition` with a local fallback `LOCAL_CONDITIONS`.

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

-- Delegate slot/inventory/context helpers to EquipperService when available
local SLOT_MAP = (EquipperService and EquipperService.SLOT_MAP) or {
    [1] = 1, [2] = 4, [3] = 7, [4] = 8, [5] = 2, [6] = 6, [7] = 5, [8] = 9, [9] = 10,
}

local slotHasItem = EquipperService and EquipperService.slotHasItem or function(slotIdx)
    local f = ({[1]=getHead,[2]=getBody,[3]=getLeg,[4]=getFeet,[5]=getNeck,[6]=getLeft,[7]=getRight,[8]=getFinger,[9]=getAmmo})[slotIdx]
    if not f then return nil end
    return f()
end

local slotHasItemId = EquipperService and EquipperService.slotHasItemId or function(slotIdx, itemId)
    local item = slotHasItem(slotIdx)
    if not item then return false end
    local ids = {itemId, getInactiveItemId(itemId), getActiveItemId(itemId)}
    return table.find(ids, item:getId()) and true or false
end

local buildInventoryIndex = EquipperService and EquipperService.buildInventoryIndex or function()
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

local snapshotContext = EquipperService and EquipperService.snapshotContext or function()
    return {
        hp = hppercent(), mp = manapercent(), monsters = getMonsters(), players = getPlayers(),
        target = target() and target():getName():lower() or nil, inPz = isInPz(), paralyzed = isParalyzed(),
        danger = (TargetBot and TargetBot.Danger and TargetBot.Danger()) or 0,
        cavebotOn = CaveBot and CaveBot.isOn and CaveBot.isOn() or false,
        targetbotOn = TargetBot and TargetBot.isOn and TargetBot.isOn() or false,
        healbotOn = (storage["healbot"] and storage["healbot"][1] and storage["healbot"][1].enabled) or false,
        bosses = config.bosses or {},
    }
end

local isUnsafeToUnequip = EquipperService and EquipperService.isUnsafeToUnequip or function(ctx)
    if ctx.inPz then return false end
    if ctx.hp <= 35 then return true end
    if ctx.danger >= 50 then return true end
    return false
end

local function unequipSlot(slotIdx)
    local item = slotHasItem(slotIdx)
    if not item then return false end
    -- Preferred: move equipped item from inventory slot to first available backpack
    
    local dest
    for _, container in ipairs(getContainers()) do
        if not containerIsFull(container) then
            dest = container
            break
        end
    end
    if not dest then
        
        return false
    end
    local pos = dest:getSlotPosition(dest:getItemsCount())
    local ok = g_game.move(item, pos, item:getCount())
    
    return ok
end

local function equipSlot(slotIdx, itemId)
    local mappedSlot = SLOT_MAP[slotIdx] or slotIdx
    

    -- Try direct equip API first (non-blocking request)
    local triedEquipApi = false
    if g_game and g_game.equipItemId then
        triedEquipApi = true
        local ok = pcall(function() g_game.equipItemId(itemId) end)
        
        -- small chance server synchronizes instantly; re-check
        if slotHasItemId(slotIdx, itemId) then
            
            return true
        end
    end

    -- Fallback: try g_game.findItemInContainers first (may find in closed containers)
    local found = nil
    if g_game and g_game.findItemInContainers then
        pcall(function()
            local f = g_game.findItemInContainers(itemId)
            if f then found = f end
        end)
    end
    if not found then
        for _, container in ipairs(getContainers()) do
            for _, it in ipairs(container:getItems() or {}) do
                if it:getId() == itemId then
                    found = it
                    break
                end
            end
            if found then break end
        end
    end
    if not found then
        
            -- item not found in open containers
            return false
    end
    local ok2 = g_game.move(found, {x = 65535, y = mappedSlot, z = 0}, found:getCount())
    
    return slotHasItemId(slotIdx, itemId) or ok2
end

-- ============================================================================
-- CONDITIONS (table-driven)
-- ============================================================================

-- Delegate condition evaluation to EquipperService when available, fallback to local map
local LOCAL_CONDITIONS = {
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
    [19] = function(ctx, v) return ctx.healbotOn end,
    [20] = function(ctx, v) return not ctx.healbotOn end,
}

local function evalCondition(id, value, ctx)
    if EquipperService and EquipperService.evalCondition then
        return EquipperService.evalCondition(id, value, ctx)
    end
    local fn = LOCAL_CONDITIONS[id]
    if not fn then return false end
    return fn(ctx, value)
end

local function rulePasses(rule, ctx)
    if EquipperService and EquipperService.rulePasses then
        return EquipperService.rulePasses(rule, ctx)
    end
    -- fallback
    local mainOk = evalCondition(rule.mainCondition, rule.mainValue, ctx)
    if rule.relation == "-" then return mainOk end
    local optOk = evalCondition(rule.optionalCondition, rule.optValue, ctx)
    if rule.relation == "and" then return mainOk and optOk end
    if rule.relation == "or" then return mainOk or optOk end
    return mainOk
end

-- ============================================================================
-- ============================================================================
-- ACTION PLANNING (pure decision-making)
-- ============================================================================

local function computeAction(rule, ctx, inventoryIndex)
    -- Delegate pure decision making to service for testability/consistency
    if EquipperService and EquipperService.computeAction then
        return EquipperService.computeAction(rule, ctx, inventoryIndex, {
            slotHasItem = slotHasItem,
            slotHasItemId = slotHasItemId,
            isUnsafeToUnequip = isUnsafeToUnequip,
        })
    end
    -- If service missing, conservatively return no action and mark missing
    return nil, true
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

EquipManager = macro(1000, function()
    if not config.enabled then return end

    -- Debug: enabled for troubleshooting
    

    -- Skip gear swaps during critical healing/danger to avoid conflicts
    if HealContext and HealContext.isCritical and HealContext.isCritical() then
        return
    end

    local rules = getEnabledRules()
    if not rules or #rules == 0 then return end

    local currentTime = now
    if (currentTime - EquipState.lastEquipAction) < EquipState.EQUIP_COOLDOWN then return end

    if not EquipState.needsEquipCheck and EquipState.correctEq then return end

    local ctx = snapshotContext()
    local inventoryIndex = buildInventoryIndex()

    for _, rule in ipairs(rules) do
        if rulePasses(rule, ctx) then
            local action, missing = computeAction(rule, ctx, inventoryIndex)
            if action then
                if action.kind == "unequip" then
                    
                    if unequipSlot(action.slotIdx) then
                        EquipState.lastEquipAction = currentTime
                        EquipState.correctEq = false
                        EquipState.needsEquipCheck = true
                        EquipState.lastRule = rule
                        return
                    else
                        
                    end
                elseif action.kind == "equip" then
                    
                    if equipSlot(action.slotIdx, action.itemId) then
                        EquipState.lastEquipAction = currentTime
                        EquipState.correctEq = false
                        EquipState.needsEquipCheck = true
                        EquipState.lastRule = rule
                        return
                    else
                        
                    end
                end
            else
                EquipState.missingItem = missing or false
                EquipState.correctEq = not missing
                EquipState.needsEquipCheck = missing
                EquipState.lastRule = rule
                -- continue to next rule
            end
        end
    end

    EquipState.needsEquipCheck = false
end)

-- ============================================================================
-- EVENT-DRIVEN EQUIPMENT MANAGEMENT
-- Listen to equipment changes for immediate response
-- ============================================================================

EventBus.on("equipment:change", function(slotId, slotName, currentId, lastId, item)
    if not config.enabled then return end

    -- Debug: enabled for troubleshooting
    

    -- Skip if recently equipped by us to avoid loops
    if now - EquipState.lastEquipAction < EquipState.EQUIP_COOLDOWN then return end

    -- Skip during critical healing
    if HealContext and HealContext.isCritical and HealContext.isCritical() then return end

    local rules = getEnabledRules()
    if not rules or #rules == 0 then return end

    local ctx = snapshotContext()
    local inventoryIndex = buildInventoryIndex()

    for _, rule in ipairs(rules) do
        
        if rulePasses(rule, ctx) then
            
            for _, slotPlan in ipairs(rule.slots) do
                if SLOT_MAP[slotPlan.slotIdx] == slotId and slotPlan.mode == "equip" and slotPlan.itemId then
                    
                    if not slotHasItemId(slotPlan.slotIdx, slotPlan.itemId) then
                        
                        local hasItem = inventoryIndex[slotPlan.itemId] ~= nil
                        if not hasItem and g_game and g_game.findItemInContainers then
                            local ok, found = pcall(g_game.findItemInContainers, slotPlan.itemId)
                            hasItem = ok and found ~= nil
                        end
                        if hasItem then
                            
                            if equipSlot(slotPlan.slotIdx, slotPlan.itemId) then
                                EquipState.lastEquipAction = now
                                EquipState.correctEq = false
                                EquipState.needsEquipCheck = true
                            else
                                
                            end
                            return
                        else
                            
                        end
                    else
                        
                    end
                end
            end
        else
            
        end
    end
end)

-- Debug helpers: call from Lua console to force an equip/unequip and print result.
-- debug helpers removed